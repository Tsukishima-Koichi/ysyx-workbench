`timescale 1ns / 1ps
`include "defines.sv"

module ACTL(
    input  logic [6:0] opcode,
    input  logic [2:0] funct3,
    input  logic [6:0] funct7,
    output logic [4:0] alu_ctrl
);
    // --------------------------------------------------------
    // 1. 提取基础标志位 (纯并行比较)
    // --------------------------------------------------------
    wire is_R = (opcode === `R_TYPE);
    wire is_I = (opcode === `I_TYPE);

    // 只有 R型 和 I型运算指令才需要解析 funct3 来决定 ALU 操作
    wire use_funct3 = is_R | is_I;

    // --------------------------------------------------------
    // 2. 新增指令检测 (funct7 特异值，优先级高于旧解码)
    // --------------------------------------------------------
    wire is_rol    = is_R & (funct3 === 3'b001) & (funct7 === 7'b0110000);
    wire is_ror    = is_R & (funct3 === 3'b101) & (funct7 === 7'b0110000);
    wire is_rori   = is_I & (funct3 === 3'b101) & (funct7 === 7'b0110000);
    wire is_min    = is_R & (funct3 === 3'b100) & (funct7 === 7'b0000101);
    wire is_max    = is_R & (funct3 === 3'b110) & (funct7 === 7'b0000101);
    wire is_minu   = is_R & (funct3 === 3'b101) & (funct7 === 7'b0000101);
    wire is_maxu   = is_R & (funct3 === 3'b111) & (funct7 === 7'b0000101);
    wire is_zip    = is_R & (funct3 === 3'b001) & (funct7 === 7'b0000100);
    wire is_unzip  = is_R & (funct3 === 3'b101) & (funct7 === 7'b0000100);
    wire is_xperm8 = is_R & (funct3 === 3'b100) & (funct7 === 7'b0010100);
    wire is_new    = is_rol | is_ror | is_rori | is_min | is_max | is_minu | is_maxu
                   | is_zip | is_unzip | is_xperm8;

    // --------------------------------------------------------
    // 3. 抽取旧版特殊运算标志 (排除被新指令占用的冲突编码)
    // --------------------------------------------------------
    // SUB: 只有 R型指令，且 funct3=000，且 funct7[5]=1 时才触发
    wire is_sub = is_R & (funct3 === 3'b000) & (funct7[5] === 1'b1);

    // SRA/SRAI: R型或I型，且 funct3=101，且 funct7[5]=1
    // 但要排除 ROR(funct7=0110000)、RORI(funct7=0110000)、MINU(funct7=0000101)、UNZIP(funct7=0000100)
    wire is_sra = use_funct3 & (funct3 === 3'b101) & (funct7[5] === 1'b1)
                & ~is_ror & ~is_rori & ~is_minu & ~is_unzip;

    // --------------------------------------------------------
    // 4. 旧版 alu_ctrl 低位并行计算 (按原有公式，不引入 is_new 额外门延迟)
    // --------------------------------------------------------
    wire [4:0] legacy_ctrl;
    assign legacy_ctrl[4] = 1'b0;
    assign legacy_ctrl[3] = use_funct3 & (funct3[2] & funct3[1]);
    assign legacy_ctrl[2] = use_funct3 & ( (funct3 === 3'b011) | (funct3[2] & ~funct3[1]) );
    assign legacy_ctrl[1] = use_funct3 & ( (funct3 === 3'b001) | (funct3 === 3'b010) | (funct3 === 3'b101) );
    assign legacy_ctrl[0] = use_funct3 & ( is_sub | (funct3 === 3'b010) | (funct3 === 3'b100)
                                         | is_sra | (funct3 === 3'b111) );

    // --------------------------------------------------------
    // 5. 新指令编码 (5-bit 优先编码)
    // --------------------------------------------------------
    wire [4:0] new_ctrl;
    assign new_ctrl = is_rol    ? 5'd10 :
                      is_ror    ? 5'd11 :
                      is_rori   ? 5'd11 :
                      is_min    ? 5'd12 :
                      is_max    ? 5'd13 :
                      is_minu   ? 5'd14 :
                      is_maxu   ? 5'd15 :
                      is_zip    ? 5'd16 :
                      is_unzip  ? 5'd17 :
                      is_xperm8 ? 5'd18 :
                      5'd0;

    // --------------------------------------------------------
    // 6. 最终输出：新指令优先，否则沿用旧版
    //    (旧版对新指令的"误解码"值被 MUX 屏蔽，不影响下游)
    // --------------------------------------------------------
    assign alu_ctrl = is_new ? new_ctrl : legacy_ctrl;

endmodule
