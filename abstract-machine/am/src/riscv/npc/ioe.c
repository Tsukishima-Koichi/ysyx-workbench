#include <am.h>
#include <klib-macros.h>

void __am_timer_init();
void __am_timer_rtc(AM_TIMER_RTC_T *);
void __am_timer_uptime(AM_TIMER_UPTIME_T *);

// =========================================
// 1. 时钟相关 (唯一真实在干活的设备)
// =========================================
static void __am_timer_config(AM_TIMER_CONFIG_T *cfg) { cfg->present = true; cfg->has_rtc = true; }

// =========================================
// 2. 键盘相关 (假装没有键盘，一直返回无按键)
// =========================================
static void __am_input_config(AM_INPUT_CONFIG_T *cfg) { cfg->present = false; }
static void __am_input_keybrd(AM_INPUT_KEYBRD_T *kbd) { kbd->keydown = 0; kbd->keycode = AM_KEY_NONE; }

// =========================================
// 3. 显卡相关 (全假，让游戏死心切回字符模式)
// =========================================
static void __am_gpu_config(AM_GPU_CONFIG_T *cfg) { 
  cfg->present = false; 
  cfg->has_accel = false;
  
  // 【关键修复】：骗它屏幕有 256x240 这么大！
  // 这样 FCEUX 的字符渲染器才知道该打印多少列和多少行
  cfg->width = 256;  
  cfg->height = 240; 
  cfg->vmemsz = 0;
}
static void __am_gpu_status(AM_GPU_STATUS_T *stat) { stat->ready = true; }
static void __am_gpu_fbdraw(AM_GPU_FBDRAW_T *draw) { }

// =========================================
// 4. 其他外设 (全部拒绝)
// =========================================
static void __am_uart_config(AM_UART_CONFIG_T *cfg)   { cfg->present = false; }
static void __am_audio_config(AM_AUDIO_CONFIG_T *cfg) { cfg->present = false; }
static void __am_audio_ctrl(AM_AUDIO_CTRL_T *ctrl) { }
static void __am_audio_status(AM_AUDIO_STATUS_T *stat) { stat->count = 0; }
static void __am_audio_play(AM_AUDIO_PLAY_T *play) { }

typedef void (*handler_t)(void *buf);
static void *lut[128] = {
  [AM_TIMER_CONFIG] = __am_timer_config,
  [AM_TIMER_RTC   ] = __am_timer_rtc,
  [AM_TIMER_UPTIME] = __am_timer_uptime,
  
  [AM_INPUT_CONFIG] = __am_input_config,
  [AM_INPUT_KEYBRD] = __am_input_keybrd,
  
  [AM_GPU_CONFIG  ] = __am_gpu_config,
  [AM_GPU_STATUS  ] = __am_gpu_status,
  [AM_GPU_FBDRAW  ] = __am_gpu_fbdraw,
  
  [AM_UART_CONFIG ] = __am_uart_config,
  
  [AM_AUDIO_CONFIG] = __am_audio_config,
  [AM_AUDIO_CTRL  ] = __am_audio_ctrl,
  [AM_AUDIO_STATUS] = __am_audio_status,
  [AM_AUDIO_PLAY  ] = __am_audio_play,
};

static void fail(void *buf) { panic("access nonexist register"); }

bool ioe_init() {
  for (int i = 0; i < LENGTH(lut); i++)
    if (!lut[i]) lut[i] = fail;
  __am_timer_init();
  return true;
}

// 还原成这两行最清爽的代码！
void ioe_read (int reg, void *buf) { ((handler_t)lut[reg])(buf); }
void ioe_write(int reg, void *buf) { ((handler_t)lut[reg])(buf); }
