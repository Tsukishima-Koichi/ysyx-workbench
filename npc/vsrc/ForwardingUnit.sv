module ForwardingUnit(
    input  logic [4:0] id_rs1, id_rs2,
    
    input  logic       ex_RegWen,
    input  logic [4:0] ex_rd,
    input  logic       mem1_RegWen,
    input  logic [4:0] mem1_rd,
    // 👇 恢复成 mem2
    input  logic       mem2_RegWen,
    input  logic [4:0] mem2_rd,
  
    output logic [1:0] id_forward_A, id_forward_B
);
    always_comb begin
        // Forward A
        if      (ex_RegWen   && ex_rd   != 5'b0 && ex_rd   == id_rs1) id_forward_A = 2'b11;
        else if (mem1_RegWen && mem1_rd != 5'b0 && mem1_rd == id_rs1) id_forward_A = 2'b10;
        else if (mem2_RegWen && mem2_rd != 5'b0 && mem2_rd == id_rs1) id_forward_A = 2'b01; // 恢复
        else                                                          id_forward_A = 2'b00;

        // Forward B
        if      (ex_RegWen   && ex_rd   != 5'b0 && ex_rd   == id_rs2) id_forward_B = 2'b11;
        else if (mem1_RegWen && mem1_rd != 5'b0 && mem1_rd == id_rs2) id_forward_B = 2'b10;
        else if (mem2_RegWen && mem2_rd != 5'b0 && mem2_rd == id_rs2) id_forward_B = 2'b01; // 恢复
        else                                                          id_forward_B = 2'b00;
    end
endmodule
