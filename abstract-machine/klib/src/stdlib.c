#include <am.h>
#include <klib.h>
#include <klib-macros.h>

#if !defined(__ISA_NATIVE__) || defined(__NATIVE_USE_KLIB__)
static unsigned long int next = 1;

int rand(void) {
  // RAND_MAX assumed to be 32767
  next = next * 1103515245 + 12345;
  return (unsigned int)(next/65536) % 32768;
}

void srand(unsigned int seed) {
  next = seed;
}

int abs(int x) {
  return (x < 0 ? -x : x);
}

int atoi(const char* nptr) {
  int x = 0;
  while (*nptr == ' ') { nptr ++; }
  while (*nptr >= '0' && *nptr <= '9') {
    x = x * 10 + *nptr - '0';
    nptr ++;
  }
  return x;
}


void *malloc(size_t size) {
  // 在 native 架构上，malloc 会在 C 运行时初始化时被调用。
  // 为了防止陷入无限死循环递归，按照原代码逻辑，直接返回 NULL 或走系统调用。
#if !(defined(__ISA_NATIVE__) && defined(__NATIVE_USE_KLIB__))

  // 定义一个静态指针，用来记录当前内存分配到了哪里
  static void *addr = NULL;
  
  // 1. 第一次调用时，把分配指针指向系统提供的堆区起始地址
  if (addr == NULL) {
    addr = heap.start;
  }

  // 2. 内存对齐 (极其重要)
  // RISC-V 等架构对内存访问有对齐要求，通常按照 8 字节对齐。
  // 比如申请 13 字节，会被向上取整为 16 字节。
  size  = (size + 7) & ~7;

  // 3. 记录当前可用地址，准备返回给用户
  void *ret = addr;

  // 4. 将分配指针向前推进 size 个字节
  addr += size;

  // 5. 边界检查：如果超出系统给定的物理内存上限，直接宕机报错
  if (addr > heap.end) {
    panic("Out of memory: heap exhausted!");
  }

  return ret;
  
#endif
  return NULL;
}

void free(void *ptr) {
  // 在早期裸机系统和初级 OS 实验中，我们通常不需要实现 free。
  // 指针碰撞分配器的特点就是“只借不还”，一旦分配就不管了。
  // 所以留空即可。
}

#endif
