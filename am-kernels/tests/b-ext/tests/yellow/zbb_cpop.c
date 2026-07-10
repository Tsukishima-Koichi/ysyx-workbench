#include "trap.h"
int main() {
    unsigned int r;
    asm volatile("cpop %0, %1" : "=r"(r) : "r"(0));          check(r == 0);
    asm volatile("cpop %0, %1" : "=r"(r) : "r"(1));          check(r == 1);
    asm volatile("cpop %0, %1" : "=r"(r) : "r"(0xFFFFFFFF)); check(r == 32);
    asm volatile("cpop %0, %1" : "=r"(r) : "r"(0xAAAAAAAA)); check(r == 16);
    return 0;
}
