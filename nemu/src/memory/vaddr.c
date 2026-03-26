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
#include <memory/paddr.h>
#include <cpu/cpu.h> // 必须引入，为了用 cpu.pc

word_t vaddr_ifetch(vaddr_t addr, int len) {
  return paddr_read(addr, len);
}

// word_t vaddr_read(vaddr_t addr, int len) {
//   return paddr_read(addr, len);
// }

word_t vaddr_read(vaddr_t addr, int len) {
  word_t ret = paddr_read(addr, len);

// ==================== mtrace 读记录 ====================
#ifdef CONFIG_MTRACE
  if (CONFIG_MTRACE_COND) {
    printf("[MTRACE] READ  | PC: " FMT_WORD " | VAddr: " FMT_WORD " | Len: %d | Data: 0x%08x\n", 
           cpu.pc, addr, len, (uint32_t)ret);
  }
#endif
// =======================================================

  return ret;
}

// void vaddr_write(vaddr_t addr, int len, word_t data) {
//   paddr_write(addr, len, data);
// }
void vaddr_write(vaddr_t addr, int len, word_t data) {
  paddr_write(addr, len, data);

// ==================== mtrace 写记录 ====================
#ifdef CONFIG_MTRACE
  if (CONFIG_MTRACE_COND) {
    printf("[MTRACE] WRITE | PC: " FMT_WORD " | VAddr: " FMT_WORD " | Len: %d | Data: 0x%08x\n", 
           cpu.pc, addr, len, (uint32_t)data);
  }
#endif
// =======================================================
}
