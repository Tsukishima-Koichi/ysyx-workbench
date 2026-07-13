`timescale 1ns / 1ps
`include "defines.sv"

module ACTL(
    input  logic [6:0] opcode,
    input  logic [2:0] funct3,
    input  logic [6:0] funct7,
    input  logic [4:0] shamt,         // inst[24:20], Zbb/Zbkb 子指令区分
    output logic [4:0] alu_ctrl       // ★ 5bit: 0-9基类, 10-26扩展
);
    // ================================================================
    // 1. 基础标志 (纯并行比较)
    // ================================================================
    wire is_R = (opcode === `R_TYPE);
    wire is_I = (opcode === `I_TYPE);
    wire use_funct3 = is_R | is_I;

    // ================================================================
    // 2. 基类特殊运算标志 (同 fastest, 纯并行)
    // ================================================================
    wire is_sub = is_R & (funct3 === 3'b000) & (funct7[5] === 1'b1);
    wire is_sra = use_funct3 & (funct3 === 3'b101) & (funct7[5] === 1'b1);

    // ================================================================
    // 3. ★ 扩展指令逐条检测 (17条并行 wire, 零优先级链)
    // ================================================================
    // Zba: 移位加
    wire is_sh1add = is_R & (funct7 === 7'b0010000) & (funct3 === 3'b010);
    wire is_sh2add = is_R & (funct7 === 7'b0010000) & (funct3 === 3'b100);
    wire is_sh3add = is_R & (funct7 === 7'b0010000) & (funct3 === 3'b110);

    // Zbs: 单比特操作
    wire is_bset   = use_funct3 & (funct3 === 3'b001) & (funct7 === 7'b0010100);
    wire is_bclr   = use_funct3 & (funct3 === 3'b001) & (funct7 === 7'b0100100);
    wire is_binv   = use_funct3 & (funct3 === 3'b001) & (funct7 === 7'b0110100);
    wire is_bext   = use_funct3 & (funct3 === 3'b101) & (funct7 === 7'b0100100);

    // Zbb: 基础逻辑非
    wire is_andn   = is_R & (funct7 === 7'b0100000) & (funct3 === 3'b111);
    wire is_orn    = is_R & (funct7 === 7'b0100000) & (funct3 === 3'b110);
    wire is_xnor   = is_R & (funct7 === 7'b0100000) & (funct3 === 3'b100);

    // Zbb: 符号扩展 (shamt 区分)
    wire is_sext_b = is_I & (funct7 === 7'b0110000) & (funct3 === 3'b001) & (shamt === 5'b00100);
    wire is_sext_h = is_I & (funct7 === 7'b0110000) & (funct3 === 3'b001) & (shamt === 5'b00101);

    // Zbb: orc.b
    wire is_orc_b  = is_I & (funct7 === 7'b0010100) & (funct3 === 3'b101);

    // Zbkb: 字节/位反转 (shamt 区分)
    wire is_rev8   = is_I & (funct7 === 7'b0110100) & (funct3 === 3'b101) & (shamt === 5'b11000);
    wire is_brev8  = is_I & (funct7 === 7'b0110100) & (funct3 === 3'b101) & (shamt === 5'b00111);

    // Zbkb: 数据打包
    wire is_pack   = is_R & (funct7 === 7'b0000100) & (funct3 === 3'b100);
    wire is_packh  = is_R & (funct7 === 7'b0000100) & (funct3 === 3'b111);

    // 任意扩展命中 → 1位宽 OR, 单级 LUT
    wire is_any_ext = is_sh1add | is_sh2add | is_sh3add | is_bset | is_bclr | is_binv | is_bext |
                      is_andn | is_orn | is_xnor | is_sext_b | is_sext_h | is_orc_b |
                      is_rev8 | is_brev8 | is_pack | is_packh;

    // ================================================================
    // 4. 基类编码 (bits[3:0] = fastest 原版布尔方程, bit[4] = 0)
    // ================================================================
    wire [4:0] base_ctrl;
    assign base_ctrl[4] = 1'b0;
    assign base_ctrl[3] = use_funct3 & (funct3[2] & funct3[1]);
    assign base_ctrl[2] = use_funct3 & ( (funct3 === 3'b011) | (funct3[2] & ~funct3[1]) );
    assign base_ctrl[1] = use_funct3 & ( (funct3 === 3'b001) | (funct3 === 3'b010) | (funct3 === 3'b101) );
    assign base_ctrl[0] = use_funct3 & ( is_sub | (funct3 === 3'b010) | (funct3 === 3'b100) | is_sra | (funct3 === 3'b111) );

    // ================================================================
    // 5. ★ 扩展编码 (每 bit 一条纯并行方程, 17→1 宽 OR, 同 fastest 风格)
    //
    //    码表 (bit4 bit3 bit2 bit1 bit0):
    //    SH1ADD = 10 (0_1010)   BSET   = 13 (0_1101)   ANDN  = 17 (1_0001)
    //    SH2ADD = 11 (0_1011)   BCLR   = 14 (0_1110)   ORN   = 18 (1_0010)
    //    SH3ADD = 12 (0_1100)   BINV   = 15 (0_1111)   XNOR  = 19 (1_0011)
    //    BEXT   = 16 (1_0000)   SEXT.B = 20 (1_0100)   SEXT.H= 21 (1_0101)
    //    ORC.B  = 22 (1_0110)   REV8   = 23 (1_0111)   BREV8 = 24 (1_1000)
    //    PACK   = 25 (1_1001)   PACKH  = 26 (1_1010)
    // ================================================================
    wire [4:0] ext_ctrl;
    // bit4 = 1 的指令: BEXT/ANDN/ORN/XNOR/SEXT.B/SEXT.H/ORC.B/REV8/BREV8/PACK/PACKH
    assign ext_ctrl[4] = is_bext | is_andn | is_orn | is_xnor | is_sext_b | is_sext_h |
                         is_orc_b | is_rev8 | is_brev8 | is_pack | is_packh;
    // bit3 = 1 的指令: SH1ADD/SH2ADD/SH3ADD/BSET/BCLR/BINV/BREV8/PACK/PACKH
    assign ext_ctrl[3] = is_sh1add | is_sh2add | is_sh3add | is_bset | is_bclr | is_binv |
                         is_brev8 | is_pack | is_packh;
    // bit2 = 1 的指令: SH3ADD/BCLR/BINV/BEXT/ORN/SEXT.H/ORC.B/BREV8/PACK
    assign ext_ctrl[2] = is_sh3add | is_bclr | is_binv | is_bext | is_orn | is_sext_h |
                         is_orc_b | is_brev8 | is_pack;
    // bit1 = 1 的指令: SH2ADD/SH3ADD/BSET/BCLR/ANDN/XNOR/SEXT.B/REV8/PACK/PACKH
    assign ext_ctrl[1] = is_sh2add | is_sh3add | is_bset | is_bclr | is_andn | is_xnor |
                         is_sext_b | is_rev8 | is_pack | is_packh;
    // bit0 = 1 的指令: SH1ADD/SH3ADD/BSET/BINV/BEXT/ANDN/ORN/SEXT.B/SEXT.H/ORC.B/REV8/PACK
    assign ext_ctrl[0] = is_sh1add | is_sh3add | is_bset | is_binv | is_bext | is_andn |
                         is_orn | is_sext_b | is_sext_h | is_orc_b | is_rev8 | is_pack;

    // ================================================================
    // 6. 最终输出: 单层 2:1 MUX (同 fastest 逻辑深度)
    // ================================================================
    assign alu_ctrl = is_any_ext ? ext_ctrl : base_ctrl;

endmodule
