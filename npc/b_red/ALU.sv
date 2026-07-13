`timescale 1ns / 1ps

module ALU#(
    parameter DATAWIDTH = 32	
)(
    input  logic [DATAWIDTH - 1:0]  A           ,
    input  logic [DATAWIDTH - 1:0]  B           ,
    input  logic [3:0]              ALUControl  ,
    output logic [DATAWIDTH - 1:0]  Result      
);

    localparam int MSB = DATAWIDTH - 1;

    logic is_sub_like;
    logic [DATAWIDTH-1:0] addsub_b;
    logic [DATAWIDTH:0] addsub_ext;
    logic [DATAWIDTH-1:0] addsub_res;
    logic slt_res, sltu_res;

    // ---- CLMUL carry-less multiplication (纯组合逻辑) ----
    function automatic [63:0] clmul_64(input [31:0] a, b);
        automatic logic [63:0] result;
        result = 64'b0;
        for (int i = 0; i < 32; i++) begin
            if (a[i]) result = result ^ ({32'b0, b} << i);
        end
        return result;
    endfunction
    wire [63:0] clmul_full;
    assign clmul_full = clmul_64(A, B);

    assign is_sub_like = (ALUControl == 4'd1) || (ALUControl == 4'd3) || (ALUControl == 4'd4);
    assign addsub_b    = B ^ {DATAWIDTH{is_sub_like}};
    assign addsub_ext  = {1'b0, A} + {1'b0, addsub_b} + {{DATAWIDTH{1'b0}}, is_sub_like};
    assign addsub_res  = addsub_ext[DATAWIDTH-1:0];
    assign slt_res     = (A[MSB] != B[MSB]) ? A[MSB] : addsub_res[MSB];
    assign sltu_res    = ~addsub_ext[DATAWIDTH];

    always_comb begin
        case (ALUControl)
            4'd0:  Result = addsub_res;                             // ADD
            4'd1:  Result = addsub_res;                             // SUB
            4'd2:  Result = A << B[4:0];                            // SLL
            4'd3:  Result = {{(DATAWIDTH-1){1'b0}}, slt_res};       // SLT
            4'd4:  Result = {{(DATAWIDTH-1){1'b0}}, sltu_res};      // SLTU
            4'd5:  Result = A ^ B;                                  // XOR
            4'd6:  Result = A >> B[4:0];                            // SRL
            4'd7:  Result = $signed(A) >>> B[4:0];                  // SRA
            4'd8:  Result = A | B;                                  // OR
            4'd9:  Result = A & B;                                  // AND
            4'd10: Result = clmul_full[31:0];                        // CLMUL
            4'd11: Result = clmul_full[62:31];                       // CLMULR
            4'd12: Result = clmul_full[63:32];                       // CLMULH
            default: Result = {DATAWIDTH{1'b0}};
        endcase
    end

endmodule
