`timescale 1ns / 1ps

module Mask#(
    parameter DATAWIDTH = 32	
)(
    input  logic [2:0]             mask   , // funct3
    input  logic [DATAWIDTH - 1:0] dout	  , // 经过移位对齐后的内存原始数据
    output logic [DATAWIDTH - 1:0] mdata    // 最终写回寄存器的数据
);
    always_comb begin
        case (mask)
            3'b000: mdata = {{25{dout[7]}}, dout[6:0]};   // lb : 符号扩展
            3'b001: mdata = {{17{dout[15]}}, dout[14:0]}; // lh : 符号扩展
            3'b100: mdata = {24'b0, dout[7:0]};           // lbu: 零扩展 (高24位补0)
            3'b101: mdata = {16'b0, dout[15:0]};          // lhu: 零扩展 (高16位补0)
            default: mdata = dout;                        // lw : 直接透传
        endcase
    end
endmodule
