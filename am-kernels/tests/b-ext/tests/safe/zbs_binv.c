#include "trap.h"
int main() {
    unsigned int r;
    asm volatile("binv %0, %1, %2" : "=r"(r) : "r"(0), "r"(0));  check(r == 1);
    asm volatile("binv %0, %1, %2" : "=r"(r) : "r"(1), "r"(0));  check(r == 0);
    asm volatile("binv %0, %1, %2" : "=r"(r) : "r"(0xAAAAAAAA), "r"(0)); check(r == 0xAAAAAAAB);
    // double toggle = identity
    asm volatile("binv %0, %1, %2" : "=r"(r) : "r"(0x12345678), "r"(10));
    asm volatile("binv %0, %1, %2" : "=r"(r) : "r"(r), "r"(10));
    check(r == 0x12345678);
    return 0;
}
