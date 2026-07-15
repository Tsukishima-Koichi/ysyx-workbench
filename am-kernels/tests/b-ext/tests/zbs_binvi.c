#include "trap.h"
int main() {
    unsigned int r;
    asm volatile("binvi %0, %1, 4" : "=r"(r) : "r"(0x0F0F0F0F));  check(r == 0x0F0F0F1F);
    asm volatile("binvi %0, %1, 0" : "=r"(r) : "r"(0xFFFFFFFF));  check(r == 0xFFFFFFFE);
    return 0;
}
