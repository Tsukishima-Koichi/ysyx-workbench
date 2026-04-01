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

#include <isa.h>

// 异常名称翻译字典，用于 etrace 打印人类可读的日志
const char *exception_names[] = {
  [0] = "Instruction address misaligned",
  [1] = "Instruction access fault",
  [2] = "Illegal instruction",
  [3] = "Breakpoint",
  [8] = "Environment call from U-mode",
  [11] = "Environment call from M-mode"
};

word_t isa_raise_intr(word_t NO, vaddr_t epc) {
  /* 1. 基础存档：保存事故现场地址和原因 */
  cpu.csr.mepc = epc;
  cpu.csr.mcause = NO;

  /* 2. 状态存档 (mstatus 关键位的流转) */
  word_t mstatus = cpu.csr.mstatus;

  // MPIE = MIE (把当前的中断开关状态 存入 备份位)
  word_t mie = (mstatus >> 3) & 1;
  mstatus = (mstatus & ~(1 << 7)) | (mie << 7);

  // MIE = 0 (进入异常处理程序后，硬件会自动关闭中断，防止嵌套)
  mstatus = mstatus & ~(1 << 3);

  // MPP = 3 (备份当前的特权模式。强制设为 M-mode)
  mstatus = (mstatus & ~(3 << 11)) | (3 << 11);

  cpu.csr.mstatus = mstatus;

  /* 3. etrace 异常追踪日志 */
#ifdef CONFIG_ETRACE
  // 防止未知的异常号越界访问数组
  const char *name = (NO < sizeof(exception_names)/sizeof(char*) && exception_names[NO]) 
                     ? exception_names[NO] 
                     : "Unknown Exception";

  Log("🔔 [etrace] Trap Triggered: PC = " FMT_WORD ", Cause = %d (%s), Jump to = " FMT_WORD, 
      epc, NO, name, cpu.csr.mtvec);
#endif

  /* 4. 返回异常处理程序的入口地址 */
  return cpu.csr.mtvec;
}


word_t isa_query_intr() {
  return INTR_EMPTY;
}
