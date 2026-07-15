#include "trap.h"
int main() {
    unsigned int r;
    asm volatile("zip %0, %1" : "=r"(r) : "r"(0x0000FFFF));       check(r == 0x55555555);
    asm volatile("zip %0, %1" : "=r"(r) : "r"(0xFFFF0000));       check(r == 0xAAAAAAAA);
    asm volatile("zip %0, %1" : "=r"(r) : "r"(0x12345678));       check(r == 0x131C1F60);
    return 0;
}