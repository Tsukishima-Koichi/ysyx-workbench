/***************************************************************************************
* Copyright (c) 2014-2024 Zihao Yu, Nanjing University
*
* NEMU is licensed under Mulan PSL v2.
* You can use this software according to the terms and conditions of the Mulan PSL v2.
* You may obtain a copy of Mulan PSL v2 at:
*          http://license.coscl.org.cn/MulanPSL2
*
* THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
* EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
* MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
*
* See the Mulan PSL v2 for more details.
***************************************************************************************/

#include <isa.h>
#include <cpu/difftest.h>
#include "../local-include/reg.h"

// 引入 NEMU 的全局 cpu 状态变量
extern CPU_state cpu;

// 为了打印报错时人类可读，我们可以定义一个寄存器名字数组
extern const char *regs[];

bool isa_difftest_checkregs(CPU_state *ref_r, vaddr_t pc) {
  // 1. 逐个比对 32 个通用寄存器
  for (int i = 0; i < 32; i++) {
    // 检查 NEMU (cpu) 和 裁判 (ref_r) 的寄存器是否一致
    if (cpu.gpr[i] != ref_r->gpr[i]) {
      // 一旦发现不一致，立刻打印凶案现场
      printf("🚨 Difftest failed at PC = 0x%08x\n", pc);
      printf("Register [%s] mismatch: DUT(NEMU) = 0x%08x, REF = 0x%08x\n", 
             regs[i], cpu.gpr[i], ref_r->gpr[i]);
      return false; // 返回 false 触发 NEMU 停机
    }
  }

  // 2. 比对下一条将要执行的指令地址 (Next PC)
  if (cpu.pc != ref_r->pc) {
    printf("🚨 Difftest failed at PC = 0x%08x\n", pc);
    printf("Next PC mismatch: DUT(NEMU) = 0x%08x, REF = 0x%08x\n", cpu.pc, ref_r->pc);
    return false;
  }

  // 如果全部一致，说明这条指令你模拟得毫无破绽！
  return true;
}

extern void (*ref_difftest_regcpy)(void *dut, bool direction);

void isa_difftest_attach() {
  // 把 NEMU 当前的完整寄存器状态（cpu），强行拷贝给裁判（REF）
  // 这样 REF 就被迫和 NEMU 处于完全相同的状态了
  ref_difftest_regcpy(&cpu, DIFFTEST_TO_REF);
}
