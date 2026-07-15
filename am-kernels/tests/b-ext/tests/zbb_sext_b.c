#include "trap.h"
int main() {
    unsigned int r;
    asm volatile("sext.b %0, %1" : "=r"(r) : "r"(0xFF)); check(r == 0xFFFFFFFF);
    asm volatile("sext.b %0, %1" : "=r"(r) : "r"(0x7F)); check(r == 0x7F);
    asm volatile("sext.b %0, %1" : "=r"(r) : "r"(0x80)); check(r == 0xFFFFFF80);
    asm volatile("sext.b %0, %1" : "=r"(r) : "r"(0x00)); check(r == 0);
    return 0;
}
