`timescale 1ns / 1ps

module ALU#(
    parameter DATAWIDTH = 32
)(
    input  logic [DATAWIDTH - 1:0]  A           ,
    input  logic [DATAWIDTH - 1:0]  B           ,
    input  logic [4:0]              ALUControl  ,  // ★ 扩展到5bit
    output logic [DATAWIDTH - 1:0]  Result
);

    localparam int MSB = DATAWIDTH - 1;

    logic is_sub_like;
    logic [DATAWIDTH-1:0] addsub_b;
    logic [DATAWIDTH:0] addsub_ext;
    logic [DATAWIDTH-1:0] addsub_res;
    logic slt_res, sltu_res;

    assign is_sub_like = (ALUControl == 5'd1) || (ALUControl == 5'd3) || (ALUControl == 5'd4);
    assign addsub_b    = B ^ {DATAWIDTH{is_sub_like}};
    assign addsub_ext  = {1'b0, A} + {1'b0, addsub_b} + {{DATAWIDTH{1'b0}}, is_sub_like};
    assign addsub_res  = addsub_ext[DATAWIDTH-1:0];
    assign slt_res     = (A[MSB] != B[MSB]) ? A[MSB] : addsub_res[MSB];
    assign sltu_res    = ~addsub_ext[DATAWIDTH];

    // ★ brev8: 字节内比特反转 (纯连线, 零逻辑深度)
    logic [DATAWIDTH-1:0] brev8_result;
    genvar k;
    generate
        for (k = 0; k < DATAWIDTH; k = k + 1) begin : gen_brev
            assign brev8_result[k] = A[(k & ~7) + (7 - (k & 7))];
        end
    endgenerate

    always_comb begin
        case (ALUControl)
            5'd0:  Result = addsub_res;                             // ADD
            5'd1:  Result = addsub_res;                             // SUB
            5'd2:  Result = A << B[4:0];                            // SLL
            5'd3:  Result = {{(DATAWIDTH-1){1'b0}}, slt_res};       // SLT
            5'd4:  Result = {{(DATAWIDTH-1){1'b0}}, sltu_res};      // SLTU
            5'd5:  Result = A ^ B;                                  // XOR
            5'd6:  Result = A >> B[4:0];                            // SRL
            5'd7:  Result = $signed(A) >>> B[4:0];                  // SRA
            5'd8:  Result = A | B;                                  // OR
            5'd9:  Result = A & B;                                  // AND
            // ★ Zba: 移位加 (移位量为纯连线，零逻辑延迟)
            5'd10: Result = ({A[30:0], 1'b0}) + B;                  // SH1ADD
            5'd11: Result = ({A[29:0], 2'b0}) + B;                  // SH2ADD
            5'd12: Result = ({A[28:0], 3'b0}) + B;                  // SH3ADD
            // ★ Zbs: 单比特操作 (5→32译码 + 一位逻辑门)
            5'd13: Result = A | (32'd1 << B[4:0]);                  // BSET/BSETI
            5'd14: Result = A & ~(32'd1 << B[4:0]);                 // BCLR/BCLRI
            5'd15: Result = A ^ (32'd1 << B[4:0]);                  // BINV/BINVI
            5'd16: Result = {31'b0, A[B[4:0]]};                     // BEXT/BEXTI
            // ★ Zbb: 基础逻辑非 (同速于 AND/OR/XOR)
            5'd17: Result = A & ~B;                                 // ANDN
            5'd18: Result = A | ~B;                                 // ORN
            5'd19: Result = ~(A ^ B);                               // XNOR
            // ★ Zbb: 符号扩展 (纯连线, 零逻辑深度)
            5'd20: Result = {{24{A[7]}}, A[7:0]};                  // SEXT.B
            5'd21: Result = {{16{A[15]}}, A[15:0]};                // SEXT.H
            // ★ Zbb: 按位或组合 (4路并行 OR-reduce, 一级门延迟)
            5'd22: Result = {{8{|A[31:24]}}, {8{|A[23:16]}},
                             {8{|A[15:8]}},  {8{|A[7:0]}}};        // ORC.B
            // ★ Zbkb: 字节/位反转 (纯连线, 零逻辑深度)
            5'd23: Result = {A[7:0], A[15:8], A[23:16], A[31:24]}; // REV8
            5'd24: Result = brev8_result;                            // BREV8
            // ★ Zbkb: 数据打包 (纯连线, 零逻辑深度)
            5'd25: Result = {B[15:0], A[15:0]};                     // PACK
            5'd26: Result = {B[7:0], A[7:0], B[7:0], A[7:0]};     // PACKH
            default: Result = {DATAWIDTH{1'b0}};
        endcase
    end

endmodule
