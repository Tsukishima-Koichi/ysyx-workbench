#include "trap.h"
int main() {
    unsigned int r;
    asm volatile("bext %0, %1, %2" : "=r"(r) : "r"(0xFFFFFFFF), "r"(0));  check(r == 1);
    asm volatile("bext %0, %1, %2" : "=r"(r) : "r"(0x00000000), "r"(5));  check(r == 0);
    asm volatile("bext %0, %1, %2" : "=r"(r) : "r"(0x80000000), "r"(31)); check(r == 1);
    asm volatile("bext %0, %1, %2" : "=r"(r) : "r"(0x7FFFFFFF), "r"(31)); check(r == 0);
    return 0;
}
