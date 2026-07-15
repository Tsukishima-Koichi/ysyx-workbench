#include "trap.h"
int main() {
    unsigned int r;
    asm volatile("packh %0, %1, %2" : "=r"(r) : "r"(0xAB), "r"(0xCD));          check(r == 0xCDABCDAB);
    asm volatile("packh %0, %1, %2" : "=r"(r) : "r"(0x00), "r"(0xFF));          check(r == 0xFF00FF00);
    asm volatile("packh %0, %1, %2" : "=r"(r) : "r"(0x12), "r"(0x34));          check(r == 0x34123412);
    return 0;
}
