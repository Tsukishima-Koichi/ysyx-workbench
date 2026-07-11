`timescale 1ns / 1ps

module AGU #(parameter DATAWIDTH = 32)(
    input  logic [DATAWIDTH-1:0] base,
    input  logic [DATAWIDTH-1:0] offset,
    output logic [DATAWIDTH-1:0] addr
);
    // 纯粹的 32 位加法，比全功能 ALU 快得多
    assign addr = base + offset;

endmodule
