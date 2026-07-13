`timescale 1ns / 1ps

module ALU#(
    parameter DATAWIDTH = 32
)(
    input  logic [DATAWIDTH - 1:0]  A           ,
    input  logic [DATAWIDTH - 1:0]  B           ,
    input  logic [4:0]              ALUControl  ,  // ★ 5bit
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

    // --- Rotate ---
    logic [4:0] shamt;
    assign shamt   = B[4:0];
    wire [31:0] rol_res = (A << shamt) | (A >> (6'd32 - shamt));
    wire [31:0] ror_res = (A >> shamt) | (A << (6'd32 - shamt));

    // --- MIN/MAX ---
    logic signed [31:0] a_signed, b_signed;
    assign a_signed = A;
    assign b_signed = B;

    // --- ZIP / UNZIP ---
    wire [31:0] zip_res = {
        A[31], A[15], A[30], A[14], A[29], A[13], A[28], A[12],
        A[27], A[11], A[26], A[10], A[25], A[ 9], A[24], A[ 8],
        A[23], A[ 7], A[22], A[ 6], A[21], A[ 5], A[20], A[ 4],
        A[19], A[ 3], A[18], A[ 2], A[17], A[ 1], A[16], A[ 0]
    };
    wire [31:0] unzip_res = {
        A[31], A[29], A[27], A[25], A[23], A[21], A[19], A[17],
        A[15], A[13], A[11], A[ 9], A[ 7], A[ 5], A[ 3], A[ 1],
        A[30], A[28], A[26], A[24], A[22], A[20], A[18], A[16],
        A[14], A[12], A[10], A[ 8], A[ 6], A[ 4], A[ 2], A[ 0]
    };

    // --- XPERM8 ---
    function [7:0] xperm8_byte(input [31:0] src, input [7:0] idx);
        if (idx[7]) xperm8_byte = 8'h00;
        else case (idx[2:0])
            3'd0: xperm8_byte = src[ 7: 0];
            3'd1: xperm8_byte = src[15: 8];
            3'd2: xperm8_byte = src[23:16];
            3'd3: xperm8_byte = src[31:24];
            default: xperm8_byte = 8'h00;
        endcase
    endfunction
    wire [31:0] xperm8_res;
    assign xperm8_res[ 7: 0] = xperm8_byte(A, B[ 7: 0]);
    assign xperm8_res[15: 8] = xperm8_byte(A, B[15: 8]);
    assign xperm8_res[23:16] = xperm8_byte(A, B[23:16]);
    assign xperm8_res[31:24] = xperm8_byte(A, B[31:24]);

    always_comb begin
        case (ALUControl)
            5'd0:  Result = addsub_res;                             // ADD
            5'd1:  Result = addsub_res;                             // SUB
            5'd2:  Result = A << shamt;                             // SLL
            5'd3:  Result = {{(DATAWIDTH-1){1'b0}}, slt_res};       // SLT
            5'd4:  Result = {{(DATAWIDTH-1){1'b0}}, sltu_res};      // SLTU
            5'd5:  Result = A ^ B;                                  // XOR
            5'd6:  Result = A >> shamt;                             // SRL
            5'd7:  Result = $signed(A) >>> shamt;                   // SRA
            5'd8:  Result = A | B;                                  // OR
            5'd9:  Result = A & B;                                  // AND
            5'd10: Result = rol_res;                                // ROL
            5'd11: Result = ror_res;                                // ROR / RORI
            5'd12: Result = (a_signed < b_signed) ? A : B;          // MIN
            5'd13: Result = (a_signed > b_signed) ? A : B;          // MAX
            5'd14: Result = (A < B) ? A : B;                        // MINU
            5'd15: Result = (A > B) ? A : B;                        // MAXU
            5'd16: Result = zip_res;                                // ZIP
            5'd17: Result = unzip_res;                              // UNZIP
            5'd18: Result = xperm8_res;                             // XPERM8
            default: Result = {DATAWIDTH{1'b0}};
        endcase
    end

endmodule
