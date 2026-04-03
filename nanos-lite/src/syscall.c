#include <common.h>
#include "syscall.h"

// 为 strace 准备的系统调用名字数组
// 注意：这里的顺序必须和 syscall.h 中 enum 的顺序完全一致！
const char *syscall_names[] = {
  "SYS_exit",
  "SYS_yield",
  "SYS_open",
  "SYS_read",
  "SYS_write",
  "SYS_kill",
  "SYS_getpid",
  "SYS_close",
  "SYS_lseek",
  "SYS_brk",
  "SYS_fstat",
  "SYS_time",
  "SYS_signal",
  "SYS_execve",
  "SYS_fork",
  "SYS_link",
  "SYS_unlink",
  "SYS_wait",
  "SYS_times",
  "SYS_gettimeofday"
};

void do_syscall(Context *c) {
  uintptr_t a[4];
  a[0] = c->GPR1; // 系统调用号
  a[1] = c->GPR2; // 参数 1
  a[2] = c->GPR3; // 参数 2
  a[3] = c->GPR4; // 参数 3

  // ------ 宏开关控制的 strace ------
#ifdef CONFIG_STRACE
  int syscall_count = sizeof(syscall_names) / sizeof(syscall_names[0]);
  if (a[0] < syscall_count) {
    Log("[strace] syscall: %s (ID = %d), args: 0x%x, 0x%x, 0x%x", 
        syscall_names[a[0]], a[0], a[1], a[2], a[3]);
  } else {
    Log("[strace] syscall: UNKNOWN (ID = %d), args: 0x%x, 0x%x, 0x%x", 
        a[0], a[1], a[2], a[3]);
  }
#endif
// ------------------------------------

  switch (a[0]) {
    case SYS_yield:
      yield(); 
      c->GPRx = 0; 
      break;

    case SYS_exit:
      halt(a[1]);      
      break;

    case SYS_write: {
      int fd = a[1];
      char *buf = (char *)a[2]; // buf 是一个内存地址，强转成字符指针
      size_t len = a[3];

      // 根据 POSIX 标准，fd = 1 是标准输出 (stdout)，fd = 2 是标准错误 (stderr)
      // 目前我们的操作系统连文件系统都没有，所以只处理向屏幕打印的请求
      if (fd == 1 || fd == 2) {
        // 遍历整个 buf，把里面的字符挨个用底层的 putch 打印出来
        for (size_t i = 0; i < len; i++) {
          putch(buf[i]);
        }
        // 极其关键的一步：系统调用的返回值必须是“成功写入的字节数”
        // 如果这里不填 len，printf 会以为写入失败了，可能会引发不断的重试或者程序崩溃！
        c->GPRx = len; 
      } else {
        // 如果想往其他文件里写（比如 fd = 3），目前不支持，返回 -1 表示失败
        c->GPRx = -1; 
      }
      break;
    }

    case SYS_brk:
      // 目前直接返回 0，表示调整总是成功
      // 未来在 PA4 实现分页机制后，这里需要真正去分配物理内存页
      c->GPRx = 0; 
      break;

    default: 
      panic("Unhandled syscall ID = %d", a[0]);
  }
}