#ifndef ARCH_H__
#define ARCH_H__

#ifdef __riscv_e
#define NR_REGS 16
#else
#define NR_REGS 32
#endif

struct Context {
  // 1. 先放通用寄存器，因为它们在汇编里是从 sp+0 开始存的
  // gpr[0] 对应 x0, gpr[1] 对应 x1 ... gpr[31] 对应 x31
  uintptr_t gpr[NR_REGS]; 

  // 2. 接下来放 CSR 寄存器，对应 OFFSET_CAUSE (32*4), STATUS (33*4), EPC (34*4)
  // 注意：顺序必须和 trap.S 里的 STORE 顺序完全一致！
  uintptr_t mcause;  // 对应 sp + 128
  uintptr_t mstatus; // 对应 sp + 132
  uintptr_t mepc;    // 对应 sp + 136

  // 3. 最后放 pdir (页表指针)，这是为以后虚拟内存实验准备的
  void *pdir;        // 对应 sp + 140
};

#ifdef __riscv_e
#define GPR1 gpr[15] // a5
#else
#define GPR1 gpr[17] // a7
#endif

#define GPR2 gpr[10] // a0: 第 1 个参数
#define GPR3 gpr[11] // a1: 第 2 个参数
#define GPR4 gpr[12] // a2: 第 3 个参数
#define GPRx gpr[10] // a0: 返回值也存放在这里

#endif
