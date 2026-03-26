/***************************************************************************************
* Copyright (c) 2014-2024 Zihao Yu, Nanjing University
*
* NEMU is licensed under Mulan PSL v2.
* You can use this software according to the terms and conditions of the Mulan PSL v2.
* You may obtain a copy of Mulan PSL v2 at:
*          http://license.coscl.org.cn/MulanPSL2
*
* THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
* EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
* MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
*
* See the Mulan PSL v2 for more details.
***************************************************************************************/

#include <device/map.h>
#include <SDL2/SDL.h>

enum {
  reg_freq,
  reg_channels,
  reg_samples,
  reg_sbuf_size,
  reg_init,
  reg_count,
  nr_reg
};

static uint8_t *sbuf = NULL;
static uint32_t *audio_base = NULL;

static void audio_play_cb(void *userdata, uint8_t *stream, int len) {
  uint32_t can_read = audio_base[reg_count];
  uint32_t nread = (len < can_read) ? len : can_read;

  if (nread > 0) {
    // 1. 永远从 sbuf 的最开头 (0 偏移) 读取数据
    memcpy(stream, sbuf, nread);
    
    // 2. 更新剩余数据量
    audio_base[reg_count] -= nread;

    // 3. 【核心修复】用 memmove 把剩下的没读完的数据，平移到 sbuf 的最前面！
    // 必须用 memmove，因为内存可能有重叠
    if (audio_base[reg_count] > 0) {
      memmove(sbuf, sbuf + nread, audio_base[reg_count]);
    }
  }

  // 4. 如果没喂饱 SDL，剩下的部分用 0 填充静音
  if (len > nread) {
    memset(stream + nread, 0, len - nread);
  }
}

static void audio_io_handler(uint32_t offset, int len, bool is_write) {
  uint32_t idx = offset / sizeof(uint32_t);
  
  // 当 Guest 程序往 reg_init 写入 1 时，初始化 SDL 音频系统
  if (is_write && idx == reg_init && audio_base[reg_init] == 1) {
    SDL_AudioSpec s = {};
    s.freq     = audio_base[reg_freq];
    s.channels = audio_base[reg_channels];
    s.samples  = audio_base[reg_samples];
    // s.samples  = 4096;
    s.format   = AUDIO_S16SYS; // 假设使用 16 位系统字节序
    s.userdata = NULL;
    s.callback = audio_play_cb;

    // 初始化并开启音频播放
    if (SDL_InitSubSystem(SDL_INIT_AUDIO) == 0) {
      if (SDL_OpenAudio(&s, NULL) == 0) {
        SDL_PauseAudio(0); // 开始播放
      }
    }
    // 初始化完成后，可以清零 init 标志或保持现状
    audio_base[reg_init] = 0; 
  }
  
  // 当 Guest 程序写入 sbuf 数据后，会手动更新 reg_count
  // 此时硬件只需要确保 sbuf_ptr 和 count 的关系正确即可
  // 在 AM_AUDIO_PLAY 的实现中，程序会向 sbuf 写入数据，然后增加 reg_count
}

void init_audio() {
  uint32_t space_size = sizeof(uint32_t) * nr_reg;
  audio_base = (uint32_t *)new_space(space_size);
  
  // 初始化流缓冲区大小寄存器
  audio_base[reg_sbuf_size] = CONFIG_SB_SIZE;
  audio_base[reg_count] = 0;

#ifdef CONFIG_HAS_PORT_IO
  add_pio_map ("audio", CONFIG_AUDIO_CTL_PORT, audio_base, space_size, audio_io_handler);
#else
  add_mmio_map("audio", CONFIG_AUDIO_CTL_MMIO, audio_base, space_size, audio_io_handler);
#endif

  sbuf = (uint8_t *)new_space(CONFIG_SB_SIZE);
  add_mmio_map("audio-sbuf", CONFIG_SB_ADDR, sbuf, CONFIG_SB_SIZE, NULL);
}
