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

#include <memory/host.h>
#include <memory/paddr.h>
#include <device/mmio.h>
#include <isa.h>

#if   defined(CONFIG_PMEM_MALLOC)
static uint8_t *pmem = NULL;
#else // CONFIG_PMEM_GARRAY
static uint8_t pmem[CONFIG_MSIZE] PG_ALIGN = {};
#endif

uint8_t* guest_to_host(paddr_t paddr) { return pmem + paddr - CONFIG_MBASE; }
paddr_t host_to_guest(uint8_t *haddr) { return haddr - pmem + CONFIG_MBASE; }

static word_t pmem_read(paddr_t addr, int len) {
  word_t ret = host_read(guest_to_host(addr), len);
  return ret;
}

static void pmem_write(paddr_t addr, int len, word_t data) {
  host_write(guest_to_host(addr), len, data);
}

static void out_of_bound(paddr_t addr) {
  panic("address = " FMT_PADDR " is out of bound of pmem [" FMT_PADDR ", " FMT_PADDR "] at pc = " FMT_WORD,
      addr, PMEM_LEFT, PMEM_RIGHT, cpu.pc);
}

void init_mem() {
#if   defined(CONFIG_PMEM_MALLOC)
  pmem = malloc(CONFIG_MSIZE);
  assert(pmem);
#endif
  IFDEF(CONFIG_MEM_RANDOM, memset(pmem, rand(), CONFIG_MSIZE));
  Log("physical memory area [" FMT_PADDR ", " FMT_PADDR "]", PMEM_LEFT, PMEM_RIGHT);
}

// word_t paddr_read(paddr_t addr, int len) {
//   if (likely(in_pmem(addr))) return pmem_read(addr, len);
//   IFDEF(CONFIG_DEVICE, return mmio_read(addr, len));
//   out_of_bound(addr);
//   return 0;
// }
word_t paddr_read(paddr_t addr, int len) {
  word_t ret = 0;
  if (likely(in_pmem(addr))) {
    ret = pmem_read(addr, len);
  } else {
    MUXDEF(CONFIG_DEVICE, ret = mmio_read(addr, len), out_of_bound(addr));
  }

// ==================== mtrace 读记录 ====================
#ifdef CONFIG_MTRACE
  // 使用我们在 menuconfig 中定义的条件宏
  if (CONFIG_MTRACE_COND) {
    // 这里的 cpu.pc 需要 extern 一下，或者确认当前文件是否已经 include 了能获取 pc 的头文件
    printf("[MTRACE] READ  | PC: " FMT_WORD " | Addr: " FMT_PADDR " | Len: %d | Data: 0x%08x\n", 
           cpu.pc, addr, len, (uint32_t)ret);
  }
#endif
// =======================================================

  return ret;
}

// void paddr_write(paddr_t addr, int len, word_t data) {
//   if (likely(in_pmem(addr))) { pmem_write(addr, len, data); return; }
//   IFDEF(CONFIG_DEVICE, mmio_write(addr, len, data); return);
//   out_of_bound(addr);
// }
void paddr_write(paddr_t addr, int len, word_t data) {
// ==================== mtrace 写记录 ====================
#ifdef CONFIG_MTRACE
  if (CONFIG_MTRACE_COND) {
    printf("[MTRACE] WRITE | PC: " FMT_WORD " | Addr: " FMT_PADDR " | Len: %d | Data: 0x%08x\n", 
           cpu.pc, addr, len, (uint32_t)data);
  }
#endif
// =======================================================

  if (likely(in_pmem(addr))) {
    pmem_write(addr, len, data);
    return;
  }
  MUXDEF(CONFIG_DEVICE, mmio_write(addr, len, data), out_of_bound(addr));
}
