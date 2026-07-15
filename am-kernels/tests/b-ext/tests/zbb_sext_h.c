#include "trap.h"
int main() {
    unsigned int r;
    asm volatile("sext.h %0, %1" : "=r"(r) : "r"(0xFFFF)); check(r == 0xFFFFFFFF);
    asm volatile("sext.h %0, %1" : "=r"(r) : "r"(0x7FFF)); check(r == 0x7FFF);
    asm volatile("sext.h %0, %1" : "=r"(r) : "r"(0x8000)); check(r == 0xFFFF8000);
    return 0;
}
