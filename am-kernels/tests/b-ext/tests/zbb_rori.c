#include "trap.h"
int main() {
    unsigned int r;
    asm volatile("rori %0, %1, 1" : "=r"(r) : "r"(0x80000001));  check(r == 0xC0000000);
    asm volatile("rori %0, %1, 1" : "=r"(r) : "r"(0x00000001));  check(r == 0x80000000);
    asm volatile("rori %0, %1, 16" : "=r"(r) : "r"(0x12345678)); check(r == 0x56781234);
    asm volatile("rori %0, %1, 0" : "=r"(r) : "r"(0xDEADBEEF));  check(r == 0xDEADBEEF);
    return 0;
}
