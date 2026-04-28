#include <isa.h>
#include <cpu/cpu.h>
#include <difftest-def.h>
#include <memory/paddr.h>
#include <string.h> // 需要用到 memcpy

// 1. 内存拷贝 API
__EXPORT void difftest_memcpy(paddr_t addr, void *buf, size_t n, bool direction) {
  // direction 为 true (DIFFTEST_TO_REF) 表示从 NPC 拷贝到 NEMU
  // direction 为 false (DIFFTEST_TO_DUT) 表示从 NEMU 拷贝到 NPC
  if (direction == DIFFTEST_TO_REF) {
    memcpy(guest_to_host(addr), buf, n);
  } else {
    memcpy(buf, guest_to_host(addr), n);
  }
}

// 2. 寄存器拷贝 API
__EXPORT void difftest_regcpy(void *dut, bool direction) {
  // NEMU 中的全局寄存器状态保存在 cpu 结构体中
  if (direction == DIFFTEST_TO_REF) {
    cpu = *(CPU_state *)dut;
  } else {
    *(CPU_state *)dut = cpu;
  }
}

// 3. 单步执行 API
__EXPORT void difftest_exec(uint64_t n) {
  // 让 NEMU 执行 n 条指令
  cpu_exec(n);
}

// 4. 中断触发 API (现阶段还没做到中断，可以先留空，把 assert 删掉防报错)
__EXPORT void difftest_raise_intr(word_t NO) {
  // 暂时留空
}

__EXPORT void difftest_init(int port) {
  void init_mem();
  init_mem();
  /* Perform ISA dependent initialization. */
  init_isa();
}
