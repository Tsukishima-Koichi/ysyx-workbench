`timescale 1ns / 1ps
`include "defines.sv"

module RF #(
    parameter ADDR_WIDTH = 5,
    parameter DATAWIDTH  = 32
)(
    input  logic clk, rst,
    input  logic                    wen0, wen1,
    input  logic [ADDR_WIDTH-1:0]   waddr0, waddr1,
    input  logic [DATAWIDTH-1:0]    wdata0, wdata1,
    input  logic [ADDR_WIDTH-1:0]   rR1_0, rR2_0,
    input  logic [ADDR_WIDTH-1:0]   rR1_1, rR2_1,
    output logic [DATAWIDTH-1:0]    rR1_0_data, rR2_0_data,
    output logic [DATAWIDTH-1:0]    rR1_1_data, rR2_1_data
);
    logic [DATAWIDTH-1:0] reg_bank [31:0];

`ifdef NPC_TEST
    export "DPI-C" function get_gpr;
    function int get_gpr(input int idx);
        return reg_bank[idx];
    endfunction
`endif

    always_ff @(posedge clk) begin
        if (rst) begin
            for (int i = 0; i < 32; i++) reg_bank[i] <= 0;
        end else begin
            if (wen0 && waddr0 != 5'd0) reg_bank[waddr0] <= wdata0;
            if (wen1 && waddr1 != 5'd0) reg_bank[waddr1] <= wdata1;
        end
    end

    assign rR1_0_data = (rR1_0 == 5'd0) ? 32'd0 :
        (wen0 && waddr0 != 5'd0 && waddr0 == rR1_0) ? wdata0 :
        (wen1 && waddr1 != 5'd0 && waddr1 == rR1_0) ? wdata1 :
        reg_bank[rR1_0];
    assign rR2_0_data = (rR2_0 == 5'd0) ? 32'd0 :
        (wen0 && waddr0 != 5'd0 && waddr0 == rR2_0) ? wdata0 :
        (wen1 && waddr1 != 5'd0 && waddr1 == rR2_0) ? wdata1 :
        reg_bank[rR2_0];
    assign rR1_1_data = (rR1_1 == 5'd0) ? 32'd0 :
        (wen0 && waddr0 != 5'd0 && waddr0 == rR1_1) ? wdata0 :
        (wen1 && waddr1 != 5'd0 && waddr1 == rR1_1) ? wdata1 :
        reg_bank[rR1_1];
    assign rR2_1_data = (rR2_1 == 5'd0) ? 32'd0 :
        (wen0 && waddr0 != 5'd0 && waddr0 == rR2_1) ? wdata0 :
        (wen1 && waddr1 != 5'd0 && waddr1 == rR2_1) ? wdata1 :
        reg_bank[rR2_1];
endmodule
