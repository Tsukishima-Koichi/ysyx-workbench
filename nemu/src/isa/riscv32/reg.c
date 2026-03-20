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
#include "local-include/reg.h"

const char *regs[] = {
  "$0", "ra", "sp", "gp", "tp", "t0", "t1", "t2",
  "s0", "s1", "a0", "a1", "a2", "a3", "a4", "a5",
  "a6", "a7", "s2", "s3", "s4", "s5", "s6", "s7",
  "s8", "s9", "s10", "s11", "t3", "t4", "t5", "t6"
};

void isa_reg_display() {
  int i;
  // traversing 32 general-purpose registers
  for (i = 0; i < 32; i++) {
    // Print format: %-10s left-aligned, occupies 10 spaces
    //               0x%08x prints 8-digit hexadecimal
    //               %d prints decimal.
    printf("%-10s 0x%08x    %d\n", regs[i], cpu.gpr[i], cpu.gpr[i]);
  }
  
  // PC register is not in the general-purpose register array
  // so it needs to be printed separately
  printf("%-10s 0x%08x    %d\n", "pc", cpu.pc, cpu.pc);
}

word_t isa_reg_str2val(const char *s, bool *success) {
  // 1. 单独判断 pc 寄存器 (因为它非常特殊，不在通用寄存器数组里)
  if (strcmp(s, "pc") == 0) {
    *success = true;
    return cpu.pc;
  }

  // 2. 遍历 32 个通用寄存器进行名字匹配
  for (int i = 0; i < 32; i++) {
    // 💡 细节：regs[0] 在数组里存的是 "$0"，而其他存的是 "ra", "t0" 等纯字母。
    // 为了防止出错，如果传入的是 "0"，我们也认作是 0 号寄存器。
    if (strcmp(s, regs[i]) == 0 || (i == 0 && strcmp(s, "0") == 0)) {
      *success = true;
      
      // 注意：这里的 cpu.gpr[i] 必须和你之前在 isa_reg_display 里写的取值方式一模一样。
      // 如果你之前写的是 cpu.gpr[i]._32，这里也要加上 ._32
      return cpu.gpr[i]; 
    }
  }

  // 3. 如果扫遍了整个数组都没找到，说明用户瞎敲了一个不存在的寄存器
  *success = false;
  return 0;
}
