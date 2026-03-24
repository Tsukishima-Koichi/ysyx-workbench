module dmem(
    input         clk,
    input  [3:0]  wmask,   // 【新引入】完美的 4 位写掩码！(0000表示不写，相当于原来的 wen=0)
    /* verilator lint_off UNUSEDSIGNAL */
    input  [31:0] addr,    // 访存地址
    /* verilator lint_on UNUSEDSIGNAL */
    input  [31:0] wdata,   // 已经对齐并铺满的写入数据
    output [31:0] rdata    // 原封不动吐出 32 位，让 CPU 去切
);

    // 引入 DPI-C 读写函数
    import "DPI-C" function int  pmem_read(input int raddr);
    import "DPI-C" function void pmem_write(input int waddr, input int wdata, input byte wmask_c);

    // 核心安全机制：强制地址按 4 字节对齐
    // CPU 可能会传来奇数地址 (比如 0x80000001)，但在硬件 SRAM 和 C++ 数组里，
    // 我们总是按 32 位 (字) 边界去读取一整块。
    wire [31:0] aligned_addr = {addr[31:2], 2'b00}; // 强行把最低两位置 0

    // =======================================
    // 1. 读逻辑 (组合逻辑)
    // =======================================
    // 内存不管三七二十一，直接把这 4 个字节全读出来扔给 CPU
    // CPU 里的 final_mem_rdata 选择器会负责把它切成 8 位或 16 位
    assign rdata = pmem_read(aligned_addr);

    // =======================================
    // 2. 写逻辑 (时序逻辑，在时钟上升沿生效)
    // =======================================
    // 只要 wmask 不是 0，就说明有字节需要写入
    always @(posedge clk) begin
        if (wmask != 4'b0000) begin
            // 注意：DPI-C 要求 wmask_c 是 byte (8位)，我们把 4 位的 wmask 高位补 0 传给它
            pmem_write(aligned_addr, wdata, {4'b0000, wmask});
        end
    end

endmodule
