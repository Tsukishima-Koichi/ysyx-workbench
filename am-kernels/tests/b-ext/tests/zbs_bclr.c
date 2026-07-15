#include "trap.h"
int main() {
    unsigned int r;
    asm volatile("bclr %0, %1, %2" : "=r"(r) : "r"(0xFFFFFFFF), "r"(0));  check(r == 0xFFFFFFFE);
    asm volatile("bclr %0, %1, %2" : "=r"(r) : "r"(0xFFFFFFFF), "r"(31)); check(r == 0x7FFFFFFF);
    asm volatile("bclr %0, %1, %2" : "=r"(r) : "r"(0xAAAAAAAA), "r"(0));  check(r == 0xAAAAAAAA);
    return 0;
}
