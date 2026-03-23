module dmem(
    input         clk,
    input         wen,
    input         is_byte,
    input  [31:0] addr,
    input  [31:0] wdata,
    output reg [31:0] rdata
);
    // 引入 DPI-C 读写函数
    import "DPI-C" function int pmem_read(input int raddr);
    import "DPI-C" function void pmem_write(input int waddr, input int wdata, input byte wmask);

    // =======================================
    // 1. 读逻辑 (组合逻辑)
    // =======================================
    reg [31:0] read_word;
    reg [7:0]  read_byte;

    always @(*) begin
        // 找 C++ 要一整个字的数据 (4字节对齐)
        read_word = pmem_read(addr);
        
        // 从读出的字中抽出需要的字节 (处理 lbu)
        case (addr[1:0])
            2'b00: read_byte = read_word[7:0];
            2'b01: read_byte = read_word[15:8];  
            2'b10: read_byte = read_word[23:16]; 
            2'b11: read_byte = read_word[31:24];
        endcase
        rdata = is_byte ? {24'b0, read_byte} : read_word;
    end

    // =======================================
    // 2. 写逻辑 (时序逻辑，在时钟上升沿生效)
    // =======================================
    // 计算写掩码: 
    // 如果是 sb (写字节)，则根据地址低两位决定把 1 移到对应的位置
    // 如果是 sw (写字)，则掩码全为 1 (8'h0F，即 4'b1111)
    wire [7:0] wmask = is_byte ? (8'b00000001 << addr[1:0]) : 8'b00001111;
    
    // 数据对齐: 为了方便 C++ 按照 wmask 抓取，我们把低 8 位复制到所有 lane
    wire [31:0] aligned_wdata = is_byte ? {4{wdata[7:0]}} : wdata;

    always @(posedge clk) begin
        if (wen) begin
            // 只有出现写使能时，才真正呼叫 C++ 写入内存
            pmem_write(addr, aligned_wdata, wmask);
        end
    end

endmodule
