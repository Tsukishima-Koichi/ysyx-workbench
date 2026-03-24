#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include <stdint.h>
#include <string.h>
#include "verilated.h"
#include "svdpi.h"     
#include "Vcpu__Dpi.h" 
#include "Vcpu.h"

// ==================================================
// 1. 模拟 4MB 物理内存与 DPI-C 访存接口
// ==================================================
#define PMEM_BASE 0x80000000
#define PMEM_SIZE (4 * 1024 * 1024)

uint8_t pmem[PMEM_SIZE];

// 将 CPU 传来的物理地址转换为 C++ 数组指针
uint8_t* guest_to_host(uint32_t paddr) {
    if (paddr >= PMEM_BASE && paddr < PMEM_BASE + PMEM_SIZE) {
        return pmem + (paddr - PMEM_BASE);
    }
    return NULL; 
}

// DPI-C: 读内存 (强制 4 字节对齐)
extern "C" int pmem_read(int raddr) {
    uint32_t addr = (uint32_t)raddr & ~0x3u;
    uint8_t* host_addr = guest_to_host(addr);
    if (host_addr) {
        return *((int32_t*)host_addr);
    }
    return 0; 
}

// DPI-C: 写内存 (带掩码)
extern "C" void pmem_write(int waddr, int wdata, char wmask) {
    uint32_t addr = (uint32_t)waddr & ~0x3u;
    uint8_t* host_addr = guest_to_host(addr);
    if (host_addr) {
        uint8_t* data_ptr = (uint8_t*)&wdata;
        // 根据 wmask 的每一位决定是否写入对应的字节
        for (int i = 0; i < 4; i++) {
            if (wmask & (1 << i)) {
                host_addr[i] = data_ptr[i];
            }
        }
    }
}

// // ==================================================
// // 2. 寄存器监控 DPI-C 接口
// // ==================================================
// 声明一个全局变量保存 Verilog 传来的身份证 (Scope)
svScope regfile_scope = NULL;

// Verilog initial 块调用的函数，用来获取当前的上下文
extern "C" void set_regfile_scope() {
    regfile_scope = svGetScope();
}
extern "C" int get_gpr(int idx);

// ==================================================
// 3. 镜像加载函数
// ==================================================
void load_image(const char* img_path) {
    if (img_path == NULL) return;
    
    FILE *fp = fopen(img_path, "r");
    if (!fp) {
        printf("\33[1;31mERROR: Cannot open image %s\33[0m\n", img_path);
        assert(0);
    }

    // 如果是 .hex 文件，解析文本并写入
    if (strstr(img_path, ".hex") != NULL) {
        uint32_t inst;
        uint32_t offset = 0;
        while (fscanf(fp, "%x", &inst) == 1) {
            *((uint32_t*)(pmem + offset)) = inst;
            offset += 4;
        }
        printf("[C++] Loaded %d bytes from .hex file: %s\n", offset, img_path);
    } 
    // 如果是 .bin 文件，直接按二进制拷贝
    else {
        fseek(fp, 0, SEEK_END);
        long size = ftell(fp);
        fseek(fp, 0, SEEK_SET);
        if (size > PMEM_SIZE) size = PMEM_SIZE;
        size_t ret = fread(pmem, size, 1, fp);
        if (ret != 1) {
            printf("\33[1;31m[Error] Failed to read the complete image from %s!\33[0m\n", img_path);
            assert(0); // 如果读取失败，直接中断程序
        }
        printf("[C++] Loaded %ld bytes from .bin file: %s\n", size, img_path);
    }
    fclose(fp);
}

// ==================================================
// 4. 主函数 (Main)
// ==================================================
int main(int argc, char** argv) {
    VerilatedContext* contextp = new VerilatedContext;
    contextp->commandArgs(argc, argv);
    Vcpu* top = new Vcpu{contextp};

    // 内存清零
    memset(pmem, 0, PMEM_SIZE);

    // 解析命令行参数，寻找要加载的程序文件
    const char* image_file = NULL;
    for (int i = 1; i < argc; i++) {
        if (argv[i][0] != '-') {
            image_file = argv[i];
            break;
        }
    }
    
    // 默认加载路径
    if (image_file == NULL) {
        image_file = "./test_hex/test_8.hex";
    }
    
    // 把程序载入模拟内存 (pmem)
    load_image(image_file);

    // 复位 CPU
    top->clk = 0; top->rst = 1; top->eval();
    top->clk = 1; top->eval();
    top->rst = 0; 
    
    printf("--- CPU Simulation Start ---\n");

    int max_cycles = 100000;
    int cycles = 0;

    // 仿真主循环
    while (!contextp->gotFinish() && cycles < max_cycles) {
        // 先跑时钟，更新状态
        top->clk = 0; top->eval();
        top->clk = 1; top->eval();
        cycles++;

        // 判决逻辑：捕获 ebreak 指令 (机器码: 0x00100073)
        // 只要读到这条指令，就意味着程序主动要求停机
        if (top->inst == 0x00100073) {
            printf("\n[Success] Program Halted by ebreak at PC = 0x%08x after %d cycles\n", top->pc, cycles);
            
            // 确保已经拿到了 Verilog 的作用域身份证
            if (regfile_scope != NULL) {
                svSetScope(regfile_scope);
                int a0_val = get_gpr(10); // 检查 a0
                
                if (a0_val == 0) {
                    printf("\33[1;32mHIT GOOD TRAP\33[0m\n");
                    break; // 只有 Good Trap 正常跳出循环，最终 return 0
                } else {
                    printf("\33[1;31mHIT BAD TRAP (a0 = %d, expected 0)\33[0m\n", a0_val);
                    return 1; // 坏停机，立刻返回 1 给操作系统！
                }
            } else {
                printf("\33[1;31m[Error] regfile_scope is NULL! Verilog didn't pass it.\33[0m\n");
            }
            break; // 踩下刹车，结束仿真
        }        

        // 定期打印观察日志
        if (cycles < 100 || (cycles < 1000 && cycles % 100 == 0) || (cycles < 10000 && cycles % 1000 == 0)) {
            printf("Cycle %d: PC = 0x%08x, Inst = 0x%08x\n", cycles, top->pc, top->inst);
        }
    }

    if (cycles >= max_cycles) {
        printf("\33[1;31mSIMULATION TIMEOUT\33[0m\n");
        return 1; // 超时了也返回 1！
    }
    
    printf("--- CPU Simulation End (Total Cycles: %d) ---\n", cycles);
    delete top;
    delete contextp;
    return 0; // 只有经历了 Good Trap 的 break，才会平安走到这里
}
