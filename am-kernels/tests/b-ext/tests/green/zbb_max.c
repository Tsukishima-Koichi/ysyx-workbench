#include "trap.h"
int main() {
    unsigned int r;
    asm volatile("max %0, %1, %2" : "=r"(r) : "r"(10), "r"(20));       check(r == 20);
    asm volatile("max %0, %1, %2" : "=r"(r) : "r"(-1), "r"(0));        check((int)r == 0);
    asm volatile("max %0, %1, %2" : "=r"(r) : "r"(-100), "r"(-200));   check((int)r == -100);
    return 0;
}
