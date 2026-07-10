#include "trap.h"
int main() {
    unsigned int r;
    asm volatile("maxu %0, %1, %2" : "=r"(r) : "r"(10), "r"(20));  check(r == 20);
    asm volatile("maxu %0, %1, %2" : "=r"(r) : "r"(-1), "r"(0));   check(r == (unsigned int)-1);
    return 0;
}
