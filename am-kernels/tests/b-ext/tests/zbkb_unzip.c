#include "trap.h"
int main() {
    unsigned int r;
    asm volatile("unzip %0, %1" : "=r"(r) : "r"(0x55555555));    check(r == 0x0000FFFF);
    asm volatile("unzip %0, %1" : "=r"(r) : "r"(0xAAAAAAAA));    check(r == 0xFFFF0000);
    asm volatile("unzip %0, %1" : "=r"(r) : "r"(0x131C1F60));    check(r == 0x12345678);
    return 0;
}