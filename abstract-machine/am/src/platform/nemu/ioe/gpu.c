#include <am.h>
#include <nemu.h>
#include <string.h>

#define SYNC_ADDR (VGACTL_ADDR + 4)

void __am_gpu_init() {
  // 【重要】之前的测试代码已经完成了它的历史使命，现在全部删掉！
  // 保持这个函数为空即可，因为硬件已经在 NEMU 里初始化好了。
}

void __am_gpu_config(AM_GPU_CONFIG_T *cfg) {
  uint32_t screen_wh = inl(VGACTL_ADDR);
  uint32_t h = screen_wh & 0xffff;
  uint32_t w = screen_wh >> 16;
  
  *cfg = (AM_GPU_CONFIG_T) {
    .present = true, .has_accel = false,
    .width = w, .height = h,
    .vmemsz = w * h * sizeof(uint32_t)
  };
}

// void __am_gpu_fbdraw(AM_GPU_FBDRAW_T *ctl) {
//   // 1. 获取显存首地址和传进来的像素数据首地址
//   uint32_t *fb = (uint32_t *)(uintptr_t)FB_ADDR;
//   uint32_t *pixels = (uint32_t *)ctl->pixels;
  
//   // 2. 必须再次读取屏幕总宽度，用于计算一维数组的正确偏移量
//   uint32_t screen_w = inl(VGACTL_ADDR) >> 16; 
  
//   // 3. 将 ctl->pixels 中的像素块，一行一行地绘制到屏幕的 (x, y) 坐标处
//   for (int i = 0; i < ctl->h; i++) {
//     for (int j = 0; j < ctl->w; j++) {
//       // 目标位置：(起始Y + 当前行) * 屏幕总宽 + (起始X + 当前列)
//       fb[(ctl->y + i) * screen_w + (ctl->x + j)] = pixels[i * ctl->w + j];
//     }
//   }

//   // 4. 如果要求同步，向硬件发送刷新信号
//   if (ctl->sync) {
//     outl(SYNC_ADDR, 1);
//   }
// }

void __am_gpu_fbdraw(AM_GPU_FBDRAW_T *ctl) {
  uint32_t *fb = (uint32_t *)(uintptr_t)FB_ADDR;
  uint32_t *pixels = (uint32_t *)ctl->pixels;
  int w = ctl->w, h = ctl->h, x = ctl->x, y = ctl->y;
  int screen_w = inl(VGACTL_ADDR) >> 16;

  for (int i = 0; i < h; i++) {
    // 计算每一行在显存中的起始偏移
    uint32_t *dst = fb + (y + i) * screen_w + x;
    // 计算当前行在源像素数组中的起始位置
    uint32_t *src = pixels + i * w;
    // 使用 memcpy 直接整行搬运（长度是 像素数 * 每个像素4字节）
    memcpy(dst, src, w * sizeof(uint32_t));
  }

  if (ctl->sync) {
    outl(SYNC_ADDR, 1);
  }
}

void __am_gpu_status(AM_GPU_STATUS_T *status) {
  status->ready = true;
}
