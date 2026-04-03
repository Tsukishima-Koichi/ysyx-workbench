#include <am.h>
#include <riscv/riscv.h>
#include <klib.h>

static Context* (*user_handler)(Event, Context*) = NULL;

Context* __am_irq_handle(Context *c) {
  if (user_handler) {
    Event ev = {0};
    // 检查硬件传过来的 mcause（异常原因）
    switch (c->mcause) {
      case 11: // 11 代表 RISC-V 机器模式下的 ecall
        // 通过检查 a7 寄存器 (gpr[17]) 来区分 Syscall 和 Yield
        if (c->gpr[17] == -1) {
          ev.event = EVENT_YIELD;
        } else {
          ev.event = EVENT_SYSCALL;
        }
        
        // 【极其重要的一步】：跳过 ecall 指令！
        // 因为 mepc 目前指向的是 ecall 这条指令本身，
        // 如果不加 4，一会儿回去的时候 CPU 又会执行一遍 ecall，导致无限死循环！
        c->mepc += 4; 
        break;
        
      default: 
        ev.event = EVENT_ERROR; 
        break;
    }

    // 将具体的异常原因和出错的 PC 地址打包，传给 Nanos-lite 备查
    ev.cause = c->mcause;
    ev.ref = c->mepc;

    c = user_handler(ev, c);
    assert(c != NULL);
  }

  return c;
}

extern void __am_asm_trap(void);

bool cte_init(Context*(*handler)(Event, Context*)) {
  // initialize exception entry
  asm volatile("csrw mtvec, %0" : : "r"(__am_asm_trap));

  // register event handler
  user_handler = handler;

  return true;
}

Context *kcontext(Area kstack, void (*entry)(void *), void *arg) {
  return NULL;
}

void yield() {
#ifdef __riscv_e
  asm volatile("li a5, -1; ecall");
#else
  asm volatile("li a7, -1; ecall");
#endif
}

bool ienabled() {
  return false;
}

void iset(bool enable) {
}
