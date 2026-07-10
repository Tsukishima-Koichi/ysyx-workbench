#include <stdio.h>
#include <stdlib.h>
#include "verilated.h"
#include "Vcpu.h"
#include "memory.h"
#include "difftest.h"
#include "monitor.h"
#include "svdpi.h"

// Performance counter DPI (from cpu.sv)
extern "C" void perf_get_counters(
    int* commits, int* branches, int* mispredicts,
    int* stall_front, int* stall_back
);
// Extended counters from myCPU.sv
extern "C" int get_perf_counter(int idx);

// // 宏定义最好统一移到 Makefile，这里仅作演示保留
// #define GEN_WAVEFORM 
// #define MAX_CYCLES 500000 
// #define NEMU_TRACE

#ifdef GEN_WAVEFORM
#include "verilated_vcd_c.h"
#endif

int main(int argc, char** argv) {
    VerilatedContext* contextp = new VerilatedContext;
    contextp->commandArgs(argc, argv);
    Vcpu* top = new Vcpu{contextp};

    #ifdef GEN_WAVEFORM
    printf("Waveform generation enabled.\n");
    Verilated::traceEverOn(true);
    VerilatedVcdC* tfp = new VerilatedVcdC;
    top->trace(tfp, 99);                  
    tfp->open("build/wave.vcd");          
    #endif

    // 1. 解析参数并加载二进制镜像
    parse_args_and_load(argc, argv);

    // 2. 初始化 NEMU DiffTest
    init_difftest();

    // 3. 复位 CPU
    top->clk = 0; top->rst = 1; top->eval();
    top->clk = 1; top->eval();
    top->rst = 0; 
    
    printf("--- CPU Simulation Start ---\n");
    unsigned int cycles = 0;

    // 4. 仿真主循环
    while (!contextp->gotFinish()) {
        top->clk = 0; top->eval();
        #ifdef GEN_WAVEFORM
        contextp->timeInc(1); tfp->dump(contextp->time());
        #endif

        top->clk = 1; top->eval();
        #ifdef GEN_WAVEFORM
        contextp->timeInc(1); tfp->dump(contextp->time());
        #endif

        cycles++;

        // --- 核心校验逻辑 ---
        // 检查上一拍的 DiffTest 结果，如果报错则直接终止循环
        if (!difftest_check()) goto sim_end;

        // 当前拍有指令写回时，比对 PC，并通过 NEMU 步进 1 条指令
        if (top->commit_valid) {
            if (!difftest_commit(top->commit_pc)) goto sim_end;
        }

        // --- 状态与监控输出 ---
        if (cycles % 1000000 == 0) {
            printf("\r[Simulation Progress] Running... %uM cycles, Current PC = 0x%08x", cycles / 1000000, top->pc);
            fflush(stdout); 
        }

        if (top->dead_loop) {
            printf("\n\n[Halt] Program finished and entered infinite loop at PC=0x80000010 after %u cycles!\n", cycles);
            
            // ==========================================
            //  Memory Dump
            // ==========================================
            uint32_t addr1 = 0x80200020;
            uint32_t addr2 = 0x80200040;
            
            // 计算地址在物理内存数组 pmem 中的相对偏移量，并强制转换为 32 位指针进行读取
            uint32_t val1 = *(uint32_t*)(pmem + (addr1 - PMEM_BASE));
            uint32_t val2 = *(uint32_t*)(pmem + (addr2 - PMEM_BASE));
            
            printf("\n========== Memory Dump ==========\n");
            printf("Mem[0x%08x] = 0x%08x\n", addr1, val1);
            printf("Mem[0x%08x] = 0x%08x\n", addr2, val2);
            printf("=================================\n\n");
            
            break; 
        }

        if (top->halt_req) { // ebreak
            printf("\n[Halt] ebreak detected after %d cycles\n", cycles);
            // 这里可以直接调用我们保留在 difftest.h 里的 extern get_gpr(10) 来查 a0 寄存器
            int a0_val = get_gpr(10); 
            if (a0_val == 0) printf("\33[1;32mHIT GOOD TRAP\33[0m\n");
            else             printf("\33[1;31mHIT BAD TRAP (a0 = %d)\33[0m\n", a0_val);
            break; 
        }

        #ifdef MAX_CYCLES
        if (cycles >= MAX_CYCLES) {
            printf("\n\33[1;31mSIMULATION TIMEOUT\33[0m\n");
            break; 
        }
        #endif
    }

    // ==========================================
    //  Performance Summary
    // ==========================================
    {
        int p_commits, p_branches, p_mispredicts, p_stall_f, p_stall_b;
        svSetScope(svGetScopeFromName("TOP.cpu"));
        perf_get_counters(&p_commits, &p_branches, &p_mispredicts, &p_stall_f, &p_stall_b);

        // 从 myCPU 内部的 perf_counters 模块获取扩展计数器
        svSetScope(svGetScopeFromName("TOP.cpu.u_myCPU.u_perf"));
        int p_load_stall    = get_perf_counter(2);
        int p_mdu_stall     = get_perf_counter(3);
        int p_redirect      = get_perf_counter(4);
        int p_lw_count      = get_perf_counter(5);
        int p_lb_lh_count   = get_perf_counter(6);
        int p_load_use_hzd  = get_perf_counter(7);
        int p_wb_fwd_hits   = get_perf_counter(8);
        int p_min_sp        = get_perf_counter(9);
        int p_max_dram      = get_perf_counter(10);
        int p_pred_bubble   = get_perf_counter(11);

        int p_total_loads   = p_lw_count + p_lb_lh_count;

        printf("\n========== Performance Summary ==========\n");
        printf("Cycles:              %u\n", cycles);
        printf("Committed Insns:     %d\n", p_commits);
        if (cycles > 0) printf("IPC:                 %.4f\n", (float)p_commits / cycles);
        if (p_branches > 0) {
            printf("Branches/Jumps:      %d\n", p_branches);
            printf("Mispredicts:         %d\n", p_mispredicts);
            printf("Branch Accuracy:     %.2f%%\n", 100.0 * (p_branches - p_mispredicts) / p_branches);
        }
        printf("------------------------------------------\n");
        printf("--- Stall Breakdown ---\n");
        if (cycles > 0) {
            printf("Frontend Stalls:     %d cyc (%.1f%%)\n", p_stall_f, 100.0 * p_stall_f / cycles);
            printf("Backend Stalls:      %d cyc (%.1f%%)\n",  p_stall_b, 100.0 * p_stall_b / cycles);
            printf("Load-Use Stalls:     %d cyc (%.1f%%)\n", p_load_stall, 100.0 * p_load_stall / cycles);
            printf("MDU Stalls:          %d cyc (%.1f%%)\n", p_mdu_stall, 100.0 * p_mdu_stall / cycles);
            printf("Redirect Flushes:    %d cyc (%.1f%%)\n", p_redirect, 100.0 * p_redirect / cycles);
            printf("Pred-Taken Bubbles:  %d cyc (%.1f%%)\n", p_pred_bubble, 100.0 * p_pred_bubble / cycles);
        }
        printf("------------------------------------------\n");
        printf("--- Memory Profile ---\n");
        printf("LW instructions:     %d\n", p_lw_count);
        printf("LB/LH instructions:  %d\n", p_lb_lh_count);
        printf("Total loads:         %d\n", p_total_loads);
        printf("Load-Use hazards:    %d\n", p_load_use_hzd);
        if (p_total_loads > 0)
            printf("Load-Use rate:       %.1f%% of loads\n", 100.0 * p_load_use_hzd / p_total_loads);
        printf("Min SP (x2):         0x%08x\n", p_min_sp);
        printf("Max DRAM addr:       0x%08x", p_max_dram);
        if (p_stall_f > 0 && p_load_stall > 0)
            printf("  (stack=0x%x ~ 0x%x)", p_min_sp, p_max_dram);
        printf("\n");
        printf("------------------------------------------\n");
        printf("--- Forwarding ---\n");
        printf("WB forwarding hits:  %d\n", p_wb_fwd_hits);
        if (p_commits > 0)
            printf("Fwd rate:            %.1f%% of commits\n", 100.0 * p_wb_fwd_hits / p_commits);
        printf("==========================================\n");
    }

sim_end:
    #ifdef GEN_WAVEFORM
    if (tfp) tfp->close();
    #endif
    printf("--- CPU Simulation End ---\n");

    delete top;
    delete contextp;
    return 0; 
}
