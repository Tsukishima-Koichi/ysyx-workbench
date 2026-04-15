`timescale 1ns / 1ps
`include "defines.sv"

module HazardDetectionUnit(
    // 来自 ID 阶段 (正在译码的指令)
    input  logic [4:0] id_rs1,
    input  logic [4:0] id_rs2,
    input  logic [6:0] id_opcode, // 当前指令的操作码
    
    // 来自 EX 阶段 (上一条指令)
    input  logic [1:0] ex_WbSel, // 判断是否是 Load 指令 (WbSel == 2'b10 表示从内存读)
    input  logic [4:0] ex_rd,    // 上一条指令的目标寄存器
    
    // 控制流水线停顿的输出
    output logic       stall_IF,
    output logic       stall_ID,
    output logic       flush_ID_EX
);

    logic is_load_use;
    logic rs1_read;
    logic rs2_read;

    // 🌟 核心修复：判断当前指令是否真的需要读取 rs1 和 rs2
    always_comb begin
        // 是否读取 rs1？
        case (id_opcode)
            // R型, I型(含算术和Load), JALR, S型(Store), B型(Branch), CSR 都需要读 rs1
            `R_TYPE, `I_TYPE, `IL_TYPE, `IJ_TYPE, `S_TYPE, `B_TYPE, `CSR_TYPE: 
                rs1_read = 1'b1;
            default: 
                rs1_read = 1'b0; // LUI, AUIPC, JAL 不读 rs1
        endcase

        // 是否读取 rs2？
        case (id_opcode)
            // R型, S型(Store), B型(Branch) 需要读 rs2
            `R_TYPE, `S_TYPE, `B_TYPE: 
                rs2_read = 1'b1;
            default: 
                rs2_read = 1'b0; // I型(含Load/JALR), U型, J型等 不读 rs2
        endcase
    end

    always_comb begin
        is_load_use = 1'b0;
        
        // 判断条件：
        // 1. 上一条指令是 Load (ex_WbSel == 2'b10)
        // 2. 目标寄存器不是 x0
        if ((ex_WbSel == 2'b10) && (ex_rd != 5'd0)) begin
            // 3. 🌟 只有在当前指令确实需要读取对应寄存器时，才触发冲突检测
            if ((rs1_read && (ex_rd == id_rs1)) || (rs2_read && (ex_rd == id_rs2))) begin
                is_load_use = 1'b1;
            end
        end
    end

    // 发生 Load-Use 冒险时：冻结 PC、冻结 IF/ID 阶段，并清空传入 EX 阶段的控制信号(塞气泡)
    assign stall_IF    = is_load_use;
    assign stall_ID    = is_load_use;
    assign flush_ID_EX = is_load_use;

endmodule
