/***************************************************************************************
* Copyright (c) 2014-2024 Zihao Yu, Nanjing University
*
* NEMU is licensed under Mulan PSL v2.
* You can use this software according to the terms and conditions of the Mulan PSL v2.
* You may obtain a copy of Mulan PSL v2 at:
*          http://license.coscl.org.cn/MulanPSL2
*
* THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
* EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
* MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
*
* See the Mulan PSL v2 for more details.
***************************************************************************************/

#include "local-include/reg.h"
#include <cpu/cpu.h>
#include <cpu/ifetch.h>
#include <cpu/decode.h>

#define R(i) gpr(i)
#define Mr vaddr_read
#define Mw vaddr_write

enum {
  TYPE_I, TYPE_U, TYPE_S,
  TYPE_N, // none
  TYPE_J,
  TYPE_R,
  TYPE_B,
};

#define src1R() do { *src1 = R(rs1); } while (0)
#define src2R() do { *src2 = R(rs2); } while (0)
#define immI() do { *imm = SEXT(BITS(i, 31, 20), 12); } while(0)
#define immU() do { *imm = SEXT(BITS(i, 31, 12), 20) << 12; } while(0)
#define immS() do { *imm = (SEXT(BITS(i, 31, 25), 7) << 5) | BITS(i, 11, 7); } while(0)
#define immJ() do { *imm = (SEXT(BITS(i, 31, 31), 1) << 20) | (BITS(i, 19, 12) << 12) | (BITS(i, 20, 20) << 11) | (BITS(i, 30, 21) << 1); } while(0)
#define immB() do { *imm = (SEXT(BITS(i, 31, 31), 1) << 12) | (BITS(i, 7, 7) << 11) | (BITS(i, 30, 25) << 5) | (BITS(i, 11, 8) << 1); } while(0)

static void decode_operand(Decode *s, int *rd, word_t *src1, word_t *src2, word_t *imm, int type) {
  uint32_t i = s->isa.inst;
  int rs1 = BITS(i, 19, 15);
  int rs2 = BITS(i, 24, 20);
  *rd     = BITS(i, 11, 7);
  switch (type) {
    case TYPE_I: src1R();          immI(); break;
    case TYPE_U:                   immU(); break;
    case TYPE_S: src1R(); src2R(); immS(); break;
    case TYPE_N: break;
    case TYPE_J:                   immJ(); break;
    case TYPE_R: src1R(); src2R();         break;
    case TYPE_B: src1R(); src2R(); immB(); break;
    default: panic("unsupported type = %d", type);
  }
}

static int decode_exec(Decode *s) {
  s->dnpc = s->snpc;

#define INSTPAT_INST(s) ((s)->isa.inst)
#define INSTPAT_MATCH(s, name, type, ... /* execute body */ ) { \
  int rd = 0; \
  word_t src1 = 0, src2 = 0, imm = 0; \
  decode_operand(s, &rd, &src1, &src2, &imm, concat(TYPE_, type)); \
  __VA_ARGS__ ; \
}

  INSTPAT_START();

  // ================= U 型指令 (高位立即数) =================
  // lui: 加载高位立即数。将 imm 写入 rd
  INSTPAT("??????? ????? ????? ??? ????? 01101 11", lui    , U, R(rd) = imm);
  // auipc: PC 加高位立即数。PC + imm 写入 rd
  INSTPAT("??????? ????? ????? ??? ????? 00101 11", auipc  , U, R(rd) = s->pc + imm);

  // ================= J/I 型指令 (无条件跳转) =================
  // jal: 跳转并链接 (J型)。跳到 pc+imm，rd 存入返回地址 pc+4
  INSTPAT("??????? ????? ????? ??? ????? 11011 11", jal    , J, R(rd) = s->pc + 4; s->dnpc = s->pc + imm);
  // jalr: 寄存器跳转并链接 (I型)。跳到 src1+imm (最低位清零)，rd 存入返回地址 pc+4
  INSTPAT("??????? ????? ????? 000 ????? 11001 11", jalr   , I, R(rd) = s->pc + 4; s->dnpc = (src1 + imm) & ~1);

  // ================= B 型指令 (条件分支) =================
  // beq: 相等则跳转
  INSTPAT("??????? ????? ????? 000 ????? 11000 11", beq    , B, s->dnpc = (src1 == src2) ? (s->pc + imm) : s->snpc);
  // bne: 不等则跳转
  INSTPAT("??????? ????? ????? 001 ????? 11000 11", bne    , B, s->dnpc = (src1 != src2) ? (s->pc + imm) : s->snpc);
  // blt: 有符号小于则跳转 (必须强转为 signed)
  INSTPAT("??????? ????? ????? 100 ????? 11000 11", blt    , B, s->dnpc = ((sword_t)src1 < (sword_t)src2) ? (s->pc + imm) : s->snpc);
  // bge: 有符号大于等于则跳转
  INSTPAT("??????? ????? ????? 101 ????? 11000 11", bge    , B, s->dnpc = ((sword_t)src1 >= (sword_t)src2) ? (s->pc + imm) : s->snpc);
  // bltu: 无符号小于则跳转 (默认就是 unsigned，直接比)
  INSTPAT("??????? ????? ????? 110 ????? 11000 11", bltu   , B, s->dnpc = (src1 < src2) ? (s->pc + imm) : s->snpc);
  // bgeu: 无符号大于等于则跳转
  INSTPAT("??????? ????? ????? 111 ????? 11000 11", bgeu   , B, s->dnpc = (src1 >= src2) ? (s->pc + imm) : s->snpc);

  // ================= Load 指令 (I 型 - 内存读取) =================
  // lb: 读 1 字节，并进行有符号扩展到 32 位
  INSTPAT("??????? ????? ????? 000 ????? 00000 11", lb     , I, R(rd) = (sword_t)(int8_t)Mr(src1 + imm, 1));
  // lh: 读 2 字节，并进行有符号扩展到 32 位
  INSTPAT("??????? ????? ????? 001 ????? 00000 11", lh     , I, R(rd) = (sword_t)(int16_t)Mr(src1 + imm, 2));
  // lw: 读 4 字节
  INSTPAT("??????? ????? ????? 010 ????? 00000 11", lw     , I, R(rd) = Mr(src1 + imm, 4));
  // lbu: 读 1 字节，无符号扩展 (高位补 0)
  INSTPAT("??????? ????? ????? 100 ????? 00000 11", lbu    , I, R(rd) = Mr(src1 + imm, 1));
  // lhu: 读 2 字节，无符号扩展 (高位补 0)
  INSTPAT("??????? ????? ????? 101 ????? 00000 11", lhu    , I, R(rd) = Mr(src1 + imm, 2));

  // ================= Store 指令 (S 型 - 内存写入) =================
  // sb: 存 1 字节 (最低 8 位)
  INSTPAT("??????? ????? ????? 000 ????? 01000 11", sb     , S, Mw(src1 + imm, 1, src2));
  // sh: 存 2 字节 (最低 16 位)
  INSTPAT("??????? ????? ????? 001 ????? 01000 11", sh     , S, Mw(src1 + imm, 2, src2));
  // sw: 存 4 字节 (32 位)
  INSTPAT("??????? ????? ????? 010 ????? 01000 11", sw     , S, Mw(src1 + imm, 4, src2));

  // ================= ALU 立即数指令 (I 型 - 算术/逻辑) =================
  // addi: 加立即数
  INSTPAT("??????? ????? ????? 000 ????? 00100 11", addi   , I, R(rd) = src1 + imm);
  // slti: 有符号小于立即数置 1 (比较前强制转有符号)
  INSTPAT("??????? ????? ????? 010 ????? 00100 11", slti   , I, R(rd) = ((sword_t)src1 < (sword_t)imm) ? 1 : 0);
  // sltiu: 无符号小于立即数置 1
  INSTPAT("??????? ????? ????? 011 ????? 00100 11", sltiu  , I, R(rd) = (src1 < imm) ? 1 : 0);
  // xori: 异或立即数
  INSTPAT("??????? ????? ????? 100 ????? 00100 11", xori   , I, R(rd) = src1 ^ imm);
  // ori: 或立即数
  INSTPAT("??????? ????? ????? 110 ????? 00100 11", ori    , I, R(rd) = src1 | imm);
  // andi: 与立即数
  INSTPAT("??????? ????? ????? 111 ????? 00100 11", andi   , I, R(rd) = src1 & imm);
  // slli: 逻辑左移 (位移量取 imm 的低 5 位)
  INSTPAT("0000000 ????? ????? 001 ????? 00100 11", slli   , I, R(rd) = src1 << (imm & 0x1F));
  // srli: 逻辑右移 (高位补 0)
  INSTPAT("0000000 ????? ????? 101 ????? 00100 11", srli   , I, R(rd) = src1 >> (imm & 0x1F));
  // srai: 算术右移 (高位补符号位，必须强制转有符号再移位)
  INSTPAT("0100000 ????? ????? 101 ????? 00100 11", srai   , I, R(rd) = (sword_t)src1 >> (imm & 0x1F));

  // ================= ALU 寄存器指令 (R 型 - 算术/逻辑) =================
  // add: 寄存器加法
  INSTPAT("0000000 ????? ????? 000 ????? 01100 11", add    , R, R(rd) = src1 + src2);
  // sub: 寄存器减法
  INSTPAT("0100000 ????? ????? 000 ????? 01100 11", sub    , R, R(rd) = src1 - src2);
  // sll: 逻辑左移 (位移量取 src2 的低 5 位)
  INSTPAT("0000000 ????? ????? 001 ????? 01100 11", sll    , R, R(rd) = src1 << (src2 & 0x1F));
  // slt: 有符号小于置 1
  INSTPAT("0000000 ????? ????? 010 ????? 01100 11", slt    , R, R(rd) = ((sword_t)src1 < (sword_t)src2) ? 1 : 0);
  // sltu: 无符号小于置 1
  INSTPAT("0000000 ????? ????? 011 ????? 01100 11", sltu   , R, R(rd) = (src1 < src2) ? 1 : 0);
  // xor: 异或
  INSTPAT("0000000 ????? ????? 100 ????? 01100 11", xor    , R, R(rd) = src1 ^ src2);
  // srl: 逻辑右移
  INSTPAT("0000000 ????? ????? 101 ????? 01100 11", srl    , R, R(rd) = src1 >> (src2 & 0x1F));
  // sra: 算术右移 (高位补符号位)
  INSTPAT("0100000 ????? ????? 101 ????? 01100 11", sra    , R, R(rd) = (sword_t)src1 >> (src2 & 0x1F));
  // or: 或
  INSTPAT("0000000 ????? ????? 110 ????? 01100 11", or     , R, R(rd) = src1 | src2);
  // and: 与
  INSTPAT("0000000 ????? ????? 111 ????? 01100 11", and    , R, R(rd) = src1 & src2);

  // ================= M 扩展指令 (R 型 - 乘除法) =================
  // funct7 固定为 0000001，opcode 为 0110011

  // mul: 乘法 (保留低 32 位，无论有无符号底层位运算结果一样)
  INSTPAT("0000001 ????? ????? 000 ????? 01100 11", mul    , R, R(rd) = src1 * src2);
  // mulh: 有符号乘法 (取高 32 位，必须强转 64 位 signed)
  INSTPAT("0000001 ????? ????? 001 ????? 01100 11", mulh   , R, R(rd) = ((int64_t)(sword_t)src1 * (int64_t)(sword_t)src2) >> 32);
  // mulhu: 无符号乘法 (取高 32 位，必须强转 64 位 unsigned)
  INSTPAT("0000001 ????? ????? 011 ????? 01100 11", mulhu  , R, R(rd) = ((uint64_t)src1 * (uint64_t)src2) >> 32);
  // mulhsu: 有符号乘无符号 (取高 32 位)
  INSTPAT("0000001 ????? ????? 010 ????? 01100 11", mulhsu , R, R(rd) = ((int64_t)(sword_t)src1 * (uint64_t)src2) >> 32);

  // div: 有符号除法 (包含除零和溢出防御)
  INSTPAT("0000001 ????? ????? 100 ????? 01100 11", div    , R, R(rd) = (src2 == 0) ? 0xffffffff : ((src1 == 0x80000000 && src2 == 0xffffffff) ? src1 : ((sword_t)src1 / (sword_t)src2)));
  // divu: 无符号除法 (包含除零防御)
  INSTPAT("0000001 ????? ????? 101 ????? 01100 11", divu   , R, R(rd) = (src2 == 0) ? 0xffffffff : (src1 / src2));
  
  // rem: 有符号取模 (包含除零和溢出防御)
  INSTPAT("0000001 ????? ????? 110 ????? 01100 11", rem    , R, R(rd) = (src2 == 0) ? src1 : ((src1 == 0x80000000 && src2 == 0xffffffff) ? 0 : ((sword_t)src1 % (sword_t)src2)));
  // remu: 无符号取模 (包含除零防御)
  INSTPAT("0000001 ????? ????? 111 ????? 01100 11", remu   , R, R(rd) = (src2 == 0) ? src1 : (src1 % src2));

  // ================= Zicsr 扩展指令 (系统/特权) =================
  
  // csrrw (CSR Read/Write): 把 CSR 的旧值读入 rd，把 src1 写进 CSR
  INSTPAT("??????? ????? ????? 001 ????? 11100 11", csrrw  , I, word_t csr = BITS(s->isa.inst, 31, 20); word_t t = csr_read(csr); csr_write(csr, src1); R(rd) = t);
  
  // csrrs (CSR Read and Set): 把 CSR 的旧值读入 rd，然后把 CSR 原来的值和 src1 按位或，再写回 CSR
  // (如果 rs1 = x0，那就相当于纯粹的读 CSR 操作)
  INSTPAT("??????? ????? ????? 010 ????? 11100 11", csrrs  , I, word_t csr = BITS(s->isa.inst, 31, 20); word_t t = csr_read(csr); csr_write(csr, t | src1); R(rd) = t);

  // ================= 系统异常返回指令 =================

  // mret (Machine-mode Trap Return)
  INSTPAT("0011000 00010 00000 000 00000 11100 11", mret, I, \
    word_t mstatus = cpu.csr.mstatus; \
    word_t mpie = (mstatus >> 7) & 1; \
    // 1. MIE = MPIE (恢复中断使能)
    mstatus = (mstatus & ~(1 << 3)) | (mpie << 3); \
    // 2. MPIE = 1 (规范要求返回后 MPIE 置 1)
    mstatus |= (1 << 7); \
    // 3. 【最关键的一步】MPP = 0 (返回后特权级改为 U-mode，或清空备份)
    mstatus &= ~(3 << 11); \
    \
    cpu.csr.mstatus = mstatus; \
    /* 【etrace 新增】记录退出异常的踪迹 */ \
    /* 注意这里用了 IFDEF 宏来避免没开启 ETRACE 时报变量未使用的警告 */ \
    IFDEF(CONFIG_ETRACE, Log("🔙 [etrace] Trap Return: PC = " FMT_WORD ", Jump back to = " FMT_WORD, s->pc, cpu.csr.mepc)); \
    \
    s->dnpc = cpu.csr.mepc; \
  );

  // 请确保将 ecall 放在 inv (兜底的非法指令) 之前！
  INSTPAT("0000000 00000 00000 000 00000 11100 11", ecall  , N, s->dnpc = isa_raise_intr(11, s->pc));
  INSTPAT("0000000 00001 00000 000 00000 11100 11", ebreak , N, NEMUTRAP(s->pc, R(10))); // R(10) is $a0
  INSTPAT("??????? ????? ????? ??? ????? ????? ??", inv    , N, INV(s->pc));
  
  INSTPAT_END();

  R(0) = 0; // reset $zero to 0

  return 0;
}

int isa_exec_once(Decode *s) {
  s->isa.inst = inst_fetch(&s->snpc, 4);
  return decode_exec(s);
}
