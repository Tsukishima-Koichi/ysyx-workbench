#include <am.h>
#include <nemu.h>

// NEMU 规定，如果读取到的键盘码带有这个标记位，说明是“按下(keydown)”，否则是“松开(keyup)”
#define KEYDOWN_MASK 0x8000

void __am_input_keybrd(AM_INPUT_KEYBRD_T *kbd) {
  // 从键盘 MMIO 地址读取 32 位数据
  uint32_t code = inl(KBD_ADDR);
  
  // 如果没有任何按键事件，硬件会返回 AM_KEY_NONE (通常是 0)
  if (code == AM_KEY_NONE) {
    kbd->keydown = false;
    kbd->keycode = AM_KEY_NONE;
    return;
  }

  // 通过按位与运算检查 KEYDOWN_MASK 是否为 1
  kbd->keydown = (code & KEYDOWN_MASK) ? true : false;
  
  // 通过按位取反再与运算，把掩码位剔除，只保留纯净的按键真实编号 (断码)
  kbd->keycode = code & ~KEYDOWN_MASK;
}
