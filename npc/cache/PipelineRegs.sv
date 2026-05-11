`timescale 1ns / 1ps
`include "defines.sv"

// ==========================================
// 1. IF1/IF2 Pipeline Register
// ==========================================
module IF1_IF2_Reg #(parameter DATAWIDTH = 32)(
    input  logic clk, rst, flush, stall,
    input  logic [DATAWIDTH-1:0] if1_pc, 
    output logic [DATAWIDTH-1:0] if2_pc, 
    output logic                 if2_valid // 标识此指令没有被冲刷
);
    // 🌟 控制通路
    always_ff @(posedge clk) begin
        if (rst) begin
            if2_valid <= 1'b0;
        end else if (flush) begin
            if2_valid <= 1'b0;
        end else if (!stall) begin
            if2_valid <= 1'b1;
        end
    end

    // 🌟 数据通路
    always_ff @(posedge clk) begin
        if (!stall) begin
            if2_pc <= if1_pc;
        end
    end
endmodule

// ==========================================
// 2. IF2/ID Pipeline Register
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
    // 🌟 控制通路
    always_ff @(posedge clk) begin
        if (rst) begin
            id_valid <= 1'b0;
        end else if (flush) begin
            id_valid <= 1'b0;
        end else if (!stall) begin
            id_valid <= if2_valid;
        end
    end

    // 🌟 数据通路
    always_ff @(posedge clk) begin
        if (!stall) begin
            id_pc       <= if2_pc;
            id_inst_raw <= if2_inst;
        end
    end
endmodule

// ==========================================
// 3. ID/EX Pipeline Register (保持你之前的修改)
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
    input  logic [1:0] id_forward_A, id_forward_B, 
    input  logic [DATAWIDTH-1:0] id_branch_target, 

    // CSR
    input  logic [11:0] id_csr_idx,
    input  logic        id_CsrWen, id_CsrImmSel, id_IsEcall, id_IsEbreak, id_IsMret,
    input  logic [1:0]  id_CsrOp,

    input  logic                 id_valid,  // 🌟 2. 新增：传入指令有效信号
    
    `ifdef NPC_TEST
    input  logic [DATAWIDTH-1:0] id_inst,   // 🌟 1. 新增：传入指令机器码
    output logic [DATAWIDTH-1:0] ex_inst,   // 🌟 3. 新增：传出指令机器码
    `endif

    output logic                 ex_valid,  // 🌟 4. 新增：传出指令有效信号

    // Outputs
    output logic [DATAWIDTH-1:0] ex_pc, ex_rs1_data, ex_rs2_data, ex_imm, ex_ret_pc,
    output logic [4:0]           ex_rd, ex_rs1, ex_rs2,
    output logic       ex_RegWen, ex_MemWen, ex_IsBranch, ex_AluSrcB,
    output logic [1:0] ex_JmpType, ex_WbSel, ex_AluSrcA,
    output logic [3:0] ex_alu_ctrl,
    output logic [2:0] ex_funct3,
    output logic [1:0] ex_forward_A, ex_forward_B,
    output logic [DATAWIDTH-1:0] ex_branch_target,

    // CSR
    output logic [11:0] ex_csr_idx,
    output logic        ex_CsrWen, ex_CsrImmSel, ex_IsEcall, ex_IsEbreak, ex_IsMret,
    output logic [1:0]  ex_CsrOp
);
    // 🌟 1. 控制通路 (Control Path)
    always_ff @(posedge clk) begin
        if (rst) begin
            ex_rd <= 0;
            {ex_RegWen, ex_MemWen, ex_IsBranch, ex_AluSrcB} <= 0;
            {ex_JmpType, ex_WbSel, ex_AluSrcA} <= 0;
            ex_CsrWen <= 0; 
            {ex_IsEcall, ex_IsEbreak, ex_IsMret} <= 0;
            ex_CsrOp <= 0;
            ex_valid <= 1'b0;  // 🌟 复位时清零
        end else if (flush) begin
            ex_rd <= 0;
            {ex_RegWen, ex_MemWen, ex_IsBranch, ex_AluSrcB} <= 0;
            {ex_JmpType, ex_WbSel, ex_AluSrcA} <= 0;
            ex_CsrWen <= 0;
            {ex_IsEcall, ex_IsEbreak, ex_IsMret} <= 0;
            ex_CsrOp <= 0;
            ex_valid <= 1'b0;  // 🌟 冲刷流水线时，将指令标为无效(气泡)
        end else if (!stall) begin
            ex_rd <= id_rd;
            {ex_RegWen, ex_MemWen, ex_IsBranch, ex_AluSrcB} <= {id_RegWen, id_MemWen, id_IsBranch, id_AluSrcB};
            {ex_JmpType, ex_WbSel, ex_AluSrcA} <= {id_JmpType, id_WbSel, id_AluSrcA};
            ex_CsrWen <= id_CsrWen;
            {ex_IsEcall, ex_IsEbreak, ex_IsMret} <= {id_IsEcall, id_IsEbreak, id_IsMret};
            ex_CsrOp <= id_CsrOp;
            ex_valid <= id_valid; // 🌟 正常运行时，传递有效信号
        end
    end

    // 🌟 2. 数据通路 (Data Path)
    always_ff @(posedge clk) begin
        if (!stall) begin 
            {ex_pc, ex_rs1_data, ex_rs2_data, ex_imm, ex_ret_pc} <= {id_pc, id_rs1_data, id_rs2_data, id_imm, id_ret_pc};
            {ex_rs1, ex_rs2} <= {id_rs1, id_rs2};
            ex_alu_ctrl <= id_alu_ctrl;
            ex_funct3   <= id_funct3;
            {ex_forward_A, ex_forward_B} <= {id_forward_A, id_forward_B};
            ex_csr_idx <= id_csr_idx;
            ex_CsrImmSel <= id_CsrImmSel;
            ex_branch_target <= id_branch_target;

            `ifdef NPC_TEST
            ex_inst <= id_inst; // 🌟 顺着流水线打一拍把机器码传下去
            `endif
        end
    end
endmodule

// ==========================================
// 4. EX/MEM1 Pipeline Register
// ==========================================
module EX_MEM1_Reg #(parameter DATAWIDTH = 32)(
    input  logic clk, rst, flush, stall,
    input  logic [DATAWIDTH-1:0] ex_alu_res, ex_rs2_data, ex_ret_pc, ex_agu_res, ex_csr_rdata,
    input  logic [4:0]           ex_rd,
    input  logic                 ex_RegWen, ex_MemWen,
    input  logic [1:0]           ex_WbSel,
    input  logic [2:0]           ex_funct3,
    input  logic [DATAWIDTH-1:0] ex_fw_data,
    
    output logic [DATAWIDTH-1:0] mem1_alu_res, mem1_rs2_data, mem1_ret_pc, mem1_agu_res, mem1_csr_rdata,
    output logic [4:0]           mem1_rd,
    output logic                 mem1_RegWen, mem1_MemWen,
    output logic [1:0]           mem1_WbSel,
    output logic [2:0]           mem1_funct3,
    output logic [DATAWIDTH-1:0] mem1_fw_data
);

    always_ff @(posedge clk) begin
        if (rst) begin
            mem1_rd <= 0;
            {mem1_RegWen, mem1_MemWen} <= 0;
            mem1_WbSel <= 0;
        end else if (flush) begin
            mem1_rd <= 0;
            {mem1_RegWen, mem1_MemWen} <= 0;
            mem1_WbSel <= 0;
        end else if (!stall) begin
            mem1_rd <= ex_rd;
            {mem1_RegWen, mem1_MemWen} <= {ex_RegWen, ex_MemWen};
            mem1_WbSel <= ex_WbSel;
        end
    end


    always_ff @(posedge clk) begin
        if (!stall) begin
            {mem1_alu_res, mem1_rs2_data, mem1_ret_pc, mem1_agu_res, mem1_csr_rdata} <= 
            {ex_alu_res,   ex_rs2_data,   ex_ret_pc,   ex_agu_res,   ex_csr_rdata};
            mem1_funct3 <= ex_funct3;
            mem1_fw_data <= ex_fw_data;
        end
    end
endmodule

// ==========================================
// 5. MEM1/MEM2 Pipeline Register 
// ==========================================
module MEM1_MEM2_Reg #(parameter DATAWIDTH = 32)(
    input  logic clk, rst, flush, stall,
    input  logic [DATAWIDTH-1:0] mem1_alu_res, mem1_agu_res, mem1_ret_pc, mem1_csr_rdata,
    input  logic [4:0]           mem1_rd,
    input  logic                 mem1_RegWen,
    input  logic [1:0]           mem1_WbSel,
    input  logic [2:0]           mem1_funct3,
    input  logic [DATAWIDTH-1:0] mem1_fw_data,  // 🌟 新增：接收

    output logic [DATAWIDTH-1:0] mem2_alu_res, mem2_agu_res, mem2_ret_pc, mem2_csr_rdata,
    output logic [4:0]           mem2_rd,
    output logic                 mem2_RegWen,
    output logic [1:0]           mem2_WbSel,
    output logic [2:0]           mem2_funct3,
    output logic [DATAWIDTH-1:0] mem2_fw_data   // 🌟 新增：传出给前递网络
);

    // 🌟 控制通路
    always_ff @(posedge clk) begin
        if (rst) begin
            mem2_rd <= 0; 
            mem2_RegWen <= 0; 
            mem2_WbSel <= 0; 
        end else if (flush) begin
            mem2_rd <= 0; 
            mem2_RegWen <= 0; 
            mem2_WbSel <= 0; 
        end else if (!stall) begin
            mem2_rd <= mem1_rd; 
            mem2_RegWen <= mem1_RegWen; 
            mem2_WbSel <= mem1_WbSel; 
        end
    end

    // 🌟 数据通路
    always_ff @(posedge clk) begin
        if (!stall) begin
            {mem2_alu_res, mem2_agu_res, mem2_ret_pc, mem2_csr_rdata} <= 
            {mem1_alu_res, mem1_agu_res, mem1_ret_pc, mem1_csr_rdata};
            mem2_funct3 <= mem1_funct3;
            mem2_fw_data <= mem1_fw_data;       // 🌟 新增：顺着流水线拍下去
        end
    end
endmodule

// ==========================================
// 6. MEM2/WB Pipeline Register
// ==========================================
module MEM2_WB_Reg #(parameter DATAWIDTH = 32)(
    input  logic clk, rst, flush, stall,
    input  logic [DATAWIDTH-1:0] mem2_non_load_data, // 提前算好的非 Load 数据
    input  logic [DATAWIDTH-1:0] mem2_perip_rdata,   // 原始的 BRAM 读出数据
    input  logic [1:0]           mem2_agu_res_1_0,   // 地址低两位
    input  logic [2:0]           mem2_funct3,        // funct3
    input  logic [1:0]           mem2_WbSel,         // 写回选择
    input  logic [4:0]           mem2_rd,
    input  logic                 mem2_RegWen,

    output logic [DATAWIDTH-1:0] wb_non_load_data,
    output logic [DATAWIDTH-1:0] wb_perip_rdata,
    output logic [1:0]           wb_agu_res_1_0,
    // 🌟 极端压低扇出，逼迫工具为每一个字节扩展路径单独复制触发器
    (* MAX_FANOUT = "4" *) output logic [2:0]           wb_funct3,
    (* MAX_FANOUT = "4" *) output logic [1:0]           wb_WbSel,
    output logic [4:0]           wb_rd,
    output logic                 wb_RegWen
);
    // 🌟 控制通路
    always_ff @(posedge clk) begin
        if (rst) begin
            wb_rd <= 0;
            wb_RegWen <= 0;
            wb_WbSel <= 0;
        end else if (flush) begin
            wb_rd <= 0;
            wb_RegWen <= 0;
            wb_WbSel <= 0;
        end else if (!stall) begin
            wb_rd <= mem2_rd;
            wb_RegWen <= mem2_RegWen;
            wb_WbSel <= mem2_WbSel;
        end
    end

    // 🌟 数据通路
    always_ff @(posedge clk) begin
        if (!stall) begin
            wb_non_load_data <= mem2_non_load_data;
            wb_perip_rdata   <= mem2_perip_rdata;
            wb_agu_res_1_0   <= mem2_agu_res_1_0;
            wb_funct3        <= mem2_funct3;
        end
    end
endmodule
