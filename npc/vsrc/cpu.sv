// vsrc/cpu.sv
`timescale 1ns / 1ps

// 1. 导入 C++ 中的内存读写函数
import "DPI-C" context function int pmem_read(input int raddr);
import "DPI-C" context function void pmem_write(input int waddr, input int wdata, input byte wmask);

module cpu(
    input logic clk,
    input logic rst,

    output logic [31:0] pc,   // 🌟 变成输出端口
    output logic [31:0] inst, // 🌟 变成输出端口
    output logic        halt_req
);
    // 线缆声明
    logic [31:0] irom_addr;
    logic [31:0] irom_data;
    
    logic [31:0] perip_addr;
    logic        perip_wen;
    logic [ 3:0] perip_mask;
    logic [31:0] perip_wdata;
    logic [31:0] perip_rdata;

    // 2. 例化核心流水线
    myCPU u_myCPU (
        .cpu_rst      (rst),
        .cpu_clk      (clk),
        .irom_addr    (irom_addr),
        .irom_data    (irom_data),
        .perip_addr   (perip_addr),
        .perip_wen    (perip_wen),
        .perip_mask   (perip_mask),
        .perip_wdata  (perip_wdata),
        .perip_rdata  (perip_rdata)
    );

    // 3. 组合逻辑读 IROM (取指)
    // 直接映射到 C++ 侧的 pmem_read
    always_comb begin
        irom_data = pmem_read(irom_addr);
    end

    // 4. 组合逻辑读 DRAM / 外设 (访存)
    always_comb begin
        perip_rdata = pmem_read(perip_addr);
    end

    // 5. 核心修复：将写操作改为异步复位风格以匹配全局时序
    // 解决 SYNCASYNCNET 警告
    always_ff @(posedge clk) begin
        if (rst) begin
            // 复位时不执行写操作
        end else if (perip_wen) begin
            // 只有非复位且写使能有效时，调用 C++ 侧的 pmem_write
            // 拼接 wmask 以适配 C++ 的 char 类型
            pmem_write(perip_addr, perip_wdata, {4'b0, perip_mask});
        end
    end
    
    // 6. 暴露信号供 C++ main.cpp 停机判断使用

    // 使用跨层级引用获取 myCPU 内部的 PC 和指令信号
    // 这里的 if_pc 和 if_inst 对应 myCPU.sv 中的定义
    assign pc = u_myCPU.if_pc;     
    assign inst = u_myCPU.if_inst; 

    // 🌟 获取 EX 阶段确实执行了的 ebreak 信号 (由于在 EX 阶段，它已经逃过了分支冲刷)
    assign halt_req = u_myCPU.ex_IsEbreak;

endmodule

