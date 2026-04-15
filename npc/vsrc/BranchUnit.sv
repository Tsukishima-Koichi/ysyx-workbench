`timescale 1ns / 1ps

module BranchUnit #(
    parameter DATAWIDTH = 32
)(
    input  logic [DATAWIDTH-1:0] pc,
    input  logic [DATAWIDTH-1:0] imm,
    input  logic [DATAWIDTH-1:0] rs1_data,
    input  logic [DATAWIDTH-1:0] rs2_data,
    input  logic [DATAWIDTH-1:0] trap_pc,
    input  logic                 Branch,
    input  logic [1:0]           Jump,
    input  logic [2:0]           funct3,
    
    output logic [DATAWIDTH-1:0] next_pc,
    output logic [DATAWIDTH-1:0] pc_plus_4
);
    assign pc_plus_4 = pc + 32'd4;
    
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
    
    logic [DATAWIDTH-1:0] branch_target, jalr_target;
    assign branch_target = pc + imm;
    assign jalr_target   = (rs1_data + imm) & ~32'h1;
    
    always_comb begin
        next_pc = pc_plus_4;
        if      (Jump == 2'b11) next_pc = trap_pc;       // ecall/mret
        else if (Jump == 2'b10) next_pc = jalr_target;   // JALR
        else if (Jump == 2'b01) next_pc = branch_target; // JAL
        else if (take_branch)   next_pc = branch_target; // Branch
    end
endmodule
