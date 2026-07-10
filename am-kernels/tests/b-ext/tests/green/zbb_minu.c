#include "trap.h"
int main() {
    unsigned int r;
    asm volatile("minu %0, %1, %2" : "=r"(r) : "r"(10), "r"(20));  check(r == 10);
    asm volatile("minu %0, %1, %2" : "=r"(r) : "r"(-1), "r"(1));   check(r == 1);
    return 0;
}
