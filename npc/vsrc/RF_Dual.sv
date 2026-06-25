`timescale 1ns / 1ps
`include "defines.sv"

/**
 * 双发射寄存器文件 — 4 读端口 + 2 写端口
 */
module RF_Dual #(
    parameter ADDR_WIDTH = 5,
    parameter DATAWIDTH  = 32
)(
    input  logic clk, rst,
    input  logic                    wen0, wen1,
    input  logic [ADDR_WIDTH-1:0]   waddr0, waddr1,
    input  logic [DATAWIDTH-1:0]    wdata0, wdata1,
    input  logic [ADDR_WIDTH-1:0]   rR1_0, rR2_0,  // inst0: rs1, rs2
    input  logic [ADDR_WIDTH-1:0]   rR1_1, rR2_1,  // inst1: rs1, rs2
    output logic [DATAWIDTH-1:0]    rR1_0_data, rR2_0_data,
    output logic [DATAWIDTH-1:0]    rR1_1_data, rR2_1_data
);
    logic [DATAWIDTH-1:0] reg_bank [31:0];

    always_ff @(posedge clk) begin
        if (rst) begin
            for (int i = 0; i < 32; i++) reg_bank[i] <= 0;
        end else begin
            if (wen0 && waddr0 != 5'd0) reg_bank[waddr0] <= wdata0;
            if (wen1 && waddr1 != 5'd0) reg_bank[waddr1] <= wdata1;
        end
    end

    // 读端口 0 (inst0 rs1): wen0 优先, wen1 次之 (inst0 先写)
    assign rR1_0_data = (wen0 && waddr0 != 5'd0 && waddr0 == rR1_0) ? wdata0 :
                        (wen1 && waddr1 != 5'd0 && waddr1 == rR1_0) ? wdata1 :
                        reg_bank[rR1_0];
    assign rR2_0_data = (wen0 && waddr0 != 5'd0 && waddr0 == rR2_0) ? wdata0 :
                        (wen1 && waddr1 != 5'd0 && waddr1 == rR2_0) ? wdata1 :
                        reg_bank[rR2_0];
    assign rR1_1_data = (wen0 && waddr0 != 5'd0 && waddr0 == rR1_1) ? wdata0 :
                        (wen1 && waddr1 != 5'd0 && waddr1 == rR1_1) ? wdata1 :
                        reg_bank[rR1_1];
    assign rR2_1_data = (wen0 && waddr0 != 5'd0 && waddr0 == rR2_1) ? wdata0 :
                        (wen1 && waddr1 != 5'd0 && waddr1 == rR2_1) ? wdata1 :
                        reg_bank[rR2_1];
endmodule
