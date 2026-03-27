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

word_t isa_raise_intr(word_t NO, vaddr_t epc) {
  /* 1. 存档：把当前的 PC 存入 mepc，把原因 NO 存入 mcause */
  cpu.csr.mepc = epc;
  cpu.csr.mcause = NO;

  /* 2. 状态转换：更新 mstatus */
  word_t mstatus = cpu.csr.mstatus;
  
  // MPIE = MIE (保存当前的中断使能状态)
  word_t mie = (mstatus >> 3) & 1;
  mstatus = (mstatus & ~(1 << 7)) | (mie << 7);
  
  // MIE = 0 (进入异常处理后，自动关闭中断)
  mstatus = mstatus & ~(1 << 3);
  
  // MPP = 3 (因为 NEMU 目前只有 M-mode，所以异常前一定是 M-mode)
  mstatus = (mstatus & ~(3 << 11)) | (3 << 11);
  
  cpu.csr.mstatus = mstatus;

  /* 3. 跳转：下一条指令去 mtvec 取 */
  return cpu.csr.mtvec;
}

word_t isa_query_intr() {
  return INTR_EMPTY;
}
