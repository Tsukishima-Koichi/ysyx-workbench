#include "trap.h"
int main() {
    unsigned int r;
    asm volatile("sh2add %0, %1, %2" : "=r"(r) : "r"(3), "r"(7));     check(r == 19);
    asm volatile("sh2add %0, %1, %2" : "=r"(r) : "r"(0), "r"(100));   check(r == 100);
    asm volatile("sh2add %0, %1, %2" : "=r"(r) : "r"(10), "r"(0));    check(r == 40);
    asm volatile("sh2add %0, %1, %2" : "=r"(r) : "r"(0x3FFFFFFF), "r"(5)); check(r == 0xFFFFFFFC + 5);
    return 0;
}
