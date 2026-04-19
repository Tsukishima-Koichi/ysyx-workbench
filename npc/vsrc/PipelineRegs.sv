`timescale 1ns / 1ps

// ==========================================
// 1. IF1/IF2 Pipeline Register (🌟 新增)
// ==========================================
module IF1_IF2_Reg #(parameter DATAWIDTH = 32)(
    input  logic clk, rst, flush, stall,
    input  logic [DATAWIDTH-1:0] if1_pc, 
    output logic [DATAWIDTH-1:0] if2_pc, 
    output logic                 if2_valid // 标识此指令没有被冲刷
);
    always_ff @(posedge clk) begin
        if (rst || flush) begin
            if2_pc    <= 0;
            if2_valid <= 1'b0;
        end else if (!stall) begin
            if2_pc    <= if1_pc;
            if2_valid <= 1'b1;
        end
    end
endmodule

// ==========================================
// 2. IF2/ID Pipeline Register (原 IF_ID_Reg 修改)
// ==========================================
module IF2_ID_Reg #(parameter DATAWIDTH = 32)(
    input  logic clk, rst, flush, stall,
    input  logic [DATAWIDTH-1:0] if2_pc, 
    input  logic [DATAWIDTH-1:0] if2_inst, // 新增：锁存取到的指令
    input  logic                 if2_valid,
    output logic [DATAWIDTH-1:0] id_pc, 
    output logic [DATAWIDTH-1:0] id_inst_raw,
    output logic                 id_valid 
);
    always_ff @(posedge clk) begin
        if (rst || flush) begin
            id_pc       <= 0;
            id_inst_raw <= 0;
            id_valid    <= 1'b0;
        end else if (!stall) begin
            id_pc       <= if2_pc;
            id_inst_raw <= if2_inst;
            id_valid    <= if2_valid;
        end
    end
endmodule

// ==========================================
// 3. ID/EX Pipeline Register
// ==========================================
module ID_EX_Reg #(parameter DATAWIDTH = 32)(
    input  logic clk, rst, flush, stall,
    
    // Data
    input  logic [DATAWIDTH-1:0] id_pc, id_rs1_data, id_rs2_data, id_imm, id_ret_pc,
    input  logic [4:0]           id_rd, id_rs1, id_rs2,
    
    // Control
    input  logic       id_RegWen, id_MemWen, id_IsBranch, id_AluSrcB,
    input  logic [1:0] id_JmpType, id_WbSel, id_AluSrcA,
    input  logic [3:0] id_alu_ctrl,
    input  logic [2:0] id_funct3,
    
    input  logic [1:0] id_forward_A, id_forward_B, // <--- 新增：接收预计算的前递信号
    input  logic [DATAWIDTH-1:0] id_branch_target, // <--- 新增：接收 ID 阶段算好的分支目标地址

    // CSR
    input  logic [11:0] id_csr_idx,
    input  logic        id_CsrWen, id_CsrImmSel, id_IsEcall, id_IsEbreak, id_IsMret,
    input  logic [1:0]  id_CsrOp,
    
    // Outputs
    output logic [DATAWIDTH-1:0] ex_pc, ex_rs1_data, ex_rs2_data, ex_imm, ex_ret_pc,
    output logic [4:0]           ex_rd, ex_rs1, ex_rs2,
    output logic       ex_RegWen, ex_MemWen, ex_IsBranch, ex_AluSrcB,
    output logic [1:0] ex_JmpType, ex_WbSel, ex_AluSrcA,
    output logic [3:0] ex_alu_ctrl,
    output logic [2:0] ex_funct3,
    
    output logic [1:0] ex_forward_A, ex_forward_B, // <--- 新增：输出给 EX 阶段
    output logic [DATAWIDTH-1:0] ex_branch_target, // <--- 新增：输出给 EX 阶段

    // CSR
    output logic [11:0] ex_csr_idx,
    output logic        ex_CsrWen, ex_CsrImmSel, ex_IsEcall, ex_IsEbreak, ex_IsMret,
    output logic [1:0]  ex_CsrOp
);
    always_ff @(posedge clk) begin
        if (rst || flush) begin
            {ex_pc, ex_rs1_data, ex_rs2_data, ex_imm, ex_ret_pc} <= 0;
            {ex_rd, ex_rs1, ex_rs2} <= 0;
            {ex_RegWen, ex_MemWen, ex_IsBranch, ex_AluSrcB} <= 0;
            {ex_JmpType, ex_WbSel, ex_AluSrcA} <= 0;
            ex_alu_ctrl <= 0;
            ex_funct3   <= 0;
            {ex_forward_A, ex_forward_B} <= 0; // <--- 新增：复位清零
            {ex_csr_idx, ex_CsrWen, ex_CsrImmSel, ex_IsEcall, ex_IsEbreak, ex_IsMret, ex_CsrOp} <= 0;
            ex_branch_target <= 0; // 冲刷时清零
        end else if (!stall) begin
            {ex_pc, ex_rs1_data, ex_rs2_data, ex_imm, ex_ret_pc} <= {id_pc, id_rs1_data, id_rs2_data, id_imm, id_ret_pc};
            {ex_rd, ex_rs1, ex_rs2} <= {id_rd, id_rs1, id_rs2};
            {ex_RegWen, ex_MemWen, ex_IsBranch, ex_AluSrcB} <= {id_RegWen, id_MemWen, id_IsBranch, id_AluSrcB};
            {ex_JmpType, ex_WbSel, ex_AluSrcA} <= {id_JmpType, id_WbSel, id_AluSrcA};
            ex_alu_ctrl <= id_alu_ctrl;
            ex_funct3   <= id_funct3;
            {ex_forward_A, ex_forward_B} <= {id_forward_A, id_forward_B}; // <--- 新增：流水传递
            {ex_csr_idx, ex_CsrWen, ex_CsrImmSel, ex_IsEcall, ex_IsEbreak, ex_IsMret, ex_CsrOp} <=
                {id_csr_idx, id_CsrWen, id_CsrImmSel, id_IsEcall, id_IsEbreak, id_IsMret, id_CsrOp};
            ex_branch_target <= id_branch_target; // 流水传递
        end
    end
endmodule

// ==========================================
// 4. EX/MEM Pipeline Register
// ==========================================
module EX_MEM_Reg #(parameter DATAWIDTH = 32)(
    input  logic clk, rst, flush, stall,
    
    input  logic [DATAWIDTH-1:0] ex_alu_res, ex_rs2_data, ex_ret_pc,
    input  logic [DATAWIDTH-1:0] ex_agu_res, // <--- 新增：接收 AGU 算出的地址
    input  logic [4:0]           ex_rd,
    input  logic                 ex_RegWen, ex_MemWen,
    input  logic [1:0]           ex_WbSel,
    input  logic [2:0]           ex_funct3,
    input  logic [DATAWIDTH-1:0] ex_csr_rdata,
    
    output logic [DATAWIDTH-1:0] mem_alu_res, mem_rs2_data, mem_ret_pc,
    output logic [DATAWIDTH-1:0] mem_agu_res, // <--- 新增：输出给 MEM 阶段使用
    output logic [4:0]           mem_rd,
    output logic                 mem_RegWen, mem_MemWen,
    output logic [1:0]           mem_WbSel,
    output logic [2:0]           mem_funct3,
    output logic [DATAWIDTH-1:0] mem_csr_rdata
);
    always_ff @(posedge clk) begin
        if (rst || flush) begin
            {mem_alu_res, mem_rs2_data, mem_ret_pc, mem_agu_res} <= 0; // <--- 加上 mem_agu_res
            mem_rd <= 0;
            {mem_RegWen, mem_MemWen} <= 0;
            mem_WbSel <= 0;
            mem_funct3 <= 0;
            mem_csr_rdata <= 0;
        end else if (!stall) begin
            {mem_alu_res, mem_rs2_data, mem_ret_pc, mem_agu_res} <= {ex_alu_res, ex_rs2_data, ex_ret_pc, ex_agu_res}; // <--- 加上 AGU 传递
            mem_rd <= ex_rd;
            {mem_RegWen, mem_MemWen} <= {ex_RegWen, ex_MemWen};
            mem_WbSel <= ex_WbSel;
            mem_funct3 <= ex_funct3;
            mem_csr_rdata <= ex_csr_rdata;
        end
    end
endmodule

// ==========================================
// 5. MEM/WB Pipeline Register
// ==========================================
module MEM_WB_Reg #(parameter DATAWIDTH = 32)(
    input  logic clk, rst, flush, stall,

    input  logic [DATAWIDTH-1:0] mem_alu_res, mem_ret_pc,
    input  logic [DATAWIDTH-1:0] mem_agu_res, // 🌟 传递 AGU 地址
    input  logic [2:0]           mem_funct3,  // 🌟 传递 Mask 配置
    input  logic [4:0]           mem_rd,
    input  logic                 mem_RegWen,
    input  logic [1:0]           mem_WbSel,
    input  logic [DATAWIDTH-1:0] mem_csr_rdata,

    output logic [DATAWIDTH-1:0] wb_alu_res, wb_ret_pc,
    output logic [DATAWIDTH-1:0] wb_agu_res,  // 🌟 输出
    output logic [2:0]           wb_funct3,   // 🌟 输出
    output logic [4:0]           wb_rd,
    output logic                 wb_RegWen,
    output logic [1:0]           wb_WbSel,
    output logic [DATAWIDTH-1:0] wb_csr_rdata
);
    always_ff @(posedge clk) begin
        if (rst || flush) begin
            {wb_alu_res, wb_ret_pc, wb_agu_res} <= 0;
            wb_funct3 <= 0;
            wb_rd <= 0;
            wb_RegWen <= 0;
            wb_WbSel <= 0;
            wb_csr_rdata <= 0;
        end else if (!stall) begin
            {wb_alu_res, wb_ret_pc, wb_agu_res} <= {mem_alu_res, mem_ret_pc, mem_agu_res};
            wb_funct3 <= mem_funct3;
            wb_rd <= mem_rd;
            wb_RegWen <= mem_RegWen;
            wb_WbSel <= mem_WbSel;
            wb_csr_rdata <= mem_csr_rdata;
        end
    end
endmodule
