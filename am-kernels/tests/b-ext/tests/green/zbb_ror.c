#include "trap.h"
int main() {
    unsigned int r;
    asm volatile("ror %0, %1, %2" : "=r"(r) : "r"(0x80000001), "r"(1));  check(r == 0xC0000000);
    asm volatile("ror %0, %1, %2" : "=r"(r) : "r"(0x80000001), "r"(31)); check(r == 0x00000003);
    asm volatile("ror %0, %1, %2" : "=r"(r) : "r"(0x12345678), "r"(16)); check(r == 0x56781234);
    asm volatile("ror %0, %1, %2" : "=r"(r) : "r"(0xDEADBEEF), "r"(0));  check(r == 0xDEADBEEF);
    return 0;
}
