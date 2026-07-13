import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from _build_core import *
DIR = os.path.dirname(os.path.abspath(__file__))
COE_IN = os.path.join(DIR, "..", "withMext", "irom.coe")
COE_OUT = os.path.join(DIR, "irom.coe")
BIN_OUT = os.path.join(DIR, "irom.bin")
B_ENC = {
    'rol':0x606293b3,'ror':0x6062d3b3,'rori':0x6052d393,
    'max':0x0a62e3b3,'maxu':0x0a62f3b3,'min':0x0a62c3b3,'minu':0x0a62d3b3,
    'xperm8':0x2862c3b3,
}
TESTS = [
    ("rol","rrr",[(1,1,2),(0x12345678,4,0x23456781),(0x80000000,1,1),(0,8,0)]),
    ("ror","rrr",[(0x12345678,4,0x81234567),(0x80000000,1,0x40000000),(1,1,0x80000000),(0,8,0)]),
    ("rori","rri",[(0x12345678,4,0x81234567),(0x80000000,1,0x40000000),(1,1,0x80000000)]),
    ("max","rrr",[(0xFFFFFFFF,0,0),(5,10,10),((-10)&0xFFFFFFFF,(-5)&0xFFFFFFFF,(-5)&0xFFFFFFFF)]),
    ("maxu","rrr",[(5,10,10),(0xFFFFFFFF,0,0xFFFFFFFF),(0,5,5)]),
    ("min","rrr",[(0xFFFFFFFF,0,0xFFFFFFFF),(5,10,5),((-10)&0xFFFFFFFF,(-5)&0xFFFFFFFF,(-10)&0xFFFFFFFF)]),
    ("minu","rrr",[(5,10,5),(0xFFFFFFFF,0,0),(0,5,0)]),
    ("xperm8","rrr",[(0,0,0),(0xFEDCBA98,0x76543210,0xFEDCBA98)]),
]
build(COE_IN, COE_OUT, BIN_OUT, B_ENC, TESTS, 45)
