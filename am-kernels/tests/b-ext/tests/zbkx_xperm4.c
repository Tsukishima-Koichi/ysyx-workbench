#include "trap.h"
int main() {
    unsigned int r;
    // identity: rs2=0x76543210 selects nibbles in order
    asm volatile("xperm4 %0, %1, %2" : "=r"(r) : "r"(0xFEDCBA98), "r"(0x76543210));
    check(r == 0xFEDCBA98);
    // all select nibble 0
    asm volatile("xperm4 %0, %1, %2" : "=r"(r) : "r"(0x12345678), "r"(0x00000000));
    check(r == 0x88888888);
    // duplicate nibbles
    asm volatile("xperm4 %0, %1, %2" : "=r"(r) : "r"(0x76543210), "r"(0x33332222));
    check(r == 0x33332222);
    return 0;
}
