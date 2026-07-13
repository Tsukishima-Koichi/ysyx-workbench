import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from _build_core import *
DIR = os.path.dirname(os.path.abspath(__file__))
COE_IN = os.path.join(DIR, "..", "withMext", "irom.coe")
COE_OUT = os.path.join(DIR, "irom.coe")
BIN_OUT = os.path.join(DIR, "irom.bin")
B_ENC = {'clz':0x60029393,'ctz':0x60129393,'cpop':0x60229393,'xperm4':0x2862a3b3}
TESTS = [
    ("clz","ru",[(0x80000000,0,0),(1,0,31),(0x0F000000,0,4),(0,0,32)]),
    ("ctz","ru",[(0x80000000,0,31),(0x10,0,4),(1,0,0),(0,0,32)]),
    ("cpop","ru",[(0,0,0),(0xFFFFFFFF,0,32),(0x12345678,0,13)]),
    ("xperm4","rrr",[(0,0,0),(0xFEDCBA98,0x76543210,0xFEDCBA98)]),
]
build(COE_IN, COE_OUT, BIN_OUT, B_ENC, TESTS, 41)
