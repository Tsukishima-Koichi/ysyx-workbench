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

    assign is_sub_like = (ALUControl == 4'd1) || (ALUControl == 4'd3) || (ALUControl == 4'd4);
    assign addsub_b    = B ^ {DATAWIDTH{is_sub_like}};
    assign addsub_ext  = {1'b0, A} + {1'b0, addsub_b} + {{DATAWIDTH{1'b0}}, is_sub_like};
    assign addsub_res  = addsub_ext[DATAWIDTH-1:0];
    assign slt_res     = (A[MSB] != B[MSB]) ? A[MSB] : addsub_res[MSB];
    assign sltu_res    = ~addsub_ext[DATAWIDTH];

    // --- CLZ ---
    logic [5:0] clz_result;
    always_comb begin
        clz_result = 6'd32;
        for (int i = 0; i < 32; i++)
            if (A[i]) clz_result = 6'd31 - 6'(i[4:0]);
    end

    // --- CTZ ---
    logic [5:0] ctz_result;
    always_comb begin
        ctz_result = 6'd32;
        for (int i = 31; i >= 0; i--)
            if (A[i]) ctz_result = 6'(i[4:0]);
    end

    // --- CPOP ---
    logic [5:0] cpop_result;
    always_comb begin
        cpop_result = 6'd0;
        for (int i = 0; i < 32; i++)
            cpop_result = cpop_result + {5'b0, A[i]};
    end

    // --- XPERM4 ---
    logic [31:0] xperm4_result;
    always_comb begin
        for (int i = 0; i < 8; i++) begin
            case (B[4*i +: 4])
                4'd0:  xperm4_result[4*i +: 4] = A[ 3: 0];
                4'd1:  xperm4_result[4*i +: 4] = A[ 7: 4];
                4'd2:  xperm4_result[4*i +: 4] = A[11: 8];
                4'd3:  xperm4_result[4*i +: 4] = A[15:12];
                4'd4:  xperm4_result[4*i +: 4] = A[19:16];
                4'd5:  xperm4_result[4*i +: 4] = A[23:20];
                4'd6:  xperm4_result[4*i +: 4] = A[27:24];
                4'd7:  xperm4_result[4*i +: 4] = A[31:28];
                default: xperm4_result[4*i +: 4] = 4'b0;
            endcase
        end
    end

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
            4'd10: Result = {26'b0, clz_result};                    // CLZ
            4'd11: Result = {26'b0, ctz_result};                    // CTZ
            4'd12: Result = {26'b0, cpop_result};                   // CPOP
            4'd13: Result = xperm4_result;                          // XPERM4
            default: Result = {DATAWIDTH{1'b0}};
        endcase
    end

endmodule
