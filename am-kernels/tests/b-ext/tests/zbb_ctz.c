#include "trap.h"
int main() {
    unsigned int r;
    asm volatile("ctz %0, %1" : "=r"(r) : "r"(1));          check(r == 0);
    asm volatile("ctz %0, %1" : "=r"(r) : "r"(0x80000000)); check(r == 31);
    asm volatile("ctz %0, %1" : "=r"(r) : "r"(0x10));       check(r == 4);
    asm volatile("ctz %0, %1" : "=r"(r) : "r"(0));          check(r == 32);
    return 0;
}
