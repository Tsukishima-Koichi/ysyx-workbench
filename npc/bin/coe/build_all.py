#!/usr/bin/env python3
"""Generate individual COE files for all 37 B-extension instructions.
Each: withMext base + 1 test function, expect 38 (37 RV32I + 1).
Output: bin/coe/<name>/irom.coe + irom.bin + dram.bin
"""
import sys, os, struct

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from _build_core import *

DIR = os.path.dirname(os.path.abspath(__file__))
COE_IN = os.path.join(DIR, "..", "withMext", "irom.coe")
DRAM_BIN = os.path.join(DIR, "..", "withMext", "dram.bin")

# All 37 B-extension instructions
ALL_TESTS = [
    # Safe (22)
    ("sh1add", "rrr", [(5,10,20),(0,42,42),(1,0,2),(0x1000,0x10,0x2010)]),
    ("sh2add", "rrr", [(5,100,120),(0,42,42),(1,0,4),(0x100,0x1000,0x1400)]),
    ("sh3add", "rrr", [(5,100,140),(0,42,42),(1,0,8),(0x80,0x1000,0x1400)]),
    ("bset",   "rrr", [(0,0,1),(0xF0,3,0xF8),(0,31,0x80000000)]),
    ("bclr",   "rrr", [(0xFF,0,0xFE),(0xFF,3,0xF7),(0xFFFFFFFF,31,0x7FFFFFFF)]),
    ("binv",   "rrr", [(0,0,1),(0x0F,3,0x07),(0,31,0x80000000)]),
    ("bext",   "rrr", [(1,0,1),(0x80,7,1),(0x80,0,0),(0x80000000,31,1)]),
    ("bseti",  "rri", [(0,0,1),(0xF0,3,0xF8),(0,31,0x80000000)]),
    ("bclri",  "rri", [(0xFF,0,0xFE),(0xFF,3,0xF7),(0xFFFFFFFF,31,0x7FFFFFFF)]),
    ("binvi",  "rri", [(0,0,1),(0x0F,3,0x07),(0,31,0x80000000)]),
    ("bexti",  "rri", [(1,0,1),(0x80,7,1),(0x80,0,0),(0x80000000,31,1)]),
    ("andn",   "rrr", [(0xFF,0x0F,0xF0),(0x12345678,0xFFFF0000,0x00005678),(0,0xFF,0)]),
    ("orn",    "rrr", [(0xF0,0x0F,0xFFFFFFF0),(0,0,0xFFFFFFFF)]),
    ("xnor",   "rrr", [(0xFF,0x0F,0xFFFFFF0F),(0xAAAAAAAA,0x55555555,0x00000000)]),
    ("sext.b", "ru",  [(0x7F,0,0x7F),(0x80,0,0xFFFFFF80),(0,0,0),(0xFF,0,0xFFFFFFFF)]),
    ("sext.h", "ru",  [(0x7FFF,0,0x7FFF),(0x8000,0,0xFFFF8000),(0,0,0)]),
    ("zext.h", "ru",  [(0x1234ABCD,0,0x0000ABCD),(0x87658000,0,0x00008000),(0,0,0)]),
    ("orc.b",  "ru",  [(0x01020304,0,0xFFFFFFFF),(0x00010000,0,0x00FF0000),(0,0,0)]),
    ("rev8",   "ru",  [(0x12345678,0,0x78563412),(0x01020304,0,0x04030201),(0,0,0)]),
    ("brev8",  "ru",  [(0x01020304,0,0x8040C020),(0,0,0),(1,0,0x80)]),
    ("pack",   "rrr", [(0x1234,0x5678,0x56781234),(0,0,0)]),
    ("packh",  "rrr", [(0x12,0x34,0x34123412),(0,0,0)]),
    # Green (8)
    ("rol",    "rrr", [(1,1,2),(0x12345678,4,0x23456781),(0x80000000,1,1),(0,8,0)]),
    ("ror",    "rrr", [(0x12345678,4,0x81234567),(0x80000000,1,0x40000000),(1,1,0x80000000),(0,8,0)]),
    ("rori",   "rri", [(0x12345678,4,0x81234567),(0x80000000,1,0x40000000),(1,1,0x80000000)]),
    ("max",    "rrr", [(0xFFFFFFFF,0,0),(5,10,10),((-10)&0xFFFFFFFF,(-5)&0xFFFFFFFF,(-5)&0xFFFFFFFF)]),
    ("maxu",   "rrr", [(5,10,10),(0xFFFFFFFF,0,0xFFFFFFFF),(0,5,5)]),
    ("min",    "rrr", [(0xFFFFFFFF,0,0xFFFFFFFF),(5,10,5),((-10)&0xFFFFFFFF,(-5)&0xFFFFFFFF,(-10)&0xFFFFFFFF)]),
    ("minu",   "rrr", [(5,10,5),(0xFFFFFFFF,0,0),(0,5,0)]),
    ("xperm8", "rrr", [(0,0,0),(0xFEDCBA98,0x76543210,0xFEDCBA98)]),
    # Yellow (4)
    ("clz",    "ru",  [(0x80000000,0,0),(1,0,31),(0x0F000000,0,4),(0,0,32)]),
    ("ctz",    "ru",  [(0x80000000,0,31),(0x10,0,4),(1,0,0),(0,0,32)]),
    ("cpop",   "ru",  [(0,0,0),(0xFFFFFFFF,0,32),(0x12345678,0,13)]),
    ("xperm4", "rrr", [(0,0,0),(0xFEDCBA98,0x76543210,0xFEDCBA98)]),
    # Red (3)
    ("clmul",  "rrr", [(0,0,0),(1,1,1),(3,3,5),(0xFF,0xFF,0x5555)]),
    ("clmulh", "rrr", [(0,0,0),(3,0x80000000,1),(0xFFFFFFFF,0xFFFFFFFF,0x55555555)]),
    ("clmulr", "rrr", [(0,0,0),(3,0x80000000,3),(0xFFFFFFFF,0xFFFFFFFF,0xAAAAAAAA)]),
    # Zbkb extra (2)
    ("zip",   "ru",  [(0x0000FFFF,0,0x55555555),(0xFFFF0000,0,0xAAAAAAAA),(0x12345678,0,0x131C1F60)]),
    ("unzip", "ru",  [(0x55555555,0,0x0000FFFF),(0xAAAAAAAA,0,0xFFFF0000),(0x131C1F60,0,0x12345678)]),
]

# All encodings
B_ENC = {
    'sh1add':0x2062a3b3,'sh2add':0x2062c3b3,'sh3add':0x2062e3b3,
    'bset':0x286293b3,'bclr':0x486293b3,'binv':0x686293b3,'bext':0x4862d3b3,
    'bseti':0x28529393,'bclri':0x48529393,'binvi':0x68529393,'bexti':0x4852d393,
    'andn':0x4062f3b3,'orn':0x4062e3b3,'xnor':0x4062c3b3,
    'sext.b':0x60429393,'sext.h':0x60529393,'zext.h':0x0802c3b3,
    'orc.b':0x2872d393,'rev8':0x6982d393,'brev8':0x6872d393,
    'pack':0x0862c3b3,'packh':0x0862f3b3,
    'rol':0x606293b3,'ror':0x6062d3b3,'rori':0x6052d393,
    'max':0x0a62e3b3,'maxu':0x0a62f3b3,'min':0x0a62c3b3,'minu':0x0a62d3b3,
    'xperm8':0x2862c3b3, 'xperm4':0x2862a3b3,
    'clz':0x60029393,'ctz':0x60129393,'cpop':0x60229393,
    'clmul':0x0a6293b3,'clmulh':0x0a62b3b3,'clmulr':0x0a62a3b3,
    'zip':0x08f29393,'unzip':0x08f2d393,
}

total = len(ALL_TESTS)
for i, (name, fmt, cases) in enumerate(ALL_TESTS):
    out_dir = os.path.join(DIR, name)
    os.makedirs(out_dir, exist_ok=True)
    COE_OUT = os.path.join(out_dir, "irom.coe")
    BIN_OUT = os.path.join(out_dir, "irom.bin")

    test = [(name, fmt, cases)]
    enc  = {name: B_ENC[name]}

    build(COE_IN, COE_OUT, BIN_OUT, enc, test, 38)

    # Copy dram
    dram_out = os.path.join(out_dir, "dram.bin")
    with open(DRAM_BIN, 'rb') as f:
        dram_data = f.read()
    with open(dram_out, 'wb') as f:
        f.write(dram_data)

    print(f"  [{i+1:2d}/{total}] {name}")

print(f"\nDone! {total} individual test COEs in {DIR}/")
