`timescale 1ns / 1ps

module AGU #(parameter DATAWIDTH = 32)(
    input  logic [DATAWIDTH-1:0] base,
    input  logic [DATAWIDTH-1:0] offset,
    output logic [DATAWIDTH-1:0] addr
);
    assign addr = base + offset;
endmodule
