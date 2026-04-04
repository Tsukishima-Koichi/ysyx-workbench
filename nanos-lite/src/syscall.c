#include <common.h>
#include "syscall.h"
#include <sys/time.h>  // <---- 【加上这一行！】
#include <am.h> // 必须包含 AM 头文件以使用 io_read

// 【新增】声明 VFS (虚拟文件系统) 的核心接口
extern int fs_open(const char *pathname, int flags, int mode);
extern size_t fs_read(int fd, void *buf, size_t len);
extern size_t fs_write(int fd, const void *buf, size_t len);
extern size_t fs_lseek(int fd, size_t offset, int whence);
extern int fs_close(int fd);
extern const char *fs_get_name(int fd);

// 为 strace 准备的系统调用名字数组
const char *syscall_names[] = {
  "SYS_exit", "SYS_yield", "SYS_open", "SYS_read", "SYS_write",
  "SYS_kill", "SYS_getpid", "SYS_close", "SYS_lseek", "SYS_brk",
  "SYS_fstat", "SYS_time", "SYS_signal", "SYS_execve", "SYS_fork",
  "SYS_link", "SYS_unlink", "SYS_wait", "SYS_times", "SYS_gettimeofday"
};

// 假设 sys_gettimeofday 的具体实现
int sys_gettimeofday(struct timeval *tv, struct timezone *tz) {
  if (tv != NULL) {
    // 获取系统启动以来的微秒数
    uint64_t us = io_read(AM_TIMER_UPTIME).us;
    tv->tv_sec = us / 1000000;
    tv->tv_usec = us % 1000000;
  }
  return 0;
}

void do_syscall(Context *c) {
  uintptr_t a[4];
  a[0] = c->GPR1; // 系统调用号
  a[1] = c->GPR2; // 参数 1
  a[2] = c->GPR3; // 参数 2
  a[3] = c->GPR4; // 参数 3

// ------ 宏开关控制的智能 strace ------
#ifdef CONFIG_STRACE
  int syscall_count = sizeof(syscall_names) / sizeof(syscall_names[0]);
  if (a[0] < syscall_count) {
    
    // 如果是读、写、lseek、关闭等针对具体 FD 的操作，a[1] 就是 fd
    if (a[0] == SYS_read || a[0] == SYS_write || a[0] == SYS_lseek || a[0] == SYS_close) {
      int fd = a[1];
      Log("[strace] syscall: %s (ID = %d), fd: %d [%s], args: 0x%x, 0x%x", 
          syscall_names[a[0]], a[0], fd, fs_get_name(fd), a[2], a[3]);
    } 
    // 【附赠功能】如果是 open，a[1] 本身就是请求打开的文件路径字符串！
    else if (a[0] == SYS_open) {
      Log("[strace] syscall: %s (ID = %d), path: [%s], args: 0x%x, 0x%x", 
          syscall_names[a[0]], a[0], (char *)a[1], a[2], a[3]);
    } 
    // 其他普通系统调用
    else {
      Log("[strace] syscall: %s (ID = %d), args: 0x%x, 0x%x, 0x%x", 
          syscall_names[a[0]], a[0], a[1], a[2], a[3]);
    }
    
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

    // 【新增】打开文件
    case SYS_open:
      c->GPRx = fs_open((const char *)a[1], a[2], a[3]);
      break;

    // 【新增】读取文件
    case SYS_read:
      c->GPRx = fs_read(a[1], (void *)a[2], a[3]);
      break;

    // 【极致优雅】现在的 SYS_write 只需一句话
    case SYS_write:
      c->GPRx = fs_write(a[1], (const void *)a[2], a[3]);
      break;

    // 【新增】移动读写指针
    case SYS_lseek:
      c->GPRx = fs_lseek(a[1], a[2], a[3]);
      break;

    // 【新增】关闭文件
    case SYS_close:
      c->GPRx = fs_close(a[1]);
      break;

    case SYS_brk:
      c->GPRx = 0; 
      break;

    case SYS_gettimeofday:
      c->GPRx = sys_gettimeofday((struct timeval *)a[1], (struct timezone *)a[2]);
      break;

    default: 
      panic("Unhandled syscall ID = %d", a[0]);
  }
}