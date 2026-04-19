#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "verilated.h"
#include "svdpi.h"     
#include "Vcpu__Dpi.h" 
#include "Vcpu.h"
#include "memory.h"  // 引入内存和加载模块


// #define GEN_WAVEFORM  // 定义宏以启用波形生成
// #define MAX_CYCLES 50000  // 定义最大仿真周期数，防止死循环

#ifdef GEN_WAVEFORM
#include "verilated_vcd_c.h"  // 引入波形导出相关的头文件
#endif

svScope regfile_scope = NULL;

extern "C" void set_regfile_scope() {
    regfile_scope = svGetScope();
}
extern "C" int get_gpr(int idx);

int main(int argc, char** argv) {
    VerilatedContext* contextp = new VerilatedContext;
    contextp->commandArgs(argc, argv);
    Vcpu* top = new Vcpu{contextp};

    #ifdef GEN_WAVEFORM
    printf("Waveform generation enabled. Output will be saved to ./build/wave.vcd\n");
    // 初始化波形追踪
    Verilated::traceEverOn(true);
    VerilatedVcdC* tfp = new VerilatedVcdC;
    top->trace(tfp, 99);                  // 99 表示追踪所有的层级深度
    tfp->open("build/wave.vcd");          // 将波形文件输出到 build 目录下
    #endif

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

    #ifdef MAX_CYCLES
    printf("Maximum simulation cycles set to %d\n", MAX_CYCLES);
    int max_cycles = MAX_CYCLES; 
    #endif
    
    int cycles = 0;

    // 仿真主循环
    while (!contextp->gotFinish()) {
        top->clk = 0; top->eval();

        #ifdef GEN_WAVEFORM
        contextp->timeInc(1);             // 时间步进
        tfp->dump(contextp->time());      // 记录时钟低电平时的波形
        #endif

        top->clk = 1; top->eval();

        #ifdef GEN_WAVEFORM
        contextp->timeInc(1);             // 时间步进
        tfp->dump(contextp->time());      // 记录时钟高电平时的波形
        #endif

        cycles++;

        // 使用 halt_req判定
        if (top->halt_req) {

            printf("\n[Halt] ebreak detected after %d cycles\n", cycles);
            
            if (regfile_scope != NULL) {
                svSetScope(regfile_scope);
                int a0_val = get_gpr(10); 
                if (a0_val == 0) {
                    printf("\33[1;32mHIT GOOD TRAP\33[0m\n");
                } else {
                    printf("\33[1;31mHIT BAD TRAP (a0 = %d, expected 0)\33[0m\n", a0_val);

                    #ifdef GEN_WAVEFORM
                    // 🌟 核心修复：在程序异常退出前，强行把波形刷入硬盘！
                    if (tfp) {
                        tfp->close();
                    }
                    #endif

                    return 1; 
                }
            }
            break; 
        }

        #ifdef MAX_CYCLES
        if (cycles >= max_cycles) {
            printf("\33[1;31mSIMULATION TIMEOUT\33[0m\n");
                    #ifdef GEN_WAVEFORM
                    if (tfp) {
                        tfp->close();
                    }
                    #endif
            return 1; 
        }
        #endif
    }

    
    #ifdef GEN_WAVEFORM
    // 仿真结束时，一定要关闭波形文件，否则文件会损坏！
    tfp->close();
    #endif
    
    printf("--- CPU Simulation End ---\n");

    delete top;
    delete contextp;
    return 0; 
}
