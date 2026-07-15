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
    logic [DATAWIDTH-1:0] sh2add_res;
    logic slt_res, sltu_res;

    assign is_sub_like = (ALUControl == 4'd1) || (ALUControl == 4'd3) || (ALUControl == 4'd4);
    assign addsub_b    = B ^ {DATAWIDTH{is_sub_like}};
    assign addsub_ext  = {1'b0, A} + {1'b0, addsub_b} + {{DATAWIDTH{1'b0}}, is_sub_like};
    assign addsub_res  = addsub_ext[DATAWIDTH-1:0];
    // A fixed two-bit shift is wiring.  Use a dedicated 32-bit adder so the
    // existing RV32I add/sub carry chain does not gain an input mux.
    assign sh2add_res  = {A[DATAWIDTH-3:0], 2'b0} + B;
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
            4'd10: Result = sh2add_res;                             // SH2ADD
            default: Result = {DATAWIDTH{1'b0}};
        endcase
    end

endmodule
