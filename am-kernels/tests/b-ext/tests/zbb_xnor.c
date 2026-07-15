#include "trap.h"
int main() {
    unsigned int r;
    asm volatile("xnor %0, %1, %2" : "=r"(r) : "r"(0xFF), "r"(0xFF));      check(r == 0xFFFFFFFF);
    asm volatile("xnor %0, %1, %2" : "=r"(r) : "r"(0xAAAAAAAA), "r"(0x55555555)); check(r == 0);
    asm volatile("xnor %0, %1, %2" : "=r"(r) : "r"(0x1234), "r"(0x5678));  check(r == ~(0x1234 ^ 0x5678));
    return 0;
}
