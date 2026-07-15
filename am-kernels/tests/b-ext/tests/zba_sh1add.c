#include "trap.h"
int main() {
    unsigned int r;
    asm volatile("sh1add %0, %1, %2" : "=r"(r) : "r"(5), "r"(10));    check(r == 20);
    asm volatile("sh1add %0, %1, %2" : "=r"(r) : "r"(0), "r"(42));    check(r == 42);
    asm volatile("sh1add %0, %1, %2" : "=r"(r) : "r"(1), "r"(0));     check(r == 2);
    asm volatile("sh1add %0, %1, %2" : "=r"(r) : "r"(0x1000), "r"(0x10)); check(r == 0x2010);
    return 0;
}
