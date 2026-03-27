#include <am.h>
#include <klib-macros.h>

#define SERIAL_PORT     (0x10000000) // 未来为了兼容 SoC 设为 0x10000000

extern char _heap_start;
int main(const char *args);

extern char _pmem_start;
#define PMEM_SIZE (128 * 1024 * 1024)
#define PMEM_END  ((uintptr_t)&_pmem_start + PMEM_SIZE)

Area heap = RANGE(&_heap_start, PMEM_END);
static const char mainargs[MAINARGS_MAX_LEN] = TOSTRING(MAINARGS_PLACEHOLDER); // defined in CFLAGS

// ==========================================
// 修复点：实现串口输出
// ==========================================
void putch(char ch) {
  // volatile 关键字极其重要！它告诉编译器：
  // 绝对不许优化这行代码，必须老老实实向这个物理地址发起一次 Store 访存！
  *(volatile uint8_t *)SERIAL_PORT = ch;
}

void halt(int code) {
  // 把 code 的值放入 a0 寄存器，然后执行 ebreak，最后陷入死循环以防万一
  asm volatile("mv a0, %0; ebreak" : :"r"(code));
  while (1);
}

void _trm_init() {
  int ret = main(mainargs);
  halt(ret);
}
