`timescale 1ns / 1ps
`include "defines.sv"

module HazardDetectionUnit(
    // 来自 ID 阶段 (当前译码的指令)
    input  logic [4:0] id_rs1,
    input  logic [4:0] id_rs2,
    input  logic [6:0] id_opcode,
    
    // 来自 EX 阶段 (上一条指令)
    input  logic       ex_RegWen,
    input  logic [1:0] ex_WbSel, // 2'b10 表示 Load
    input  logic [4:0] ex_rd,
    
    // 来自 MEM 阶段 (上上一条指令) - 保留端口以兼容 myCPU 顶层例化
    input  logic [1:0] mem_WbSel, 
    input  logic [4:0] mem_rd,
    
    // 输出控制信号
    output logic       stall_IF,
    output logic       stall_ID,
    output logic       flush_ID_EX
);

    logic rs1_read, rs2_read;
    logic is_load_use;

    // ========================================================
    // 1. 判断当前 ID 阶段指令是否真的需要读取 rs1 和 rs2
    // ========================================================
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

    // ========================================================
    // 2. 经典的 Load-Use 冒险检测
    // ========================================================
    // 规则: 如果上一条指令 (正处于 EX 阶段) 是 Load，且当前指令需要用它的目标寄存器。
    // 因为 Load 的数据必须等到 WB 阶段才能出 BRAM/总线，即使有前递网络，
    // 也必须停顿 (Stall) 一拍，等 Load 进入 MEM 阶段后再流转。
    always_comb begin
        is_load_use = 1'b0;
        
        if ((ex_WbSel == 2'b10) && (ex_rd != 5'd0)) begin
            if ((rs1_read && (ex_rd == id_rs1)) || (rs2_read && (ex_rd == id_rs2))) begin
                is_load_use = 1'b1;
            end
        end
    end

    // ========================================================
    // 3. 综合 Stall 逻辑
    // ========================================================
    // 说明：分支判断已移入 EX 阶段，因此 Branch 指令视同普通运算指令，
    // 仅依赖上述的 Load-Use 停顿即可，不再需要额外的 branch_hazard 检查！
    
    assign stall_IF    = is_load_use;
    assign stall_ID    = is_load_use;
    assign flush_ID_EX = is_load_use;

endmodule
