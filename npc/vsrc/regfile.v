module regfile(
    input         clk,
    input  [4:0]  rs1,    // 读端口 1 的寄存器号
    input  [4:0]  rs2,    // 读端口 2 的寄存器号
    input  [4:0]  rd,     // 写端口的寄存器号
    input  [31:0] wdata,  // 要写入的数据
    input         wen,    // 写使能信号 (Write Enable)
    
    output [31:0] rs1_data,   // 读出的数据 1
    output [31:0] rs2_data    // 读出的数据 2
);
    // 定义 32 个 32 位的寄存器数组
    reg [31:0] rf [0:31];

    // ==================================================
    //  DPI-C 导出与作用域传递
    // ==================================================
    // 1. 导入一个带有 context（上下文）属性的 C 函数
    import "DPI-C" context function void set_regfile_scope();

    // 2. 仿真 0 时刻，主动把自己的作用域“递”给 C++
    initial begin
        set_regfile_scope();
    end

    // 3. 导出读取函数
    export "DPI-C" function get_gpr;

    // function int get_gpr(input int idx);
    //     get_gpr = rf[idx];
    // endfunction

    function int get_gpr;
        input int idx;
        begin
            // 注意：这里的 rf 是你寄存器二维数组的名字。
            // 如果你定义的数组叫 regs 或者 gpr，请把这里的 rf 替换成你的数组名！
            // 为了安全起见，x0 寄存器永远返回 0
            if (idx == 0) begin
                get_gpr = 0;
            end else begin
                get_gpr = rf[idx]; 
            end
        end
    endfunction
    // ==================================================

    // 初始化寄存器 (为了防止 Verilator 报 X 状态警告)
    integer i;
    initial begin
        for (i = 0; i < 32; i = i + 1) rf[i] = 32'b0;
    end

    // 写入逻辑 (时序逻辑，当时钟上升沿且允许写入，且写的不是 x0 时才写入)
    always @(posedge clk) begin
        if (wen && rd != 5'b0) begin
            rf[rd] <= wdata;
        end
    end

    // 读出逻辑 (组合逻辑，如果是 0 号寄存器直接输出 0，否则输出数组里的值)
    assign rs1_data = (rs1 == 5'b0) ? 32'b0 : rf[rs1];
    assign rs2_data = (rs2 == 5'b0) ? 32'b0 : rf[rs2];
endmodule
