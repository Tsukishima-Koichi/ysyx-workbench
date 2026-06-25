#include <stdio.h>
#include <stdlib.h>
#include "verilated.h"
#ifdef DUAL_ISSUE
#include "Vcpu_dual.h"
#else
#include "Vcpu.h"
#endif
#include "memory.h"
#include "difftest.h"
#include "monitor.h"
#include "svdpi.h"

// Performance counter DPI import
#ifdef DUAL_ISSUE
extern "C" void perf_get_counters_dual(
    int* commits, int* branches, int* mispredicts,
    int* early_flushes, int* micro_flushes, int* br_flushes,
    int* stall_front, int* stall_back, int* dual_issues
);
#else
extern "C" void perf_get_counters(
    int* commits, int* branches, int* mispredicts,
    int* early_flushes, int* micro_flushes, int* br_flushes,
    int* stall_front, int* stall_back
);
#endif

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
#ifdef DUAL_ISSUE
    Vcpu_dual* top = new Vcpu_dual{contextp};
#else
    Vcpu* top = new Vcpu{contextp};
#endif

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
            printf("\n\n[Halt] Program finished and entered infinite loop at PC=0x%08x after %u cycles!\n", top->halt_pc, cycles);

            // ==========================================
            //  Performance Summary
            // ==========================================
            int p_commits, p_branches, p_mispredicts;
            int p_early_flushes, p_micro_flushes, p_br_flushes;
            int p_stall_front, p_stall_back, p_dual = 0;
            svSetScope(svGetScopeFromName("TOP.cpu_dual.u_myCPU"));
#ifdef DUAL_ISSUE
            perf_get_counters_dual(&p_commits, &p_branches, &p_mispredicts,
                              &p_early_flushes, &p_micro_flushes, &p_br_flushes,
                              &p_stall_front, &p_stall_back, &p_dual);
#else
            svSetScope(svGetScopeFromName("TOP.cpu.u_myCPU"));
            perf_get_counters(&p_commits, &p_branches, &p_mispredicts,
                              &p_early_flushes, &p_micro_flushes, &p_br_flushes,
                              &p_stall_front, &p_stall_back);
#endif

            printf("\n========== Performance Summary ==========\n");
            printf("Cycles:              %u\n", cycles);
            printf("Committed Insns:     %d\n", p_commits);
            if (cycles > 0) printf("IPC:                 %.4f\n", (float)p_commits / cycles);
#ifdef DUAL_ISSUE
            printf("Dual-Issue Cycles:   %d (%.1f%%)\n", p_dual, 100.0 * p_dual / (cycles > 0 ? cycles : 1));
#endif
            if (p_branches > 0) {
                printf("Branches Predicted:  %d\n", p_branches);
                printf("Branch Mispredicts:  %d\n", p_mispredicts);
                printf("Branch Accuracy:     %.2f%%\n", 100.0 * (p_branches - p_mispredicts) / p_branches);
                printf("Early RF Flushes:    %d (%.1f%% of mispredicts)\n", p_early_flushes, 100.0 * p_early_flushes / p_mispredicts);
                printf("Micro-flushes:       %d\n", p_micro_flushes);
                printf("Global BR Flushes:   %d\n", p_br_flushes);
            }
            if (cycles > 0) {
                printf("Frontend Stall:      %d cyc (%.1f%%)\n", p_stall_front, 100.0 * p_stall_front / cycles);
                printf("Backend Stall:       %d cyc (%.1f%%)\n",  p_stall_back,  100.0 * p_stall_back  / cycles);
            }
            printf("==========================================\n");

            // ==========================================
            //  Memory Dump
            // ==========================================
            uint32_t addr1 = 0x80200020;
            uint32_t addr2 = 0x80200040;
            uint32_t addr_pass = 0x80100000;
            uint32_t addr_fail = 0x80100004;

            uint32_t val1 = *(uint32_t*)(pmem + (addr1 - PMEM_BASE));
            uint32_t val2 = *(uint32_t*)(pmem + (addr2 - PMEM_BASE));
            uint32_t val_pass = *(uint32_t*)(pmem + (addr_pass - PMEM_BASE));
            uint32_t val_fail = *(uint32_t*)(pmem + (addr_fail - PMEM_BASE));

            printf("\n========== Memory Dump ==========\n");
            printf("Mem[0x%08x] = 0x%08x (checksum1)\n", addr1, val1);
            printf("Mem[0x%08x] = 0x%08x (checksum2)\n", addr2, val2);
            printf("Mem[0x%08x] = 0x%08x (pass_count)\n", addr_pass, val_pass);
            printf("Mem[0x%08x] = 0x%08x (fail_count)\n", addr_fail, val_fail);
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

sim_end:
    #ifdef GEN_WAVEFORM
    if (tfp) tfp->close();
    #endif
    printf("--- CPU Simulation End ---\n");

    delete top;
    delete contextp;
    return 0; 
}
