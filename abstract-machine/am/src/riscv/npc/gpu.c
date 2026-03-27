#include <am.h>

void __am_gpu_init() {
}

void __am_gpu_config(AM_GPU_CONFIG_T *cfg) {
  // 随便骗它一个分辨率，只要不报错就行
  cfg->present = true;
  cfg->has_accel = false;
  cfg->width = 400;
  cfg->height = 300;
  cfg->vmemsz = 0;
}

void __am_gpu_fbdraw(AM_GPU_FBDRAW_T *ctl) {
  // 字符版玛丽不需要画像素，这里什么都不做
}

void __am_gpu_status(AM_GPU_STATUS_T *status) {
  status->ready = true;
}
