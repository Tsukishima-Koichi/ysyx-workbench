#include "trap.h"
int main() {
    unsigned int r;
    asm volatile("pack %0, %1, %2" : "=r"(r) : "r"(0x0000AAAA), "r"(0x0000BBBB)); check(r == 0xBBBBAAAA);
    asm volatile("pack %0, %1, %2" : "=r"(r) : "r"(0x00000000), "r"(0x0000FFFF)); check(r == 0xFFFF0000);
    asm volatile("pack %0, %1, %2" : "=r"(r) : "r"(0x87654321), "r"(0x12345678)); check(r == 0x56784321);
    return 0;
}
