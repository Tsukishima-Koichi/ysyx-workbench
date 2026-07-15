#include "trap.h"
int main() {
    unsigned int r;
    asm volatile("rev8 %0, %1" : "=r"(r) : "r"(0x01020304)); check(r == 0x04030201);
    asm volatile("rev8 %0, %1" : "=r"(r) : "r"(0xDEADBEEF)); check(r == 0xEFBEADDE);
    asm volatile("rev8 %0, %1" : "=r"(r) : "r"(0x00000000)); check(r == 0);
    asm volatile("rev8 %0, %1" : "=r"(r) : "r"(0xAA000055)); check(r == 0x550000AA);
    return 0;
}
