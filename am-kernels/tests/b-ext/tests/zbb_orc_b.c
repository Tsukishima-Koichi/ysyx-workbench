#include "trap.h"
int main() {
    unsigned int r;
    asm volatile("orc.b %0, %1" : "=r"(r) : "r"(0x00010203)); check(r == 0x00FFFFFF);
    asm volatile("orc.b %0, %1" : "=r"(r) : "r"(0x00000000)); check(r == 0);
    asm volatile("orc.b %0, %1" : "=r"(r) : "r"(0x00FF0000)); check(r == 0x00FF0000);
    return 0;
}
