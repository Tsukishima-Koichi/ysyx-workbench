`timescale 1ns / 1ps

module ALU#(
    parameter DATAWIDTH = 32	
)(
    input  logic [DATAWIDTH - 1:0]  A           ,
    input  logic [DATAWIDTH - 1:0]  B           ,
    input  logic [3:0]              ALUControl  ,
    output logic [DATAWIDTH - 1:0]  Result      
);

    // ==========================================
    // RV32I
    // ==========================================
    always_comb begin
        case (ALUControl)
            4'd0:  Result = A + B;                                  // ADD
            4'd1:  Result = A - B;                                  // SUB
            4'd2:  Result = A << B[4:0];                            // SLL
            4'd3:  Result = $signed(A) < $signed(B) ? 32'd1 : 32'd0;// SLT
            4'd4:  Result = A < B ? 32'd1 : 32'd0;                  // SLTU
            4'd5:  Result = A ^ B;                                  // XOR
            4'd6:  Result = A >> B[4:0];                            // SRL
            4'd7:  Result = $signed(A) >>> B[4:0];                  // SRA
            4'd8:  Result = A | B;                                  // OR
            4'd9:  Result = A & B;                                  // AND
            default: Result = 32'b0;
        endcase
    end

endmodule
