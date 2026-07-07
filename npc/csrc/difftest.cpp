#include "difftest.h"
#include "memory.h"
#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include "svdpi.h"

svScope regfile_scope = NULL;
svScope csr_scope = NULL;

extern "C" void set_regfile_scope() { regfile_scope = svGetScope(); }
extern "C" void set_csr_scope()     { csr_scope = svGetScope(); }
extern "C" int get_gpr(int idx);
extern "C" int get_csr(int idx);

#ifdef NEMU_TRACE
#include <dlfcn.h>

#define DIFFTEST_TO_DUT 0
#define DIFFTEST_TO_REF 1

struct CPU_state {
    uint32_t gpr[32];
    uint32_t pc;
    uint32_t mepc;
    uint32_t mcause;
    uint32_t mtvec;
    uint32_t mstatus;
    uint32_t mscratch;
};

void (*nemu_difftest_memcpy)(uint32_t addr, void *buf, size_t n, int direction);
void (*nemu_difftest_regcpy)(void *dut, int direction);
void (*nemu_difftest_exec)(uint64_t n);
void (*nemu_difftest_init)(void);

static bool difftest_check_pending = false;
static uint32_t difftest_check_pc = 0;

void init_difftest() {
    printf("DiffTest tracing enabled. NEMU API will be loaded dynamically.\n");
    void *handle = dlopen("../nemu/build/riscv32-nemu-interpreter-so", RTLD_LAZY);
    if (!handle) {
        printf("\33[1;31mError loading NEMU: %s\33[0m\n", dlerror());
        exit(-1);
    }

    nemu_difftest_memcpy = (void (*)(uint32_t, void *, size_t, int))dlsym(handle, "difftest_memcpy");
    nemu_difftest_regcpy = (void (*)(void *, int))dlsym(handle, "difftest_regcpy");
    nemu_difftest_exec   = (void (*)(uint64_t))dlsym(handle, "difftest_exec");
    nemu_difftest_init   = (void (*)(void))dlsym(handle, "difftest_init");

    assert(nemu_difftest_memcpy && nemu_difftest_regcpy && nemu_difftest_exec && nemu_difftest_init);

    nemu_difftest_init();
    nemu_difftest_memcpy(0x80000000, pmem, PMEM_SIZE, DIFFTEST_TO_REF);

    CPU_state initial_state = {0};
    initial_state.pc = 0x80000000;
    initial_state.mstatus = 0x1800;
    nemu_difftest_regcpy(&initial_state, DIFFTEST_TO_REF);
}

bool difftest_check() {
    if (!difftest_check_pending) return true;

    CPU_state ref_r;
    nemu_difftest_regcpy(&ref_r, DIFFTEST_TO_DUT);

    if (regfile_scope != NULL) {
        svSetScope(regfile_scope);
        for (int i = 0; i < 32; i++) {
            uint32_t dut_val = (uint32_t)get_gpr(i);
            if (dut_val != ref_r.gpr[i]) {
                printf("\n\33[1;31m[DiffTest Error] Register x%d Mismatch at PC=0x%08x!\33[0m\n", i, difftest_check_pc);
                printf("DUT x%d = 0x%08x | NEMU x%d = 0x%08x\n", i, dut_val, i, ref_r.gpr[i]);
                return false;
            }
        }
    }

    if (csr_scope != NULL) {
        svSetScope(csr_scope);
        uint32_t dut_mstatus  = (uint32_t)get_csr(0x300);
        uint32_t dut_mtvec    = (uint32_t)get_csr(0x305);
        uint32_t dut_mscratch = (uint32_t)get_csr(0x340);
        uint32_t dut_mepc     = (uint32_t)get_csr(0x341);
        uint32_t dut_mcause   = (uint32_t)get_csr(0x342);

        if (dut_mstatus != ref_r.mstatus) {
            printf("\n\33[1;31m[DiffTest Error] mstatus Mismatch at PC=0x%08x!\33[0m\n", difftest_check_pc);
            printf("DUT mstatus = 0x%08x | NEMU mstatus = 0x%08x\n", dut_mstatus, ref_r.mstatus);
            return false;
        }
        if (dut_mtvec != ref_r.mtvec) {
            printf("\n\33[1;31m[DiffTest Error] mtvec Mismatch at PC=0x%08x!\33[0m\n", difftest_check_pc);
            printf("DUT mtvec = 0x%08x | NEMU mtvec = 0x%08x\n", dut_mtvec, ref_r.mtvec);
            return false;
        }
        if (dut_mepc != ref_r.mepc) {
            printf("\n\33[1;31m[DiffTest Error] mepc Mismatch at PC=0x%08x!\33[0m\n", difftest_check_pc);
            printf("DUT mepc = 0x%08x | NEMU mepc = 0x%08x\n", dut_mepc, ref_r.mepc);
            return false;
        }
        if (dut_mcause != ref_r.mcause) {
            printf("\n\33[1;31m[DiffTest Error] mcause Mismatch at PC=0x%08x!\33[0m\n", difftest_check_pc);
            printf("DUT mcause = 0x%08x | NEMU mcause = 0x%08x\n", dut_mcause, ref_r.mcause);
            return false;
        }
        if (dut_mscratch != ref_r.mscratch) {
            printf("\n\33[1;31m[DiffTest Error] mscratch Mismatch at PC=0x%08x!\33[0m\n", difftest_check_pc);
            printf("DUT mscratch = 0x%08x | NEMU mscratch = 0x%08x\n", dut_mscratch, ref_r.mscratch);
            return false;
        }
    }

    difftest_check_pending = false;
    return true;
}

bool difftest_commit(uint32_t commit_pc, int slot) {
    CPU_state ref_r;
    nemu_difftest_regcpy(&ref_r, DIFFTEST_TO_DUT);

    if (ref_r.pc != commit_pc) {
        printf("\n\33[1;31m[DiffTest Error] PC Mismatch (slot=%d)!\33[0m\n", slot);
        printf("DUT PC: 0x%08x | NEMU PC: 0x%08x (diff=%+d)\n", commit_pc, ref_r.pc, (int)(commit_pc - ref_r.pc));
        return false;
    }

    nemu_difftest_exec(1);
    difftest_check_pending = true;
    difftest_check_pc = commit_pc;
    return true;
}

uint32_t difftest_get_nemu_pc() {
    CPU_state ref_r;
    nemu_difftest_regcpy(&ref_r, DIFFTEST_TO_DUT);
    return ref_r.pc;
}

#else
void init_difftest() {}
bool difftest_check() { return true; }
bool difftest_commit(uint32_t commit_pc, int slot) { return true; }
#endif
