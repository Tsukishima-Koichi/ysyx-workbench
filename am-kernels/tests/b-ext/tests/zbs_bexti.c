#include "trap.h"
int main() {
    unsigned int r;
    asm volatile("bexti %0, %1, 31" : "=r"(r) : "r"(0x80000000)); check(r == 1);
    asm volatile("bexti %0, %1, 0"  : "=r"(r) : "r"(0x00000001)); check(r == 1);
    asm volatile("bexti %0, %1, 1"  : "=r"(r) : "r"(0x00000001)); check(r == 0);
    return 0;
}
