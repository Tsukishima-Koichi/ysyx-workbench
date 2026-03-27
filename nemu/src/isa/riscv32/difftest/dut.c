/***************************************************************************************
* Copyright (c) 2014-2024 Zihao Yu, Nanjing University
*
* NEMU is licensed under Mulan PSL v2.
* ... (此处省略版权信息)
***************************************************************************************/

#include <isa.h>
#include <cpu/difftest.h>
#include "../local-include/reg.h"

// 引入 NEMU 全局 CPU 状态
extern CPU_state cpu;
// 引入寄存器名称字符串数组，用于报错打印
extern const char *regs[];

/**
 * mstatus 掩码说明 (0x1888):
 * 位 12-11: MPP (Machine Previous Privilege) - 确保特权级对齐
 * 位 7:     MPIE (Machine Previous Interrupt Enable) - 异常发生时的中断备份
 * 位 3:     MIE (Machine Interrupt Enable) - 中断使能开关
 * 我们只关心这几个影响程序逻辑的状态位，忽略其他硬件特征位。
 */
#define MSTATUS_MASK 0x1888

/**
 * 检查 NEMU (DUT) 与参考模型 (REF) 的寄存器状态是否一致
 */
bool isa_difftest_checkregs(CPU_state *ref_r, vaddr_t pc) {
  // 1. 比对 32 个通用寄存器 (GPRs)
  for (int i = 0; i < 32; i++) {
    if (cpu.gpr[i] != ref_r->gpr[i]) {
      printf("🚨 [Difftest] GPR Mismatch at PC = 0x%08x\n", pc);
      printf("Register [%s]: DUT = 0x%08x, REF = 0x%08x\n", 
              regs[i], cpu.gpr[i], ref_r->gpr[i]);
      return false;
    }
  }

  // 2. 比对程序计数器 (PC)
  // 注意：某些情况下 REF 可能指向下一条指令，如果报错请检查你的指令更新逻辑
  if (cpu.pc != ref_r->pc) {
    printf("🚨 [Difftest] PC Mismatch at PC = 0x%08x\n", pc);
    printf("Next PC: DUT = 0x%08x, REF = 0x%08x\n", cpu.pc, ref_r->pc);
    return false;
  }

  // 3. 比对 CSR 寄存器 (关键：对应你新加的嵌套结构体路径)

  // 比对 mepc (异常返回地址)
  if (cpu.csr.mepc != ref_r->csr.mepc) {
    printf("🚨 [Difftest] CSR Mismatch (mepc) at PC = 0x%08x\n", pc);
    printf("DUT mepc = 0x%08x, REF mepc = 0x%08x\n", cpu.csr.mepc, ref_r->csr.mepc);
    return false;
  }

  // 比对 mcause (异常原因)
  if (cpu.csr.mcause != ref_r->csr.mcause) {
    printf("🚨 [Difftest] CSR Mismatch (mcause) at PC = 0x%08x\n", pc);
    printf("DUT mcause = 0x%08x, REF mcause = 0x%08x\n", cpu.csr.mcause, ref_r->csr.mcause);
    return false;
  }

  // 比对 mstatus (状态寄存器) - 使用掩码过滤
  if ((cpu.csr.mstatus & MSTATUS_MASK) != (ref_r->csr.mstatus & MSTATUS_MASK)) {
    printf("🚨 [Difftest] CSR Mismatch (mstatus) at PC = 0x%08x\n", pc);
    printf("DUT mstatus = 0x%08x, REF mstatus = 0x%08x (Masked: 0x%x)\n", 
            cpu.csr.mstatus, ref_r->csr.mstatus, MSTATUS_MASK);
    return false;
  }

  // 比对 mtvec (异常入口基地址)
  if (cpu.csr.mtvec != ref_r->csr.mtvec) {
    printf("🚨 [Difftest] CSR Mismatch (mtvec) at PC = 0x%08x\n", pc);
    printf("DUT mtvec = 0x%08x, REF mtvec = 0x%08x\n", cpu.csr.mtvec, ref_r->csr.mtvec);
    return false;
  }

  return true;
}

/**
 * 将 NEMU 的寄存器状态同步给参考模型
 */
extern void (*ref_difftest_regcpy)(void *dut, bool direction);

void isa_difftest_attach() {
  // 核心：把当前 NEMU 的 CPU 状态（包含已初始化的 mstatus=0x1800 等）
  // 完整地复刻给参考模型，确保“裁判”开局的状态和我们一模一样
  ref_difftest_regcpy(&cpu, DIFFTEST_TO_REF);
}