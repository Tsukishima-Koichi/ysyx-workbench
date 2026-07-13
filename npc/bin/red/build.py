import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from _build_core import *
DIR = os.path.dirname(os.path.abspath(__file__))
COE_IN = os.path.join(DIR, "..", "withMext", "irom.coe")
COE_OUT = os.path.join(DIR, "irom.coe")
BIN_OUT = os.path.join(DIR, "irom.bin")
B_ENC = {'clmul':0x0a6293b3,'clmulh':0x0a62b3b3,'clmulr':0x0a62a3b3}
TESTS = [
    ("clmul","rrr",[(0,0,0),(1,1,1),(3,3,5),(0xFF,0xFF,0x5555)]),
    ("clmulh","rrr",[(0,0,0),(3,0x80000000,1),(0xFFFFFFFF,0xFFFFFFFF,0x55555555)]),
    ("clmulr","rrr",[(0,0,0),(3,0x80000000,3),(0xFFFFFFFF,0xFFFFFFFF,0xAAAAAAAA)]),
]
build(COE_IN, COE_OUT, BIN_OUT, B_ENC, TESTS, 40)
