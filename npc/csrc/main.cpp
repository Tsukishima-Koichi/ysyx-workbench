#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "verilated.h"
#include "svdpi.h"     
#include "Vcpu__Dpi.h" 
#include "Vcpu.h"
#include "memory.h"  // 引入内存和加载模块


// #define GEN_WAVEFORM  // 定义宏以启用波形生成
// #define MAX_CYCLES 5000  // 定义最大仿真周期数，防止死循环

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

    // 🌟 修改：默认文件改为 .bin 后缀（请根据你的实际编译产物路径修改）
    const char* irom_file = "./bin/test_src/irom.bin"; 
    const char* dram_file = "./bin/test_src/dram.bin"; 
    uint32_t dram_addr = 0x80100000; // 默认 DRAM 起始地址

    // 参数解析逻辑：支持 -i (IROM), -d (DRAM), -a (DRAM地址)
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-i") == 0 && i + 1 < argc) {
            irom_file = argv[++i];
        } else if (strcmp(argv[i], "-d") == 0 && i + 1 < argc) {
            dram_file = argv[++i];
        } else if (strcmp(argv[i], "-a") == 0 && i + 1 < argc) {
            sscanf(argv[++i], "%x", &dram_addr);
        } else if (argv[i][0] != '-') {
            irom_file = argv[i];          
        }
    }
    
    // 加载镜像
    load_image(irom_file, PMEM_BASE);           // IROM 加载到 0x80000000
    if (dram_file != NULL) {
        load_image(dram_file, dram_addr);       // DRAM 加载到 0x80100000
    }

    top->clk = 0; top->rst = 1; top->eval();
    top->clk = 1; top->eval();
    top->rst = 0; 
    
    printf("--- CPU Simulation Start ---\n");

    #ifdef MAX_CYCLES
    printf("Maximum simulation cycles set to %d\n", MAX_CYCLES);
    int max_cycles = MAX_CYCLES; 
    #endif
    
    unsigned int cycles = 0;

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

        // ==========================================
        // 🌟 新增：每 1000 个周期打印一次进度，\r 保证只在同一行刷新
        // ==========================================
        if (cycles % 1000000 == 0) {
            // 增加 PC 值的打印，使用 %08x 以 8 位十六进制格式显示
            printf("\r[Simulation Progress] Running... %uM cycles, Current PC = 0x%08x", cycles / 1000000, top->pc);
            fflush(stdout); // 强制立刻刷新输出缓冲区
        }

        // ==========================================
        // 🌟 修改：检测程序是否进入了死循环 (基于安全信号 dead_loop)
        // ==========================================
        if (top->dead_loop) {
            printf("\n\n[Halt] Program finished and entered infinite loop at PC=0x80000010 after %u cycles!\n", cycles);
            
            // 在这里同样可以把内存 Dump 出来看结果
            uint32_t offset_20 = 0x80200020 - 0x80000000; 
            uint32_t offset_40 = 0x80200040 - 0x80000000; 
            printf("\n========== Memory Dump ==========\n");
            printf("Mem[0x80200020] = 0x%08X\n", *((uint32_t*)(pmem + offset_20)));
            printf("Mem[0x80200040] = 0x%08X\n", *((uint32_t*)(pmem + offset_40)));
            printf("=================================\n\n");
            break; // 退出仿真循环
        }

        // 使用 halt_req判定
        if (top->halt_req) {

            printf("\n[Halt] ebreak detected after %d cycles\n", cycles);

            // ==========================================
            // 🌟 在这里加入内存探针，无论 Good 还是 Bad 都能看到最终的内存状态
            // ==========================================
            uint32_t offset_20 = 0x80200020 - 0x80000000; // 计算 0x80200020 的数组偏移
            uint32_t offset_40 = 0x80200040 - 0x80000000; // 计算 0x80200040 的数组偏移
            
            printf("\n========== Memory Dump ==========\n");
            printf("Mem[0x80200020] = 0x%08X\n", *((uint32_t*)(pmem + offset_20)));
            printf("Mem[0x80200040] = 0x%08X\n", *((uint32_t*)(pmem + offset_40)));
            printf("=================================\n\n");
            
            if (regfile_scope != NULL) {
                svSetScope(regfile_scope);
                int a0_val = get_gpr(10); 
                if (a0_val == 0) {
                    printf("\33[1;32mHIT GOOD TRAP\33[0m\n");
                } else {
                    printf("\33[1;31mHIT BAD TRAP (a0 = %d, expected 0)\33[0m\n", a0_val);

                    #ifdef GEN_WAVEFORM
                    // 在程序异常退出前，强行把波形刷入硬盘！
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
