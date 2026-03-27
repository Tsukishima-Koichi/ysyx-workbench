#include <am.h>
#include <stdint.h> // 确保系统认识 uint32_t 和 uint64_t

#define RTC_ADDR 0xa0000048

// ==========================================
// 【关键修复】手动教编译器如何从物理地址读 32 位数据
// volatile 告诉编译器：绝对不许优化这里的访存动作！
// ==========================================
static inline uint32_t inl(uintptr_t addr) {
  return *(volatile uint32_t *)addr;
}

void __am_timer_init() {
}

void __am_timer_uptime(AM_TIMER_UPTIME_T *uptime) {
  // 分别读取低 32 位和高 32 位的时间
  uint32_t low  = inl(RTC_ADDR);
  uint32_t high = inl(RTC_ADDR + 4);
  
  // 拼接成 64 位的微秒数返回
  uptime->us = ((uint64_t)high << 32) | low;
}

void __am_timer_rtc(AM_TIMER_RTC_T *rtc) {
  rtc->second = 0;
  rtc->minute = 0;
  rtc->hour   = 0;
  rtc->day    = 0;
  rtc->month  = 0;
  rtc->year   = 1900;
}
