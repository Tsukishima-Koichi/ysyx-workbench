#include <am.h>
#include <nemu.h>

// 这里的偏移量必须与 NEMU 端 audio.c 中的 enum 保持严格一致
#define AUDIO_FREQ_ADDR      (AUDIO_ADDR + 0x00)
#define AUDIO_CHANNELS_ADDR  (AUDIO_ADDR + 0x04)
#define AUDIO_SAMPLES_ADDR   (AUDIO_ADDR + 0x08)
#define AUDIO_SBUF_SIZE_ADDR (AUDIO_ADDR + 0x0c)
#define AUDIO_INIT_ADDR      (AUDIO_ADDR + 0x10)
#define AUDIO_COUNT_ADDR     (AUDIO_ADDR + 0x14)

void __am_audio_init() {
}

void __am_audio_config(AM_AUDIO_CONFIG_T *cfg) {
  // 读取硬件预设的 sbuf 总大小
  cfg->present = true;
  cfg->bufsize = inl(AUDIO_SBUF_SIZE_ADDR);
}

void __am_audio_ctrl(AM_AUDIO_CTRL_T *ctrl) {
  // 1. 设置频率、声道、采样数
  outl(AUDIO_FREQ_ADDR,     ctrl->freq);
  outl(AUDIO_CHANNELS_ADDR, ctrl->channels);
  outl(AUDIO_SAMPLES_ADDR,  ctrl->samples);
  // 2. 往 INIT 寄存器写 1，触发 NEMU 端的 SDL_OpenAudio
  outl(AUDIO_INIT_ADDR,     1);
}

void __am_audio_status(AM_AUDIO_STATUS_T *stat) {
  // 读取当前 sbuf 中已经占用的字节数
  stat->count = inl(AUDIO_COUNT_ADDR);
}

void __am_audio_play(AM_AUDIO_PLAY_T *ctl) {
  uint32_t len = ctl->buf.end - ctl->buf.start;
  uint32_t bufsize = inl(AUDIO_SBUF_SIZE_ADDR);
  uint8_t *src = (uint8_t *)ctl->buf.start;
  uint8_t *sbuf = (uint8_t *)(uintptr_t)AUDIO_SBUF_ADDR;

  // 1. 检查当前 sbuf 剩余空间是否足够容纳这次写入的数据
  // 如果空间不够，就一直循环等待硬件回调函数（消费者）读走数据
  while (bufsize - inl(AUDIO_COUNT_ADDR) < len);

  // 2. 将音频数据拷贝到 sbuf 的末尾（当前有效数据 count 的位置）
  uint32_t count = inl(AUDIO_COUNT_ADDR);
  for (uint32_t i = 0; i < len; i++) {
    sbuf[count + i] = src[i];
  }

  // 3. 更新硬件中的 count 寄存器，告诉硬件“有新货到了”
  outl(AUDIO_COUNT_ADDR, count + len);
}
