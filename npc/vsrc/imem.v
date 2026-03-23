module imem(
    input  [31:0] addr,
    output reg [31:0] inst
);
    // 引入 DPI-C 函数
    import "DPI-C" function int pmem_read(input int raddr);

    // 取指逻辑：总是读取按 4 字节对齐的地址
    always @(*) begin
        inst = pmem_read(addr);
    end

endmodule
