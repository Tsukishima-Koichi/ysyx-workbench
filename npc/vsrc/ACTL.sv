`timescale 1ns / 1ps
`include "defines.sv"

module ACTL(
    input  logic [6:0] opcode,
    input  logic [2:0] funct3,
    input  logic [6:0] funct7,
    output logic [3:0] alu_ctrl
);
    // (RV32I)
    localparam ALU_ADD  = 4'd0;
    localparam ALU_SUB  = 4'd1;
    localparam ALU_SLL  = 4'd2;
    localparam ALU_SLT  = 4'd3;
    localparam ALU_SLTU = 4'd4;
    localparam ALU_XOR  = 4'd5;
    localparam ALU_SRL  = 4'd6;
    localparam ALU_SRA  = 4'd7;
    localparam ALU_OR   = 4'd8;
    localparam ALU_AND  = 4'd9;

    always_comb begin
        alu_ctrl = ALU_ADD;
        
        case(opcode)
            `R_TYPE: begin
                case(funct3)
                    3'b000: alu_ctrl = (funct7[5]) ? ALU_SUB : ALU_ADD; // ADD / SUB
                    3'b001: alu_ctrl = ALU_SLL;
                    3'b010: alu_ctrl = ALU_SLT;
                    3'b011: alu_ctrl = ALU_SLTU;
                    3'b100: alu_ctrl = ALU_XOR;
                    3'b101: alu_ctrl = (funct7[5]) ? ALU_SRA : ALU_SRL; // SRL / SRA
                    3'b110: alu_ctrl = ALU_OR;
                    3'b111: alu_ctrl = ALU_AND;
                endcase
            end
            `I_TYPE: begin
                case(funct3)
                    3'b000: alu_ctrl = ALU_ADD; // ADDI
                    3'b001: alu_ctrl = ALU_SLL; // SLLI
                    3'b010: alu_ctrl = ALU_SLT; // SLTI
                    3'b011: alu_ctrl = ALU_SLTU;// SLTIU
                    3'b100: alu_ctrl = ALU_XOR; // XORI
                    3'b101: alu_ctrl = (funct7[5]) ? ALU_SRA : ALU_SRL; // SRLI / SRAI
                    3'b110: alu_ctrl = ALU_OR;  // ORI
                    3'b111: alu_ctrl = ALU_AND; // ANDI
                endcase
            end
            `B_TYPE: alu_ctrl = ALU_ADD;   
            `IL_TYPE, `S_TYPE, `IJ_TYPE: alu_ctrl = ALU_ADD;
            `U_TYPE: alu_ctrl = ALU_ADD; 
            `UA_TYPE: alu_ctrl = ALU_ADD;
            `J_TYPE: alu_ctrl = ALU_ADD;
            default: alu_ctrl = ALU_ADD;
        endcase
    end
endmodule
