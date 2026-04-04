#include <common.h>

#if defined(MULTIPROGRAM) && !defined(TIME_SHARING)
# define MULTIPROGRAM_YIELD() yield()
#else
# define MULTIPROGRAM_YIELD()
#endif

#define NAME(key) \
  [AM_KEY_##key] = #key,

static const char *keyname[256] __attribute__((used)) = {
  [AM_KEY_NONE] = "NONE",
  AM_KEYS(NAME)
};


// 串口写设备驱动
// 注意：串口是字符流设备，没有“偏移量”的概念，所以 offset 参数直接忽略
size_t serial_write(const void *buf, size_t offset, size_t len) {
  const char *str = (const char *)buf;
  for (size_t i = 0; i < len; i++) {
    putch(str[i]);
  }
  return len; // 返回成功写入的字节数
}


size_t events_read(void *buf, size_t offset, size_t len) {
  // 1. 调用 AM 的 API 读取键盘事件
  AM_INPUT_KEYBRD_T ev = io_read(AM_INPUT_KEYBRD);
  
  // 2. 如果当前没有按键按下或松开，直接返回 0
  if (ev.keycode == AM_KEY_NONE) {
    return 0;
  }

  // 3. 将事件格式化为文本
  // 【修复】这里使用框架自带的 keyname 数组！
  int ret = snprintf(buf, len, "%s %s\n", 
                     ev.keydown ? "kd" : "ku", 
                     keyname[ev.keycode]);
  
  return ret;
}


// 读取屏幕大小信息，格式化为字符串
size_t dispinfo_read(void *buf, size_t offset, size_t len) {
  // 从 AM 硬件层获取屏幕参数
  AM_GPU_CONFIG_T cfg = io_read(AM_GPU_CONFIG);
  
  // 按照 "WIDTH: %d\nHEIGHT: %d\n" 的格式写入 buf
  int ret = snprintf(buf, len, "WIDTH:%d\nHEIGHT:%d\n", cfg.width, cfg.height);
  return ret;
}

size_t fb_write(const void *buf, size_t offset, size_t len) {
  AM_GPU_CONFIG_T cfg = io_read(AM_GPU_CONFIG);
  int screen_w = cfg.width;

  // 1. 将字节偏移量除以 4，变成像素偏移量
  uint32_t pixel_offset = offset / 4;
  // 2. 计算出在屏幕上的二维坐标 (x, y)
  int y = pixel_offset / screen_w;
  int x = pixel_offset % screen_w;

  // 3. 调用 IOE 底层绘图接口，把像素画到屏幕上
  // 注意：由于我们上层 NDL 是“一行一行”调用 write 的，所以这里宽度就是写入的像素个数 (len / 4)，高度是 1
  io_write(AM_GPU_FBDRAW, x, y, (void *)buf, len / 4, 1, true); 

  return len;
}

void init_device() {
  Log("Initializing devices...");
  ioe_init();
}
