`timescale 1ns / 1ps
`include "defines.sv"

module ACTL(
    input  logic [6:0] opcode,
    input  logic [2:0] funct3,
    input  logic [6:0] funct7,
    output logic [4:0] alu_ctrl       // 5bit: 0-9基类, 10-18 green
);
    wire is_R = (opcode === `R_TYPE);
    wire is_I = (opcode === `I_TYPE);
    wire use_funct3 = is_R | is_I;

    // 基类: is_sra 需排除 ROR/RORI(funct7=0110000,bit5=1) 和 MINU(funct7=0000101)
    wire is_sub = is_R & (funct3 === 3'b000) & (funct7[5] === 1'b1);
    wire is_ror  = is_R & (funct3 === 3'b101) & (funct7 === 7'b0110000);
    wire is_rori = is_I & (funct3 === 3'b101) & (funct7 === 7'b0110000);
    wire is_minu = is_R & (funct3 === 3'b101) & (funct7 === 7'b0000101);
    wire is_sra  = use_funct3 & (funct3 === 3'b101) & (funct7[5] === 1'b1)
                 & ~is_ror & ~is_rori & ~is_minu;

    // ★ 并行检测 green 指令 (10条)
    wire is_rol    = is_R & (funct3 === 3'b001) & (funct7 === 7'b0110000);
    wire is_max    = is_R & (funct3 === 3'b110) & (funct7 === 7'b0000101);
    wire is_min    = is_R & (funct3 === 3'b100) & (funct7 === 7'b0000101);
    wire is_maxu   = is_R & (funct3 === 3'b111) & (funct7 === 7'b0000101);
    wire is_zip    = is_R & (funct3 === 3'b001) & (funct7 === 7'b0000100);
    wire is_unzip  = is_R & (funct3 === 3'b101) & (funct7 === 7'b0000100);
    wire is_xperm8 = is_R & (funct3 === 3'b100) & (funct7 === 7'b0010100);

    wire is_new = is_rol | is_ror | is_rori | is_min | is_max | is_minu | is_maxu
                | is_zip | is_unzip | is_xperm8;

    // 基类编码 (同 fastest 并行布尔)
    wire [4:0] base_ctrl;
    assign base_ctrl[4] = 1'b0;
    assign base_ctrl[3] = use_funct3 & (funct3[2] & funct3[1]);
    assign base_ctrl[2] = use_funct3 & ( (funct3 === 3'b011) | (funct3[2] & ~funct3[1]) );
    assign base_ctrl[1] = use_funct3 & ( (funct3 === 3'b001) | (funct3 === 3'b010) | (funct3 === 3'b101) );
    assign base_ctrl[0] = use_funct3 & ( is_sub | (funct3 === 3'b010) | (funct3 === 3'b100) | is_sra | (funct3 === 3'b111) );

    // ★ 扩展编码: unique case 并行 MUX (无优先级链)
    //    10=ROL 11=ROR/RORI 12=MIN 13=MAX 14=MINU 15=MAXU
    //    16=ZIP 17=UNZIP 18=XPERM8
    logic [4:0] new_ctrl;
    always_comb begin
        unique case (1'b1)
            is_rol:    new_ctrl = 5'd10;
            is_ror:    new_ctrl = 5'd11;
            is_rori:   new_ctrl = 5'd11;
            is_min:    new_ctrl = 5'd12;
            is_max:    new_ctrl = 5'd13;
            is_minu:   new_ctrl = 5'd14;
            is_maxu:   new_ctrl = 5'd15;
            is_zip:    new_ctrl = 5'd16;
            is_unzip:  new_ctrl = 5'd17;
            is_xperm8: new_ctrl = 5'd18;
            default:   new_ctrl = 5'd0;
        endcase
    end

    assign alu_ctrl = is_new ? new_ctrl : base_ctrl;

endmodule
