`timescale 1ns / 1ps

module PC#(
    parameter   DATAWIDTH   = 32              ,
    parameter   RESET_VAL   = 32'h8000_0000
)(
    input  logic                   clk  ,
    input  logic                   rst  ,
    input  logic [DATAWIDTH - 1:0] npc  ,
    output logic [DATAWIDTH - 1:0] pc_out   
);
    logic [DATAWIDTH - 1:0] reg_pc;

    // 彻底删除 rst_delay，精准响应复位
    always_ff @(posedge clk) begin
        if (rst) reg_pc <= RESET_VAL;
        else     reg_pc <= npc;
    end 

    assign pc_out = reg_pc;
endmodule
