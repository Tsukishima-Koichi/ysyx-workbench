#include "trap.h"
int main() {
    unsigned int r;
    asm volatile("bseti %0, %1, 0" : "=r"(r) : "r"(0));           check(r == 1);
    asm volatile("bseti %0, %1, 7" : "=r"(r) : "r"(0));           check(r == 0x80);
    asm volatile("bseti %0, %1, 0" : "=r"(r) : "r"(0xAAAAAAAA)); check(r == 0xAAAAAAAB);
    return 0;
}
