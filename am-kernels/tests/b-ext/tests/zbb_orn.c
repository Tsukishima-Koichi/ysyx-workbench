#include "trap.h"
int main() {
    unsigned int r;
    asm volatile("orn %0, %1, %2" : "=r"(r) : "r"(0xF0), "r"(0x0F));        check(r == 0xFFFFFFF0);
    asm volatile("orn %0, %1, %2" : "=r"(r) : "r"(0), "r"(0xFFFFFFFF));     check(r == 0);
    return 0;
}
