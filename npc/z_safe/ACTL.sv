`timescale 1ns / 1ps
`include "defines.sv"

module ACTL(
    input  logic [6:0] opcode,
    input  logic [2:0] funct3,
    input  logic [6:0] funct7,
    input  logic [4:0] shamt,         // ★ Zbb/Zbkb: inst[24:20] 用于区分子指令
    output logic [4:0] alu_ctrl       // ★ 5bit: 编码 Zba/Zbs/Zbb/Zbkb
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
    // 2.5 ★ Zba / Zbs 扩展检测
    // --------------------------------------------------------
    // Zba: R-type, funct7=0010000 (sh1add, sh2add, sh3add)
    wire is_zba = is_R & (funct7 === 7'b0010000);
    // Zbs: R-type 或 I-type, 仅匹配 Zbs 专属的 (funct3, funct7) 组合
    wire is_zbs = use_funct3 & (
        (funct3 === 3'b001 & (funct7 === 7'b0010100 | funct7 === 7'b0100100 | funct7 === 7'b0110100)) |
        (funct3 === 3'b101 & funct7 === 7'b0100100)
    );
    // ★ Zbb: 基础逻辑非 (andn, orn, xnor) — R-type, funct7=0100000
    wire is_zbb_neg = is_R & (funct7 === 7'b0100000) &
                      ((funct3 === 3'b111) | (funct3 === 3'b110) | (funct3 === 3'b100));
    // ★ Zbb: 符号/零扩展 (sext.b, sext.h) — I-type, funct7=0110000, funct3=001
    wire is_zbb_sext = is_I & (funct7 === 7'b0110000) & (funct3 === 3'b001);
    // ★ Zbb: orc.b — I-type, funct7=0010100, funct3=101
    wire is_zbb_orc  = is_I & (funct7 === 7'b0010100) & (funct3 === 3'b101);
    // ★ Zbkb: rev8, brev8 — I-type, funct7=0110100, funct3=101
    wire is_zbkb_rev = is_I & (funct7 === 7'b0110100) & (funct3 === 3'b101);
    // ★ Zbkb: pack, packh — R-type, funct7=0000100
    wire is_zbkb_pack= is_R & (funct7 === 7'b0000100) &
                      ((funct3 === 3'b100) | (funct3 === 3'b111));
    // 组合: 任意扩展指令
    wire is_any_ext  = is_zba | is_zbs | is_zbb_neg | is_zbb_sext |
                       is_zbb_orc | is_zbkb_rev | is_zbkb_pack;

    // --------------------------------------------------------
    // 3. 并行输出各比特位——基类指令 (bits 3:0 保持原有逻辑不变)
    // --------------------------------------------------------
    logic [3:0] alu_ctrl_base;
    assign alu_ctrl_base[3] = use_funct3 & (funct3[2] & funct3[1]);
    assign alu_ctrl_base[2] = use_funct3 & ( (funct3 === 3'b011) | (funct3[2] & ~funct3[1]) );
    assign alu_ctrl_base[1] = use_funct3 & ( (funct3 === 3'b001) | (funct3 === 3'b010) | (funct3 === 3'b101) );
    assign alu_ctrl_base[0] = use_funct3 & ( is_sub | (funct3 === 3'b010) | (funct3 === 3'b100) | is_sra | (funct3 === 3'b111) );

    // --------------------------------------------------------
    // 3.5 ★ 扩展指令操作码编码 (5-bit, 10–26)
    // --------------------------------------------------------
    logic [4:0] alu_ctrl_ext;
    always_comb begin
        alu_ctrl_ext = 5'd0;
        // Zba
        if (is_zba) begin
            case (funct3)
                3'b010: alu_ctrl_ext = 5'd10;  // SH1ADD
                3'b100: alu_ctrl_ext = 5'd11;  // SH2ADD
                3'b110: alu_ctrl_ext = 5'd12;  // SH3ADD
                default: ;
            endcase
        // Zbs
        end else if (is_zbs) begin
            if (funct3 === 3'b001) begin
                case (funct7)
                    7'b0010100: alu_ctrl_ext = 5'd13;  // BSET/BSETI
                    7'b0100100: alu_ctrl_ext = 5'd14;  // BCLR/BCLRI
                    7'b0110100: alu_ctrl_ext = 5'd15;  // BINV/BINVI
                    default: ;
                endcase
            end else if (funct3 === 3'b101 && funct7 === 7'b0100100) begin
                alu_ctrl_ext = 5'd16;  // BEXT/BEXTI
            end
        // Zbb: andn, orn, xnor
        end else if (is_zbb_neg) begin
            case (funct3)
                3'b111: alu_ctrl_ext = 5'd17;  // ANDN
                3'b110: alu_ctrl_ext = 5'd18;  // ORN
                3'b100: alu_ctrl_ext = 5'd19;  // XNOR
                default: ;
            endcase
        // Zbb: sext.b, sext.h
        end else if (is_zbb_sext) begin
            case (shamt)
                5'b00100: alu_ctrl_ext = 5'd20;  // SEXT.B
                5'b00101: alu_ctrl_ext = 5'd21;  // SEXT.H
                default: ;
            endcase
        // Zbb: orc.b
        end else if (is_zbb_orc) begin
            alu_ctrl_ext = 5'd22;  // ORC.B
        // Zbkb: rev8, brev8
        end else if (is_zbkb_rev) begin
            case (shamt)
                5'b11000: alu_ctrl_ext = 5'd23;  // REV8
                5'b00111: alu_ctrl_ext = 5'd24;  // BREV8
                default: ;
            endcase
        // Zbkb: pack, packh
        end else if (is_zbkb_pack) begin
            case (funct3)
                3'b100: alu_ctrl_ext = 5'd25;  // PACK
                3'b111: alu_ctrl_ext = 5'd26;  // PACKH
                default: ;
            endcase
        end
    end

    // --------------------------------------------------------
    // 4. 最终输出: 扩展指令命中时覆盖，否则用基类编码
    // --------------------------------------------------------
    assign alu_ctrl = is_any_ext ? alu_ctrl_ext : {1'b0, alu_ctrl_base};

endmodule
