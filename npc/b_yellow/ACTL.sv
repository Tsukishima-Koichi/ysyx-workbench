`timescale 1ns / 1ps
`include "defines.sv"

module ACTL(
    input  logic [6:0] opcode,
    input  logic [2:0] funct3,
    input  logic [6:0] funct7,
    input  logic [4:0] shamt,     // inst[24:20], 用于区分 Zbb 指令
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
    // 2.5 Zbb/Zbkx 指令检测 (纯并行比较, 不影响原有路径)
    // --------------------------------------------------------
    // CLZ:  I-type, funct3=001, funct7=0110000, shamt=00000
    // CTZ:  I-type, funct3=001, funct7=0110000, shamt=00001
    // CPOP: I-type, funct3=001, funct7=0110000, shamt=00010
    // XPERM4: R-type, funct3=010, funct7=0010100
    wire is_zbb_f7   = (funct7 === 7'b0110000);
    wire is_clz      = is_I & (funct3 === 3'b001) & is_zbb_f7 & (shamt === 5'b00000);
    wire is_ctz      = is_I & (funct3 === 3'b001) & is_zbb_f7 & (shamt === 5'b00001);
    wire is_cpop     = is_I & (funct3 === 3'b001) & is_zbb_f7 & (shamt === 5'b00010);
    wire is_xperm4   = is_R & (funct3 === 3'b010) & (funct7 === 7'b0010100);
    wire is_bitmanip = is_clz | is_ctz | is_cpop | is_xperm4;

    // --------------------------------------------------------
    // 3. 并行输出各比特位 (布尔代数方程)
    //    base 沿用原有逻辑, 遇 bitmanip 指令时由 override 接管
    // --------------------------------------------------------
    wire [3:0] alu_ctrl_base;
    // Bit 3: 命中 OR(1000) 或 AND(1001) -> 对应 funct3 为 110, 111
    assign alu_ctrl_base[3] = use_funct3 & (funct3[2] & funct3[1]);

    // Bit 2: 命中 SLTU(0100), XOR(0101), SRL(0110), SRA(0111) -> 对应 funct3 为 011, 100, 101
    assign alu_ctrl_base[2] = use_funct3 & ( (funct3 === 3'b011) | (funct3[2] & ~funct3[1]) );

    // Bit 1: 命中 SLL(0010), SLT(0011), SRL(0110), SRA(0111) -> 对应 funct3 为 001, 010, 101
    assign alu_ctrl_base[1] = use_funct3 & ( (funct3 === 3'b001) | (funct3 === 3'b010) | (funct3 === 3'b101) );

    // Bit 0: 命中 SUB(0001), SLT(0011), XOR(0101), SRA(0111), AND(1001)
    assign alu_ctrl_base[0] = use_funct3 & ( is_sub | (funct3 === 3'b010) | (funct3 === 3'b100) | is_sra | (funct3 === 3'b111) );

    // --------------------------------------------------------
    // 3.5 override 编码 (纯并行, 无优先级链):
    //     CLZ  = 10 (1010),  CTZ  = 11 (1011)
    //     CPOP = 12 (1100),  XPERM4 = 13 (1101)
    // --------------------------------------------------------
    wire [3:0] alu_ctrl_ov;
    assign alu_ctrl_ov[3] = 1'b1;                          // 10~13 的 bit3 均为 1
    assign alu_ctrl_ov[2] = is_cpop | is_xperm4;           // 12(1100), 13(1101)
    assign alu_ctrl_ov[1] = is_clz  | is_ctz;              // 10(1010), 11(1011)
    assign alu_ctrl_ov[0] = is_ctz  | is_xperm4;           // 11(1011), 13(1101)

    // 最终输出: 仅一层 2:1 mux, 对时序几乎零影响
    assign alu_ctrl = is_bitmanip ? alu_ctrl_ov : alu_ctrl_base;

endmodule
