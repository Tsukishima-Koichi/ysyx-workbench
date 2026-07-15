#include "trap.h"
int main() {
    unsigned int r;
    asm volatile("zext.h %0, %1" : "=r"(r) : "r"(0xFFFF));     check(r == 0xFFFF);
    asm volatile("zext.h %0, %1" : "=r"(r) : "r"(0x8000));     check(r == 0x8000);
    asm volatile("zext.h %0, %1" : "=r"(r) : "r"(0x1234ABCD)); check(r == 0xABCD);
    return 0;
}
