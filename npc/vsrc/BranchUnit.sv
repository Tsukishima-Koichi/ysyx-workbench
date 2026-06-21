`timescale 1ns / 1ps

module BranchUnit #(
    parameter DATAWIDTH = 32
)(
    input  logic [DATAWIDTH-1:0] imm,
    input  logic [DATAWIDTH-1:0] rs1_data,
    input  logic [DATAWIDTH-1:0] rs2_data,
    
    input  logic [DATAWIDTH-1:0] precalc_branch_target,
    input  logic [DATAWIDTH-1:0] precalc_pc_plus_4,    
    
    input  logic [DATAWIDTH-1:0] trap_pc,
    input  logic                 Branch,
    input  logic [1:0]           Jump,
    input  logic [2:0]           funct3,
    
    output logic [DATAWIDTH-1:0] next_pc,
    output logic                 actual_taken // 删除了 pc_plus_4
);
    // 删除了 assign pc_plus_4 = precalc_pc_plus_4;
    
    logic is_equal, is_less_s, is_less_u;
    assign is_equal  = (rs1_data == rs2_data);
    assign is_less_s = ($signed(rs1_data) < $signed(rs2_data));
    assign is_less_u = (rs1_data < rs2_data);

    logic take_branch;
    always_comb begin
        take_branch = 1'b0;
        if (Branch) begin
            case (funct3)
                3'b000: take_branch = is_equal;
                3'b001: take_branch = !is_equal;
                3'b100: take_branch = is_less_s;
                3'b101: take_branch = !is_less_s;
                3'b110: take_branch = is_less_u;
                3'b111: take_branch = !is_less_u;
                default: take_branch = 1'b0;
            endcase
        end
    end

    assign actual_taken = (Jump != 2'b00) || (Branch && take_branch);
    
    logic [DATAWIDTH-1:0] jalr_target;
    assign jalr_target = (rs1_data + imm) & ~32'h1;

    always_comb begin
        next_pc = precalc_pc_plus_4;
        if      (Jump == 2'b11) next_pc = trap_pc;
        else if (Jump == 2'b10) next_pc = jalr_target;
        else if (Jump == 2'b01) next_pc = precalc_branch_target;
        else if (take_branch)   next_pc = precalc_branch_target;
    end
endmodule
