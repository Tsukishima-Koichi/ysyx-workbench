`timescale 1ns / 1ps

module ForwardingUnit(
    // 来自 ID 阶段 (正在译码的当前指令)
    input  logic [4:0] id_rs1,
    input  logic [4:0] id_rs2,
    
    // 来自 EX 阶段 (上一条指令，下一拍它将进入 MEM 阶段)
    input  logic       ex_RegWen,
    input  logic [4:0] ex_rd,
    
    // 来自 MEM 阶段 (上上一条指令，下一拍它将进入 WB 阶段)
    input  logic       mem_RegWen,
    input  logic [4:0] mem_rd,
    
    // 提前算好的转发控制信号 (将存入 ID/EX 流水线寄存器)
    output logic [1:0] id_forward_A,
    output logic [1:0] id_forward_B
);

    always_comb begin
        // =====================================
        // Forward A (针对 rs1)
        // =====================================
        // 预测优先级 1：下一拍从 MEM 阶段拿数据
        if (ex_RegWen && (ex_rd != 5'b0) && (ex_rd == id_rs1)) begin
            id_forward_A = 2'b10;
        end
        // 预测优先级 2：下一拍从 WB 阶段拿数据
        else if (mem_RegWen && (mem_rd != 5'b0) && (mem_rd == id_rs1)) begin
            id_forward_A = 2'b01;
        end
        else begin
            id_forward_A = 2'b00;
        end

        // =====================================
        // Forward B (针对 rs2)
        // =====================================
        if (ex_RegWen && (ex_rd != 5'b0) && (ex_rd == id_rs2)) begin
            id_forward_B = 2'b10;
        end
        else if (mem_RegWen && (mem_rd != 5'b0) && (mem_rd == id_rs2)) begin
            id_forward_B = 2'b01;
        end
        else begin
            id_forward_B = 2'b00;
        end
    end

endmodule
