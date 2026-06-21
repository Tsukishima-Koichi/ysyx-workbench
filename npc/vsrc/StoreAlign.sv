`timescale 1ns / 1ps

module StoreAlign #(
    parameter DATAWIDTH = 32
)(
    input  logic [1:0]             addr_offset ,
    input  logic [DATAWIDTH-1:0]   wdata_in    ,
    input  logic [1:0]             size_mask   ,
    input  logic                   MemWrite    , 
    output logic [3:0]             wmask_out   ,
    output logic [DATAWIDTH-1:0]   wdata_out    
);
    always_comb begin
        wmask_out = 4'b0000;
        wdata_out = wdata_in;
        
        if (MemWrite) begin
            case (size_mask)
                2'b00: begin // sb
                    wdata_out = {4{wdata_in[7:0]}};
                    wmask_out = 4'b0001 << addr_offset; 
                end
                2'b01: begin // sh
                    wdata_out = {2{wdata_in[15:0]}};
                    wmask_out = addr_offset[1] ? 4'b1100 : 4'b0011;
                end
                2'b10: begin // sw
                    wdata_out = wdata_in;
                    wmask_out = 4'b1111;
                end
                default: wmask_out = 4'b0000;
            endcase
        end
    end
endmodule
