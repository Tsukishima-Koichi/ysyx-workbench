#include "trap.h"
// clmulh: upper 32 bits of carry-less product prod[63:32]
int main() {
    unsigned int r;
    // 3 * 5 = 15 in GF(2), product fits in low bits, high bits = 0
    asm volatile("clmulh %0, %1, %2" : "=r"(r) : "r"(3), "r"(5)); check(r == 0);
    // x^31 * x^31 = x^62, high bits: bit[62]=1 -> result bit[30]=1
    asm volatile("clmulh %0, %1, %2" : "=r"(r) : "r"(0x80000000), "r"(0x80000000)); check(r == 0x40000000);
    // (all-1)^2 in GF(2): only even bits set -> prod[63:32] = 0x55555555
    asm volatile("clmulh %0, %1, %2" : "=r"(r) : "r"(0xFFFFFFFF), "r"(0xFFFFFFFF)); check(r == 0x55555555);
    return 0;
}
