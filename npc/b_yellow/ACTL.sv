`timescale 1ns / 1ps
`include "defines.sv"

module ACTL(
    input  logic [6:0] opcode,
    input  logic [2:0] funct3,
    input  logic [6:0] funct7,
    input  logic [4:0] shamt,         // inst[24:20], 区分 clz/ctz/cpop
    output logic [3:0] alu_ctrl       // 4bit: 0-9基类, 10-13 yellow
);
    wire is_R = (opcode === `R_TYPE);
    wire is_I = (opcode === `I_TYPE);
    wire use_funct3 = is_R | is_I;

    wire is_sub = is_R & (funct3 === 3'b000) & (funct7[5] === 1'b1);
    wire is_sra = use_funct3 & (funct3 === 3'b101) & (funct7[5] === 1'b1);

    // ★ 并行检测 yellow 指令 (4条, 纯组合)
    wire is_clz    = is_I & (funct3 === 3'b001) & (funct7 === 7'b0110000) & (shamt === 5'b00000);
    wire is_ctz    = is_I & (funct3 === 3'b001) & (funct7 === 7'b0110000) & (shamt === 5'b00001);
    wire is_cpop   = is_I & (funct3 === 3'b001) & (funct7 === 7'b0110000) & (shamt === 5'b00010);
    wire is_xperm4 = is_R & (funct3 === 3'b010) & (funct7 === 7'b0010100);

    wire is_new = is_clz | is_ctz | is_cpop | is_xperm4;

    // 基类编码 (同 fastest)
    wire [3:0] base_ctrl;
    assign base_ctrl[3] = use_funct3 & (funct3[2] & funct3[1]);
    assign base_ctrl[2] = use_funct3 & ( (funct3 === 3'b011) | (funct3[2] & ~funct3[1]) );
    assign base_ctrl[1] = use_funct3 & ( (funct3 === 3'b001) | (funct3 === 3'b010) | (funct3 === 3'b101) );
    assign base_ctrl[0] = use_funct3 & ( is_sub | (funct3 === 3'b010) | (funct3 === 3'b100) | is_sra | (funct3 === 3'b111) );

    // ★ 扩展编码 (每 bit 宽 OR)
    // 10=CLZ(1010) 11=CTZ(1011) 12=CPOP(1100) 13=XPERM4(1101)
    wire [3:0] new_ctrl;
    assign new_ctrl[3] = 1'b1;  // 10-13 的 bit3 均为 1
    assign new_ctrl[2] = is_cpop | is_xperm4;
    assign new_ctrl[1] = is_clz  | is_ctz;
    assign new_ctrl[0] = is_ctz  | is_xperm4;

    assign alu_ctrl = is_new ? new_ctrl : base_ctrl;

endmodule
