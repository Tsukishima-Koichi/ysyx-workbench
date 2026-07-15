#include "trap.h"
int main() {
    unsigned int r;
    // identity
    asm volatile("xperm8 %0, %1, %2" : "=r"(r) : "r"(0xDEADBEEF), "r"(0x03020100));
    check(r == 0xDEADBEEF);
    // reverse bytes
    asm volatile("xperm8 %0, %1, %2" : "=r"(r) : "r"(0xDEADBEEF), "r"(0x00010203));
    check(r == 0xEFBEADDE);
    // all select byte 0
    asm volatile("xperm8 %0, %1, %2" : "=r"(r) : "r"(0xDEADBEEF), "r"(0x00000000));
    check(r == 0xEFEFEFEF);
    // out of range -> 0
    asm volatile("xperm8 %0, %1, %2" : "=r"(r) : "r"(0xDEADBEEF), "r"(0x04040404));
    check(r == 0);
    return 0;
}
