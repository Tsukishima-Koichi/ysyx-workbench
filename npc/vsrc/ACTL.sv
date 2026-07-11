`timescale 1ns / 1ps
`include "defines.sv"

module ACTL(
    input  logic [6:0] opcode,
    input  logic [2:0] funct3,
    input  logic [6:0] funct7,
    output logic [3:0] alu_ctrl
);
    // --------------------------------------------------------
    // 1. 提取基础标志位 (纯并行比较)
    // --------------------------------------------------------
    wire is_R = (opcode === `R_TYPE);
    wire is_I = (opcode === `I_TYPE);
    
    // 只有 R型 和 I型运算指令才需要解析 funct3 来决定 ALU 操作
    wire use_funct3 = is_R | is_I;

    // --------------------------------------------------------
    // 2. 提取特殊运算标志 (依赖 funct7[5] 进行区分)
    // --------------------------------------------------------
    // SUB (减法): 只有 R型指令，且 funct3=000，且 funct7[5]=1 时才触发
    wire is_sub = is_R & (funct3 === 3'b000) & (funct7[5] === 1'b1);
    
    // SRA/SRAI (算术右移): R型或I型，且 funct3=101，且 funct7[5]=1 时触发
    wire is_sra = use_funct3 & (funct3 === 3'b101) & (funct7[5] === 1'b1);

    // --------------------------------------------------------
    // 3. 并行输出各比特位 (布尔代数方程)
    // --------------------------------------------------------
    // Bit 3: 命中 OR(1000) 或 AND(1001) -> 对应 funct3 为 110, 111
    assign alu_ctrl[3] = use_funct3 & (funct3[2] & funct3[1]);

    // Bit 2: 命中 SLTU(0100), XOR(0101), SRL(0110), SRA(0111) -> 对应 funct3 为 011, 100, 101
    assign alu_ctrl[2] = use_funct3 & ( (funct3 === 3'b011) | (funct3[2] & ~funct3[1]) );

    // Bit 1: 命中 SLL(0010), SLT(0011), SRL(0110), SRA(0111) -> 对应 funct3 为 001, 010, 101
    assign alu_ctrl[1] = use_funct3 & ( (funct3 === 3'b001) | (funct3 === 3'b010) | (funct3 === 3'b101) );

    // Bit 0: 命中 SUB(0001), SLT(0011), XOR(0101), SRA(0111), AND(1001)
    assign alu_ctrl[0] = use_funct3 & ( is_sub | (funct3 === 3'b010) | (funct3 === 3'b100) | is_sra | (funct3 === 3'b111) );

endmodule
