#include <am.h>
#include <nemu.h> // 这里面定义了 inl() 宏和 RTC_ADDR

// 静态变量，用于记录系统刚刚启动时的基准时间
static uint64_t boot_time = 0;

// 辅助函数：专门用来从 NEMU 读取 64 位的原始时间
static uint64_t read_rtc() {
  // inl 是 AM 封装好的 I/O 读取宏，专门用来读 32 位数据
  uint32_t low = inl(RTC_ADDR);       // 读取低 32 位
  uint32_t high = inl(RTC_ADDR + 4);  // 读取高 32 位

  // 把高 32 位左移，然后和低 32 位按位或，拼成 64 位
  // 注意：必须先把 high 强转成 uint64_t，否则 32 位左移 32 位会变成 0！
  return ((uint64_t)high << 32) | low;
}

void __am_timer_init() {
  // 在系统刚启动初始化时，记录下当前的绝对时间作为开机时间
  boot_time = read_rtc();
}

void __am_timer_uptime(AM_TIMER_UPTIME_T *uptime) {
  // 现在的启动时间 = 当前的绝对时间 - 开机时的基准时间
  uptime->us = read_rtc() - boot_time;
}

void __am_timer_rtc(AM_TIMER_RTC_T *rtc) {
  // 讲义中说 PA 中暂不使用真实时间，所以直接塞点假数据即可
  rtc->second = 0;
  rtc->minute = 0;
  rtc->hour   = 0;
  rtc->day    = 0;
  rtc->month  = 0;
  rtc->year   = 1900;
}
