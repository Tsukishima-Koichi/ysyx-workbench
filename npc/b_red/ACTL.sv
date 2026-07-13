`timescale 1ns / 1ps
`include "defines.sv"

module ACTL(
    input  logic [6:0] opcode,
    input  logic [2:0] funct3,
    input  logic [6:0] funct7,
    output logic [3:0] alu_ctrl       // 4bit: 0-9基类, 10-12 red
);
    wire is_R = (opcode === `R_TYPE);
    wire is_I = (opcode === `I_TYPE);
    wire use_funct3 = is_R | is_I;

    wire is_sub = is_R & (funct3 === 3'b000) & (funct7[5] === 1'b1);
    wire is_sra = use_funct3 & (funct3 === 3'b101) & (funct7[5] === 1'b1);

    // ★ CLMUL/CLMULR/CLMULH: R-type, funct7=0000101
    wire is_clmul = is_R & (funct7 === 7'b0000101);

    // 基类编码 + is_clmul OR 入 bit3 (10-12 的 bit3=1, 与 OR/AND 的 bit3 复用)
    // 10=CLMUL(f3=001) 11=CLMULR(f3=010) 12=CLMULH(f3=011)
    // 基类编码对这3个 funct3 产生 bit1/bit0 恰好匹配, 只需 bit3 额外置 1
    assign alu_ctrl[3] = (use_funct3 & (funct3[2] & funct3[1])) | is_clmul;
    assign alu_ctrl[2] = use_funct3 & ( (funct3 === 3'b011) | (funct3[2] & ~funct3[1]) );
    assign alu_ctrl[1] = use_funct3 & ( (funct3 === 3'b001) | (funct3 === 3'b010) | (funct3 === 3'b101) );
    assign alu_ctrl[0] = use_funct3 & ( is_sub | (funct3 === 3'b010) | (funct3 === 3'b100) | is_sra | (funct3 === 3'b111) );

endmodule
