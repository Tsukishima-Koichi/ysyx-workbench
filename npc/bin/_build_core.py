"""Shared build logic for B-extension test COE generators."""
import struct, os

def rtype(op,rd,f3,rs1,rs2,f7):
    return ((f7&0x7F)<<25)|((rs2&0x1F)<<20)|((rs1&0x1F)<<15)|((f3&7)<<12)|((rd&0x1F)<<7)|(op&0x7F)
def itype(op,rd,f3,rs1,imm12):
    return ((imm12&0xFFF)<<20)|((rs1&0x1F)<<15)|((f3&7)<<12)|((rd&0x1F)<<7)|(op&0x7F)
def stype(op,f3,rs1,rs2,imm12):
    imm=imm12&0xFFF; return ((imm>>5)<<25)|((rs2&0x1F)<<20)|((rs1&0x1F)<<15)|((f3&7)<<12)|((imm&0x1F)<<7)|(op&0x7F)
def btype(op,f3,rs1,rs2,imm13):
    imm=imm13&0x1FFF; return (((imm>>12)&1)<<31)|(((imm>>5)&0x3F)<<25)|((rs2&0x1F)<<20)|((rs1&0x1F)<<15)|((f3&7)<<12)|(((imm>>1)&0xF)<<8)|(((imm>>11)&1)<<7)|(op&0x7F)
def jtype(op,rd,imm21):
    imm=imm21&0x1FFFFF; return ((imm>>20)<<31)|(((imm>>1)&0x3FF)<<21)|(((imm>>11)&1)<<20)|(((imm>>12)&0xFF)<<12)|((rd&0x1F)<<7)|(op&0x7F)
def utype(op,rd,imm20):
    return ((imm20&0xFFFFF)<<12)|((rd&0x1F)<<7)|(op&0x7F)

def lui(rd,imm): return utype(0x37,rd,imm)
def addi(rd,rs1,imm): return itype(0x13,rd,0,rs1,imm)
def lw(rd,rs1,off): return itype(0x03,rd,2,rs1,off)
def sw(rs2,rs1,off): return stype(0x23,2,rs1,rs2,off)
def jal(rd,off): return jtype(0x6F,rd,off)
def bne(rs1,rs2,off): return btype(0x63,1,rs1,rs2,off)
def ret(): return itype(0x67,0,0,1,0)

R={'t0':5,'t1':6,'t2':7,'t3':28,'sp':2,'ra':1,'zero':0}

def li(rd,val):
    val=val&0xFFFFFFFF
    if val==0: return [addi(R[rd],0,0)]
    if val<0x80000000: sval=val
    else: sval=val-0x100000000
    if -2048<=sval and sval<2048: return [addi(R[rd],0,val&0xFFF)]
    lo=val&0xFFF; hi=(val>>12)&0xFFFFF
    if lo&0x800: hi=(hi+1)&0xFFFFF
    ins=[lui(R[rd],hi)]
    if lo!=0: ins.append(addi(R[rd],R[rd],lo))
    return ins

def make_test_func(name, fmt, cases, B_ENC):
    ins=[]
    ins.append(addi(R['sp'],R['sp'],-16&0xFFF)); ins.append(sw(R['ra'],R['sp'],12))
    test_start=len(ins)
    for a,b,exp in cases:
        ins.extend(li('t0',a))
        if fmt=='rrr': ins.extend(li('t1',b)); ins.append(B_ENC[name])
        elif fmt=='rri':
            base=B_ENC[name]; ins.append((base&~(0x1F<<20))|((b&0x1F)<<20))
        else: ins.append(B_ENC[name])
        ins.extend(li('t3',exp)); ins.append(bne(R['t2'],R['t3'],0))
    pass_start=len(ins)
    ins.append(lui(R['t0'],0x80100)); ins.append(lw(R['t1'],R['t0'],0))
    ins.append(addi(R['t1'],R['t1'],1)); ins.append(sw(R['t1'],R['t0'],0))
    ins.append(lw(R['ra'],R['sp'],12)); ins.append(addi(R['sp'],R['sp'],16))
    ins.append(ret())
    fail_start=len(ins)
    ins.append(lui(R['t0'],0x80100)); ins.append(lw(R['t1'],R['t0'],4))
    ins.append(addi(R['t1'],R['t1'],1)); ins.append(sw(R['t1'],R['t0'],4))
    ins.append(lw(R['ra'],R['sp'],12)); ins.append(addi(R['sp'],R['sp'],16))
    ins.append(ret())
    for i in range(test_start,pass_start):
        if ins[i]&0x7F==0x63:
            off=(fail_start-i)*4
            ins[i]=(ins[i]&0x01FFF07F)|(((off>>12)&1)<<31)|(((off>>11)&1)<<7)|(((off>>5)&0x3F)<<25)|(((off>>1)&0xF)<<8)
    return ins

def build(COE_IN, COE_OUT, BIN_OUT, B_ENC, TESTS, EXPECT):
    with open(COE_IN) as f: lines=f.readlines()
    hex_data=[]
    for l in lines:
        l=l.strip().rstrip(',')
        if l.startswith('memory') or l=='' or ';' in l: continue
        hex_data.append(int(l,16))
    print(f"  Original: {len(hex_data)} instructions")

    b_disp = len(hex_data) * 4
    hex_data[0x10//4] = jal(R['ra'], (b_disp - 0x10) & 0x1FFFFF)

    li_enc = addi(15, 0, EXPECT & 0xFFF) if EXPECT < 2048 else None
    for i,w in enumerate(hex_data):
        if w == 0x02500793:
            hex_data[i] = 0x02500793 ^ (37 ^ EXPECT)  # patch: li a5, EXPECT
            # Actually: li a5, 37 = 0x02500793. li a5, N = (N&0xFFF)<<20 | 0x793
            hex_data[i] = ((EXPECT & 0xFFF) << 20) | 0x00000793
            print(f"  li a5,37->{EXPECT} at 0x{i*4:04X}")
            break

    new_code = []
    new_code.append(addi(R['sp'],R['sp'],-16&0xFFF))
    new_code.append(sw(R['ra'],R['sp'],12))
    func_addrs = {}
    cur = b_disp + (2 + len(TESTS) + 4) * 4
    all_funcs = []
    for name,fmt,cases in TESTS:
        f = make_test_func(name,fmt,cases, B_ENC)
        func_addrs[name] = cur; cur += len(f)*4
        all_funcs.append((name,f))
    for name,_ in all_funcs:
        new_code.append(jal(R['ra'],(func_addrs[name]-(b_disp+len(new_code)*4))&0x1FFFFF))
    new_code.append(lw(R['ra'],R['sp'],12))
    new_code.append(addi(R['sp'],R['sp'],16))
    new_code.append(jal(R['ra'], (0xe4 - (b_disp + len(new_code)*4)) & 0x1FFFFF))
    new_code.append(jal(R['zero'],0))
    for _,f in all_funcs: new_code.extend(f)
    hex_data.extend(new_code)
    print(f"  Appended {len(new_code)}, total {len(hex_data)}")

    with open(COE_OUT,'w') as f:
        f.write('memory_initialization_radix=16;\nmemory_initialization_vector=\n')
        for w in hex_data: f.write(f'{w:08X},\n')
        f.seek(f.tell()-2); f.truncate(); f.write(';\n')
    with open(BIN_OUT,'wb') as f:
        for w in hex_data: f.write(struct.pack('<I',w))
    print(f"  -> {os.path.basename(BIN_OUT)} ({len(hex_data)*4} bytes)")
