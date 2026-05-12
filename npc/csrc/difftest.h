#ifndef __DIFFTEST_H__
#define __DIFFTEST_H__

#include <stdint.h>
#include <stdbool.h>

void init_difftest();
// 检查上一拍寄存器是否与 NEMU 匹配
bool difftest_check();
// 当前拍提交新指令，检查 PC 并步进 NEMU
bool difftest_commit(uint32_t commit_pc);

// 暴露用于检查 a0 寄存器的接口给主循环
extern "C" int get_gpr(int idx);

#endif
