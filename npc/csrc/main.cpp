#include <stdio.h>
#include <stdlib.h>
#include "verilated.h"
#include "Vcpu.h"
#include "memory.h"
#include "difftest.h"
#include "monitor.h"
#include "svdpi.h"

// Performance counter DPI (from myCPU.sv)
extern "C" void perf_get_counters(
    int* commits, int* branches, int* mispredicts,
    int* early_flushes, int* micro_flushes, int* br_flushes,
    int* stall_front, int* stall_back, int* dual_issues
);

int main(int argc, char** argv) {
    VerilatedContext* contextp = new VerilatedContext;
    contextp->commandArgs(argc, argv);
    Vcpu* top = new Vcpu{contextp};

    parse_args_and_load(argc, argv);
    init_difftest();

    top->clk = 0; top->rst = 1; top->eval();
    top->clk = 1; top->eval();
    top->rst = 0;

    printf("--- CPU Simulation Start ---\n");
    unsigned int cycles = 0;

    while (!contextp->gotFinish()) {
        top->clk = 0; top->eval();
        top->clk = 1; top->eval();
        cycles++;

        if (!difftest_check()) goto sim_end;

        // inst0 commit
        if (top->commit_valid) {
            if (!difftest_commit(top->commit_pc, 0)) goto sim_end;
        }
        // inst1 commit (dual-issue)
        if (top->commit_valid_1) {
            if (!difftest_commit(top->commit_pc_1, 1)) goto sim_end;
        }

        if (cycles % 1000000 == 0) {
            printf("\r[Simulation Progress] Running... %uM cycles, Current PC = 0x%08x", cycles / 1000000, top->pc);
            fflush(stdout);
        }

        if (top->dead_loop) {
            printf("\n\n[Halt] Program finished at PC=0x%08x after %u cycles!\n", top->halt_pc, cycles);

            int p_commits, p_branches, p_mispredicts;
            int p_early_f, p_micro_f, p_br_f;
            int p_stall_f, p_stall_b, p_dual = 0;
            svSetScope(svGetScopeFromName("TOP.cpu.u_myCPU"));
            perf_get_counters(&p_commits, &p_branches, &p_mispredicts,
                              &p_early_f, &p_micro_f, &p_br_f,
                              &p_stall_f, &p_stall_b, &p_dual);

            printf("\n========== Performance Summary ==========\n");
            printf("Cycles:              %u\n", cycles);
            printf("Committed Insns:     %d\n", p_commits);
            if (cycles > 0) printf("IPC:                 %.4f\n", (float)p_commits / cycles);
            printf("Dual-Issue Cycles:   %d (%.1f%%)\n", p_dual, 100.0 * p_dual / (cycles > 0 ? cycles : 1));
            if (p_branches > 0) {
                printf("Branches Predicted:  %d\n", p_branches);
                printf("Branch Mispredicts:  %d\n", p_mispredicts);
                printf("Branch Accuracy:     %.2f%%\n", 100.0 * (p_branches - p_mispredicts) / p_branches);
                printf("Early RF Flushes:    %d (%.1f%% of mispredicts)\n", p_early_f, 100.0 * p_early_f / p_mispredicts);
                printf("Micro-flushes:       %d\n", p_micro_f);
                printf("Global BR Flushes:   %d\n", p_br_f);
            }
            if (cycles > 0) {
                printf("Frontend Stall:      %d cyc (%.1f%%)\n", p_stall_f, 100.0 * p_stall_f / cycles);
                printf("Backend Stall:       %d cyc (%.1f%%)\n",  p_stall_b, 100.0 * p_stall_b / cycles);
            }
            printf("==========================================\n");

            uint32_t val1 = *(uint32_t*)(pmem + (0x80200020 - PMEM_BASE));
            uint32_t val2 = *(uint32_t*)(pmem + (0x80200040 - PMEM_BASE));
            uint32_t val_pass = *(uint32_t*)(pmem + (0x80100000 - PMEM_BASE));
            uint32_t val_fail = *(uint32_t*)(pmem + (0x80100004 - PMEM_BASE));
            printf("\n========== Memory Dump ==========\n");
            printf("Mem[0x80200020] = 0x%08x (checksum1)\n", val1);
            printf("Mem[0x80200040] = 0x%08x (checksum2)\n", val2);
            printf("Mem[0x80100000] = 0x%08x (pass_count)\n", val_pass);
            printf("Mem[0x80100004] = 0x%08x (fail_count)\n", val_fail);
            printf("=================================\n\n");
            break;
        }

        if (top->halt_req) {
            printf("\n[Halt] ebreak detected after %d cycles\n", cycles);
            int a0_val = get_gpr(10);
            if (a0_val == 0) printf("\33[1;32mHIT GOOD TRAP\33[0m\n");
            else             printf("\33[1;31mHIT BAD TRAP (a0 = %d)\33[0m\n", a0_val);
            break;
        }
    }

sim_end:
    printf("--- CPU Simulation End ---\n");
    delete top;
    delete contextp;
    return 0;
}
