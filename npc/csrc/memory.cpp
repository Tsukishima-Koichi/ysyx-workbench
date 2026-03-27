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
void load_image(const char* img_path) {
    if (img_path == NULL) return;
    FILE *fp = fopen(img_path, "r");
    if (!fp) {
        printf("\33[1;31mERROR: Cannot open image %s\33[0m\n", img_path);
        assert(0);
    }
    if (strstr(img_path, ".hex") != NULL) {
        uint32_t inst, offset = 0;
        while (fscanf(fp, "%x", &inst) == 1) {
            *((uint32_t*)(pmem + offset)) = inst;
            offset += 4;
        }
        printf("[C++] Loaded %d bytes from .hex file\n", offset);
    } else {
        fseek(fp, 0, SEEK_END);
        long size = ftell(fp);
        fseek(fp, 0, SEEK_SET);
        if (size > PMEM_SIZE) size = PMEM_SIZE;
        size_t ret = fread(pmem, size, 1, fp);
        assert(ret == 1);
        printf("[C++] Loaded %ld bytes from .bin file\n", size);
    }
    fclose(fp);
}
