#include "trap.h"
int main() {
    unsigned int r;
    asm volatile("brev8 %0, %1" : "=r"(r) : "r"(0x01020304)); check(r == 0x8040C020);
    asm volatile("brev8 %0, %1" : "=r"(r) : "r"(0x00000000)); check(r == 0);
    asm volatile("brev8 %0, %1" : "=r"(r) : "r"(0xFFFFFFFF)); check(r == 0xFFFFFFFF);
    asm volatile("brev8 %0, %1" : "=r"(r) : "r"(0xAA55AA55)); check(r == 0x55AA55AA);
    return 0;
}
