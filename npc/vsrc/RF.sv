`timescale 1ns / 1ps

// 1. 导入 C++ 中的作用域注册函数
import "DPI-C" context function void set_regfile_scope();

module RF #(
    parameter   ADDR_WIDTH = 5  ,
    parameter   DATAWIDTH  = 32
)(
    input  logic                    clk         ,
    input  logic                    rst         ,
    // Write rd                   
    input  logic                    wen         ,
    input  logic [ADDR_WIDTH - 1:0] waddr       ,
    input  logic [DATAWIDTH - 1:0]  wdata       ,
    // Read  rs1 rs2
    input  logic [ADDR_WIDTH - 1:0] rR1         ,
    input  logic [ADDR_WIDTH - 1:0] rR2         ,

    output logic [DATAWIDTH - 1:0]  rR1_data    ,
    output logic [DATAWIDTH - 1:0]  rR2_data
);
    logic [DATAWIDTH - 1:0] reg_bank [31:0];

    // ====================================================
    // 2. 导出获取通用寄存器的函数给 C++ 调用
    // ====================================================
    export "DPI-C" function get_gpr;
    function int get_gpr(input int idx);
        return reg_bank[idx];
    endfunction

    // 3. 在仿真刚开始时，调用 C++ 函数把当前的 scope 传过去
    initial begin
        set_regfile_scope();
    end
    // ====================================================

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

endmodule
