#include "trap.h"
int main() {
    unsigned int r;
    asm volatile("clmul %0, %1, %2" : "=r"(r) : "r"(3), "r"(5));        check(r == 15);
    asm volatile("clmul %0, %1, %2" : "=r"(r) : "r"(0x12345678), "r"(0)); check(r == 0);
    asm volatile("clmul %0, %1, %2" : "=r"(r) : "r"(1), "r"(1));        check(r == 1);
    asm volatile("clmul %0, %1, %2" : "=r"(r) : "r"(0x1), "r"(0x100));  check(r == 0x100);
    return 0;
}
