#include "trap.h"
// clmulr: bits [62:31] of carry-less product prod[62:31]
int main() {
    unsigned int r;
    // x^31 * x^31 = x^62, prod[62:31]: bit 62 -> result bit 31
    asm volatile("clmulr %0, %1, %2" : "=r"(r) : "r"(0x80000000), "r"(0x80000000)); check(r == 0x80000000);
    // (all-1)^2 in GF(2): prod[62:31] = 0xAAAAAAAA
    asm volatile("clmulr %0, %1, %2" : "=r"(r) : "r"(0xFFFFFFFF), "r"(0xFFFFFFFF)); check(r == 0xAAAAAAAA);
    // Determinism: same inputs give same output
    unsigned int r2, r3;
    asm volatile("clmulr %0, %1, %2" : "=r"(r2) : "r"(0x12345678), "r"(0x9ABCDEF0));
    asm volatile("clmulr %0, %1, %2" : "=r"(r3) : "r"(0x12345678), "r"(0x9ABCDEF0));
    check(r2 == r3);
    return 0;
}
