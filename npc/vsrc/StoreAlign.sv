`timescale 1ns / 1ps

module StoreAlign #(
    parameter DATAWIDTH = 32
)(
    input  logic [1:0]             addr_offset , // 地址最低两位 (Result[1:0])
    input  logic [DATAWIDTH-1:0]   wdata_in    , // 寄存器原始数据 (rs2)
    input  logic [1:0]             size_mask   , // funct[1:0] (sb:00, sh:01, sw:10)
    input  logic                   MemWrite    , // 写使能
    
    output logic [3:0]             wmask_out   , // 输出 4位 Byte Enable
    output logic [DATAWIDTH-1:0]   wdata_out     // 铺满后的对齐数据
);
    always_comb begin
        wmask_out = 4'b0000;
        wdata_out = wdata_in;

        if (MemWrite) begin
            case (size_mask)
                2'b00: begin // sb: 铺满字节，掩码移位
                    wdata_out = {4{wdata_in[7:0]}};
                    wmask_out = 4'b0001 << addr_offset; 
                end
                2'b01: begin // sh: 铺满半字
                    wdata_out = {2{wdata_in[15:0]}};
                    wmask_out = addr_offset[1] ? 4'b1100 : 4'b0011;
                end
                2'b10: begin // sw: 整字输出
                    wdata_out = wdata_in;
                    wmask_out = 4'b1111;
                end
                default: wmask_out = 4'b0000;
            endcase
        end
    end
endmodule
