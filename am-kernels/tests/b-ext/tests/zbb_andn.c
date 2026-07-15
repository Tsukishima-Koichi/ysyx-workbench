#include "trap.h"
int main() {
    unsigned int r;
    asm volatile("andn %0, %1, %2" : "=r"(r) : "r"(0xFF), "r"(0x0F));       check(r == 0xF0);
    asm volatile("andn %0, %1, %2" : "=r"(r) : "r"(0xAAAAAAAA), "r"(0x55555555)); check(r == 0xAAAAAAAA);
    asm volatile("andn %0, %1, %2" : "=r"(r) : "r"(0xFFFFFFFF), "r"(0xFFFFFFFF)); check(r == 0);
    return 0;
}
