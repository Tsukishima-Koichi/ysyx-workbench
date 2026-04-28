#include "memory.h"
#include "utils.h"
#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include <string.h>

uint8_t pmem[PMEM_SIZE];

// 地址映射转换
uint8_t* guest_to_host(uint32_t paddr) {
    if (paddr >= PMEM_BASE && paddr < PMEM_BASE + PMEM_SIZE) {
        return pmem + (paddr - PMEM_BASE);
    }
    return NULL; 
}

// DPI-C: 读内存与外设
extern "C" int pmem_read(int raddr) {
    uint32_t addr = (uint32_t)raddr & ~0x3u;

    if (addr == RTC_ADDR) return (uint32_t)get_time();
    if (addr == RTC_ADDR + 4) return (uint32_t)(get_time() >> 32);

    uint8_t* host_addr = guest_to_host(addr);
    if (host_addr) return *((int32_t*)host_addr);
    return 0; 
}

// DPI-C: 写内存与外设
extern "C" void pmem_write(int waddr, int wdata, char wmask) {
    uint32_t addr = (uint32_t)waddr & ~0x3u;

    if (addr == SERIAL_PORT || addr == 0xa00003f8) {
        char c = (char)(wdata & 0xFF);
        putchar(c);
        fflush(stdout); 
        return;         
    }

    uint8_t* host_addr = guest_to_host(addr);
    if (host_addr) {
        uint8_t* data_ptr = (uint8_t*)&wdata;
        for (int i = 0; i < 4; i++) {
            if (wmask & (1 << i)) host_addr[i] = data_ptr[i];
        }
    }
}

// 镜像加载逻辑
// 镜像加载逻辑改进版：完美支持 .bin 二进制文件和 .hex 文件
void load_image(const char* img_path, uint32_t load_addr) {
    if (img_path == NULL) return;
    
    // 🌟 关键修改：将 "r" 改为 "rb"，以二进制模式打开文件，防止读取 .bin 遇到特殊字符截断
    FILE *fp = fopen(img_path, "rb"); 
    if (!fp) {
        printf("\33[1;31mERROR: Cannot open image %s\33[0m\n", img_path);
        assert(0);
    }

    // 检查加载地址是否越界
    if (load_addr < PMEM_BASE || load_addr >= PMEM_BASE + PMEM_SIZE) {
        printf("\33[1;31mERROR: Load address 0x%08x is out of memory bounds\33[0m\n", load_addr);
        assert(0);
    }
    
    // 计算在 pmem 数组中的实际偏移量
    uint32_t base_offset = load_addr - PMEM_BASE;

    // 如果文件名包含 .hex，则按文本十六进制读取
    if (strstr(img_path, ".hex") != NULL) {
        uint32_t inst;
        uint32_t loaded_bytes = 0;
        // 把数据写入对应的偏移位置
        while (fscanf(fp, "%x", &inst) == 1) {
            if (base_offset + loaded_bytes >= PMEM_SIZE) break; // 防止越界
            *((uint32_t*)(pmem + base_offset + loaded_bytes)) = inst;
            loaded_bytes += 4;
        }
        printf("[C++] Loaded %u bytes from .hex file to 0x%08x\n", loaded_bytes, load_addr);
    } 
    // 否则一律按照原始二进制文件 (.bin) 读取
    else {
        fseek(fp, 0, SEEK_END);
        long size = ftell(fp);
        fseek(fp, 0, SEEK_SET);
        
        if (base_offset + size > PMEM_SIZE) size = PMEM_SIZE - base_offset;
        
        // 直接将整个文件的数据块读入内存
        size_t ret = fread(pmem + base_offset, size, 1, fp);
        
        // 如果文件非空，要求 fread 成功读取 1 个大块
        if (size > 0) {
            assert(ret == 1);
        }
        printf("[C++] Loaded %ld bytes from .bin file to 0x%08x\n", size, load_addr);
    }
    fclose(fp);
}
