#include "trap.h"
int main() {
    unsigned int r;
    asm volatile("sh3add %0, %1, %2" : "=r"(r) : "r"(2), "r"(100));  check(r == 116);
    asm volatile("sh3add %0, %1, %2" : "=r"(r) : "r"(0), "r"(0xFF)); check(r == 0xFF);
    asm volatile("sh3add %0, %1, %2" : "=r"(r) : "r"(5), "r"(10));   check(r == 50);
    asm volatile("sh3add %0, %1, %2" : "=r"(r) : "r"(0x1FFFFFFF), "r"(1)); check(r == 0xFFFFFFF8 + 1);
    return 0;
}
