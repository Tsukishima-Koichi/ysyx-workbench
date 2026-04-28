#ifndef __MEMORY_H__
#define __MEMORY_H__

#include <stdint.h>

// 物理内存与设备地址定义
#define PMEM_BASE 0x80000000
#define PMEM_SIZE (128 * 1024 * 1024)

#define SERIAL_PORT 0x10000000 
#define RTC_ADDR    0xa0000048

// 暴露物理内存指针和加载函数给主函数
extern uint8_t pmem[PMEM_SIZE];
// 👇 这里的函数声明必须加上 load_addr 参数！
void load_image(const char* img_path, uint32_t load_addr = PMEM_BASE);

#endif
