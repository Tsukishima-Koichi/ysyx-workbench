#include <common.h>

// 提前声明我们将要写的系统调用处理函数
void do_syscall(Context *c);

static Context* do_event(Event e, Context* c) {
  switch (e.event) {
    case EVENT_YIELD:
      Log("Event: Yield recognized!");
      break;

    case EVENT_SYSCALL:
      // 如果是系统调用事件，就把它转交给专门的系统调用处理函数
      do_syscall(c); 
      break;

    default: 
      panic("Unhandled event ID = %d", e.event);
  }

  return c;
}
void init_irq(void) {
  Log("Initializing interrupt/exception handler...");
  cte_init(do_event);
}
