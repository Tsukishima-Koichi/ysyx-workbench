// vsrc/cpu.sv
`timescale 1ns / 1ps

// 导入 C++ 中的内存读写函数
import "DPI-C" context function int pmem_read(input int raddr);
import "DPI-C" context function void pmem_write(input int waddr, input int wdata, input byte wmask);

module cpu(
    input logic clk,
    input logic rst,

    output logic [31:0] pc,
    output logic [31:0] inst,
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
    // 修改为 myCPU 中实际存在的信号，此处暴露 EX 阶段因为 ebreak 也是在 EX 判定的
    assign pc       = u_myCPU.ex_pc;       
    assign inst     = u_myCPU.id_inst;     
    assign halt_req = u_myCPU.ex_IsEbreak;

endmodule
