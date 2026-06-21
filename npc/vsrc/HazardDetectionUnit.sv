`timescale 1ns / 1ps
`include "defines.sv"

module HazardDetectionUnit(
    input  logic [4:0] id_rs1, id_rs2,
    input  logic [6:0] id_opcode,

    input  logic       ex_RegWen,
    input  logic [1:0] ex_WbSel,
    input  logic [4:0] ex_rd,

    input  logic       mem1_RegWen,
    input  logic [1:0] mem1_WbSel,
    input  logic [4:0] mem1_rd,

    // actual MEM1 stage (after BR) -- loads here don't have data ready yet
    input  logic       ls_RegWen,
    input  logic [1:0] ls_WbSel,
    input  logic [4:0] ls_rd,

    output logic       stall_ID, flush_ID_EX
);
    logic rs1_read, rs2_read, is_load_use;

    always_comb begin
        case (id_opcode)
            `R_TYPE, `I_TYPE, `IL_TYPE, `IJ_TYPE, `S_TYPE, `B_TYPE, `CSR_TYPE: rs1_read = 1'b1;
            default: rs1_read = 1'b0;
        endcase
        case (id_opcode)
            `R_TYPE, `S_TYPE, `B_TYPE: rs2_read = 1'b1;
            default: rs2_read = 1'b0;
        endcase
    end

    always_comb begin
        is_load_use = 1'b0;
        // EX1 stage
        if (ex_WbSel == 2'b10 && ex_rd != 5'd0) begin
            if ((rs1_read && ex_rd == id_rs1) || (rs2_read && ex_rd == id_rs2))
                is_load_use = 1'b1;
        end
        // BR stage
        if (mem1_WbSel == 2'b10 && mem1_rd != 5'd0) begin
            if ((rs1_read && mem1_rd == id_rs1) || (rs2_read && mem1_rd == id_rs2))
                is_load_use = 1'b1;
        end
        // MEM1 stage (actual memory stage) -- loaded data not ready yet
        if (ls_WbSel == 2'b10 && ls_rd != 5'd0) begin
            if ((rs1_read && ls_rd == id_rs1) || (rs2_read && ls_rd == id_rs2))
                is_load_use = 1'b1;
        end
    end

    assign stall_ID    = is_load_use;
    assign flush_ID_EX = is_load_use;
endmodule
