`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/05/08 12:42:16
// Design Name: 
// Module Name: RF
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module RF #(
    parameter   ADDR_WIDTH = 5  ,
    parameter   DATAWIDTH  = 32
)(
    input  logic                    clk            ,
    input  logic                    rst            ,
    // Write rd                   
    input  logic                    wen      ,
    input  logic [ADDR_WIDTH - 1:0] waddr    ,
    input  logic [DATAWIDTH - 1:0]  wdata       ,
    // Read  rs1 rs2
    input  logic [ADDR_WIDTH - 1:0] rR1   ,
    input  logic [ADDR_WIDTH - 1:0] rR2   ,

    output logic [DATAWIDTH - 1:0]  rR1_data  ,
    output logic [DATAWIDTH - 1:0]  rR2_data
);
    logic [DATAWIDTH - 1:0] reg_bank [31:0];

    always_ff @(posedge clk) begin
        if (rst) begin
            for (int i = 0; i < 32; i ++) begin
                reg_bank[i] <= 0;
            end
        end
        else if (wen & (waddr != 5'd0)) begin
            reg_bank[waddr] <= wdata;
        end
    end

    assign rR1_data = (wen && waddr != 5'd0 && waddr == rR1) ? wdata : reg_bank[rR1];
    assign rR2_data = (wen && waddr != 5'd0 && waddr == rR2) ? wdata : reg_bank[rR2];

    // ========================================================
    // 🌟 核心新增：DPI-C 接口对接
    // ========================================================
    
    // 1. 导入 C++ 中的上下文捕获函数
    // 注意：因为 C++ 内部调用了 svGetScope()，所以必须加 context 关键字！
    import "DPI-C" context function void set_regfile_scope();

    // 2. 导出 SV 中的读寄存器函数给 C++ 使用
    export "DPI-C" function get_gpr;

    // 3. 实现读取逻辑：根据索引返回对应寄存器的值
    function int get_gpr(input int idx);
        if (idx == 0) begin
            return 0; // x0 永远为 0
        end else begin
            return reg_bank[idx];
        end
    endfunction

    // 4. 在仿真开始的第 0 时刻，主动告诉 C++ 自己(RF)所在的位置
    initial begin
        set_regfile_scope();
    end

endmodule
