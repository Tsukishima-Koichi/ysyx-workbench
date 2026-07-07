`timescale 1ns / 1ps

module ForwardingUnit(
    input  logic [4:0] id_rs1, id_rs2,
    
    input  logic       ex_RegWen,
    input  logic [4:0] ex_rd,
    input  logic       mem1_RegWen,
    input  logic [4:0] mem1_rd,
    input  logic       mem2_RegWen,
    input  logic [4:0] mem2_rd,
    input  logic       wb_RegWen,
    input  logic [4:0] wb_rd,
  
    // 00: RF, 01: WB, 10: MEM2, 11: MEM1, 100: EX (新增第3位以支持更深层级)
    output logic [2:0] id_forward_A, id_forward_B
);
    always_comb begin
        // Forward A 优先级: EX > MEM1 > MEM2 > WB > RF
        if      (ex_RegWen   && ex_rd   != 5'b0 && ex_rd   == id_rs1) id_forward_A = 3'b100;
        else if (mem1_RegWen && mem1_rd != 5'b0 && mem1_rd == id_rs1) id_forward_A = 3'b011;
        else if (mem2_RegWen && mem2_rd != 5'b0 && mem2_rd == id_rs1) id_forward_A = 3'b010;
        else if (wb_RegWen   && wb_rd   != 5'b0 && wb_rd   == id_rs1) id_forward_A = 3'b001;
        else                                                          id_forward_A = 3'b000;
        
        // Forward B
        if      (id_rs2 != 5'd0 && ex_RegWen   && ex_rd   != 5'b0 && ex_rd   == id_rs2) id_forward_B = 3'b100;
        else if (id_rs2 != 5'd0 && mem1_RegWen && mem1_rd != 5'b0 && mem1_rd == id_rs2) id_forward_B = 3'b011;
        else if (id_rs2 != 5'd0 && mem2_RegWen && mem2_rd != 5'b0 && mem2_rd == id_rs2) id_forward_B = 3'b010;
        else if (id_rs2 != 5'd0 && wb_RegWen   && wb_rd   != 5'b0 && wb_rd   == id_rs2) id_forward_B = 3'b001;
        else                                                          id_forward_B = 3'b000;
    end
endmodule
