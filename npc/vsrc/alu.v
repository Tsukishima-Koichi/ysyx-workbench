module alu(
    input  [31:0] a,
    input  [31:0] b,
    output [31:0] res
);
    // 组合逻辑，直接相加
    assign res = a + b;
endmodule
