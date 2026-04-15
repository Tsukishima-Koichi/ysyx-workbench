`timescale 1ns / 1ps

module ForwardingUnit(
    // 来自 EX 阶段 (当前正在使用 ALU 的指令)
    input  logic [4:0] ex_rs1,
    input  logic [4:0] ex_rs2,
    
    // 来自 MEM 阶段 (上一条指令)
    input  logic       mem_RegWen,
    input  logic [4:0] mem_rd,
    
    // 来自 WB 阶段 (上上条指令)
    input  logic       wb_RegWen,
    input  logic [4:0] wb_rd,
    
    // 转发控制信号输出
    output logic [1:0] forward_A, // 控制 rs1 的多路选择器
    output logic [1:0] forward_B  // 控制 rs2 的多路选择器
);

    always_comb begin
        // =====================================
        // Forward A (针对 rs1)
        // =====================================
        // 优先级 1：EX 冒险（上一条指令刚好算完，且目标寄存器就是我需要的）
        if (mem_RegWen && (mem_rd != 5'b0) && (mem_rd == ex_rs1)) begin
            forward_A = 2'b10;
        end
        // 优先级 2：MEM 冒险（上上条指令算完准备写回，且是我需要的）
        else if (wb_RegWen && (wb_rd != 5'b0) && (wb_rd == ex_rs1)) begin
            forward_A = 2'b01;
        end
        // 默认：没有冒险，使用 ID 阶段读出的老老实实的数据
        else begin
            forward_A = 2'b00;
        end

        // =====================================
        // Forward B (针对 rs2)
        // =====================================
        if (mem_RegWen && (mem_rd != 5'b0) && (mem_rd == ex_rs2)) begin
            forward_B = 2'b10;
        end
        else if (wb_RegWen && (wb_rd != 5'b0) && (wb_rd == ex_rs2)) begin
            forward_B = 2'b01;
        end
        else begin
            forward_B = 2'b00;
        end
    end

endmodule
