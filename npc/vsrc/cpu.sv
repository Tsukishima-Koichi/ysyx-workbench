// vsrc/cpu.sv
`timescale 1ns / 1ps
`include "defines.sv"

// 导入 C++ 中的内存读写函数
import "DPI-C" context function int pmem_read(input int raddr);
import "DPI-C" context function void pmem_write(input int waddr, input int wdata, input byte wmask);

module cpu(
    input logic clk,
    input logic rst,

    output logic [31:0] pc,
    output logic [31:0] inst,
    output logic        halt_req,
    output logic        dead_loop
);
    // 线缆声明
    logic [31:0] irom_addr;
    logic [31:0] irom_data;
    
    logic [31:0] perip_addr;
    logic        perip_wen;
    logic [ 3:0] perip_mask;
    logic [31:0] perip_wdata;
    logic [31:0] perip_rdata;

    // 例化核心流水线
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

    // ====================================================
    // 🌟 核心修复 1：BRAM 读特性模拟 (打一拍地址，延迟一周期出数据)
    // ====================================================
    logic [31:0] irom_addr_reg;
    logic [31:0] perip_addr_reg;

    always_ff @(posedge clk) begin
        if (rst) begin
            irom_addr_reg  <= 32'h8000_0000;
            perip_addr_reg <= 32'h0000_0000;
        end else begin
            // 在时钟上升沿锁存 CPU 发出的地址
            irom_addr_reg  <= irom_addr;
            perip_addr_reg <= perip_addr;
        end
    end

    // 组合逻辑根据锁存的地址向 C++ 读取数据
    // 这样在外部看来，当前周期的 data 其实是上一周期地址的内容，完美契合 BRAM！
    always_comb begin
        irom_data   = pmem_read(irom_addr_reg);
        perip_rdata = pmem_read(perip_addr_reg);
    end

    // ====================================================
    // 🌟 核心修复 2：BRAM 写特性模拟 (同步写入)
    // ====================================================
    always_ff @(posedge clk) begin
        if (!rst && perip_wen) begin
            // 在时钟上升沿且写使能时，调用 C++ 写入数据
            pmem_write(perip_addr, perip_wdata, {4'b0, perip_mask});
        end
    end
    
    // ====================================================
    // 🌟 核心修复 3：修复 myCPU 内部信号引用错误及测试探针
    // ====================================================
    assign pc       = u_myCPU.ex_pc;
    assign inst     = u_myCPU.id_inst;     
    assign halt_req = u_myCPU.ex_IsEbreak;

    // 🌟 新增：精准检测程序是否正常结束
    // 条件：1. 处于 EX 阶段的 PC 为 0x80000010
    //       2. EX 阶段的指令是有效的 JAL 指令 (JmpType == 2'b01) 
    //          因为流水线 flush 时会将 ex_JmpType 清零，所以此判断免疫流水线气泡
    assign dead_loop = (u_myCPU.ex_pc == 32'h8000_0010) && (u_myCPU.ex_JmpType == 2'b01);

    // ====================================================
    // 🌟 打印标准的 Spike 格式 Trace 日志
    // ====================================================
    `ifdef TRACE_TEST
    always_ff @(posedge clk) begin
        if (!rst) begin
            // ⚠️ 必须判断 valid 信号！
            // 这样如果是由于分支预测失败导致流水线 Flush 产生的“气泡”，
            // 就不会被错误地打印出来了，完美匹配 Spike 只有真实执行指令的特性！
            if (u_myCPU.ex_valid) begin
                $display("core 0: 0x%08x (0x%08x)", u_myCPU.ex_pc, u_myCPU.ex_inst); 
            end
        end
    end
    `endif

endmodule
