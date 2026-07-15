#include "trap.h"
int main() {
    unsigned int r;
    asm volatile("bset %0, %1, %2" : "=r"(r) : "r"(0), "r"(0));   check(r == 1);
    asm volatile("bset %0, %1, %2" : "=r"(r) : "r"(0), "r"(5));   check(r == 0x20);
    asm volatile("bset %0, %1, %2" : "=r"(r) : "r"(0), "r"(31));  check(r == 0x80000000);
    asm volatile("bset %0, %1, %2" : "=r"(r) : "r"(0xFFFF0000), "r"(3)); check(r == 0xFFFF0008);
    return 0;
}
