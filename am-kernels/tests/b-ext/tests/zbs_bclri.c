#include "trap.h"
int main() {
    unsigned int r;
    asm volatile("bclri %0, %1, 0" : "=r"(r) : "r"(0xFFFFFFFF));  check(r == 0xFFFFFFFE);
    asm volatile("bclri %0, %1, 15" : "=r"(r) : "r"(0xFFFFFFFF)); check(r == 0xFFFF7FFF);
    asm volatile("bclri %0, %1, 5" : "=r"(r) : "r"(0));           check(r == 0);
    return 0;
}
