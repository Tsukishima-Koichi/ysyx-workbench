#ifndef __DIFFTEST_H__
#define __DIFFTEST_H__

#include <stdint.h>
#include <stdbool.h>

void init_difftest();
bool difftest_check();
bool difftest_commit(uint32_t commit_pc, int slot);
uint32_t difftest_get_nemu_pc();

extern "C" int get_gpr(int idx);

#endif
