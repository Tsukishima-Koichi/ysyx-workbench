#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "verilated.h"
#include "svdpi.h"     
#include "Vcpu__Dpi.h" 
#include "Vcpu.h"
#include "memory.h"  // 引入内存和加载模块

svScope regfile_scope = NULL;

extern "C" void set_regfile_scope() {
    regfile_scope = svGetScope();
}
extern "C" int get_gpr(int idx);

int main(int argc, char** argv) {
    VerilatedContext* contextp = new VerilatedContext;
    contextp->commandArgs(argc, argv);
    Vcpu* top = new Vcpu{contextp};

    memset(pmem, 0, PMEM_SIZE);

    const char* image_file = NULL;
    for (int i = 1; i < argc; i++) {
        if (argv[i][0] != '-') {
            image_file = argv[i];
            break;
        }
    }
    if (image_file == NULL) image_file = "./test_hex/test_8.hex";
    
    // 调用 memory.cpp 中的函数
    load_image(image_file);

    top->clk = 0; top->rst = 1; top->eval();
    top->clk = 1; top->eval();
    top->rst = 0; 
    
    printf("--- CPU Simulation Start ---\n");

    // int max_cycles = 500000000; 
    int cycles = 0;

    // 仿真主循环
    // while (!contextp->gotFinish() && cycles < max_cycles) {
    while (!contextp->gotFinish()) {
        uint32_t last_pc = top->pc;

        top->clk = 0; top->eval();
        top->clk = 1; top->eval();
        cycles++;

        // 停机条件判断
        if (top->inst == 0x00100073 || top->pc == last_pc) {
            if (top->inst == 0x00100073) {
                printf("\n[Halt] ebreak at PC = 0x%08x after %d cycles\n", top->pc, cycles);
            } else {
                printf("\n[Halt] Dead Loop at PC = 0x%08x after %d cycles\n", top->pc, cycles);
            }
            
            if (regfile_scope != NULL) {
                svSetScope(regfile_scope);
                int a0_val = get_gpr(10); 
                if (a0_val == 0) {
                    printf("\33[1;32mHIT GOOD TRAP\33[0m\n");
                } else {
                    printf("\33[1;31mHIT BAD TRAP (a0 = %d, expected 0)\33[0m\n", a0_val);
                    return 1; 
                }
            }
            break; 
        }        
    }

    // if (cycles >= max_cycles) {
    //     printf("\33[1;31mSIMULATION TIMEOUT\33[0m\n");
    //     return 1; 
    // }
    
    printf("--- CPU Simulation End ---\n");
    delete top;
    delete contextp;
    return 0; 
}
