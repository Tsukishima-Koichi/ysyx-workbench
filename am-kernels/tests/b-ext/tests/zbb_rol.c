#include "trap.h"
int main() {
    unsigned int r;
    asm volatile("rol %0, %1, %2" : "=r"(r) : "r"(0x80000001), "r"(1));  check(r == 0x00000003);
    asm volatile("rol %0, %1, %2" : "=r"(r) : "r"(0x80000000), "r"(1));  check(r == 0x00000001);
    asm volatile("rol %0, %1, %2" : "=r"(r) : "r"(0x12345678), "r"(16)); check(r == 0x56781234);
    asm volatile("rol %0, %1, %2" : "=r"(r) : "r"(0xDEADBEEF), "r"(0));  check(r == 0xDEADBEEF);
    return 0;
}
