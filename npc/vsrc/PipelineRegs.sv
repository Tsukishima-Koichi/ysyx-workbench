`timescale 1ns / 1ps
`include "defines.sv"

// ==============================================================================
// 前端 F-Block (Fetch & Predict)
// ==============================================================================

module F1_F2_Reg #(parameter DATAWIDTH = 32)(
    input  logic clk, rst, stall, poison,
    input  logic [DATAWIDTH-1:0] f1_pc_0, f1_pc_1,
    input  logic [DATAWIDTH-1:0] f1_inst_0, f1_inst_1,
    input  logic                 f1_nlp_hit,
    input  logic [DATAWIDTH-1:0] f1_nlp_target,
    output logic [DATAWIDTH-1:0] f2_pc_0, f2_pc_1,
    output logic [DATAWIDTH-1:0] f2_inst_0, f2_inst_1,
    output logic                 f2_valid,
    output logic                 f2_nlp_hit,
    output logic [DATAWIDTH-1:0] f2_nlp_target
);
    always_ff @(posedge clk) begin
        if (rst || poison) f2_valid <= 1'b0;
        else if (!stall)   f2_valid <= 1'b1;
    end
    always_ff @(posedge clk) begin
        if (!stall) begin
            f2_pc_0      <= f1_pc_0;
            f2_pc_1      <= f1_pc_1;
            f2_inst_0    <= f1_inst_0;
            f2_inst_1    <= f1_inst_1;
            f2_nlp_hit   <= f1_nlp_hit;
            f2_nlp_target <= f1_nlp_target;
        end
    end
endmodule

module F2_F3_Reg #(parameter DATAWIDTH = 32)(
    input  logic clk, rst, stall, poison,
    input  logic                 f2_valid,
    input  logic [DATAWIDTH-1:0] f2_pc_0, f2_pc_1,
    input  logic [DATAWIDTH-1:0] f2_inst_0, f2_inst_1,
    output logic                 f3_valid,
    output logic [DATAWIDTH-1:0] f3_pc_0, f3_pc_1,
    output logic [DATAWIDTH-1:0] f3_inst_0, f3_inst_1
);
    always_ff @(posedge clk) begin
        if (rst || poison) f3_valid <= 1'b0;
        else if (!stall)   f3_valid <= f2_valid;
    end
    always_ff @(posedge clk) begin
        if (!stall) begin
            {f3_pc_0, f3_pc_1}     <= {f2_pc_0, f2_pc_1};
            {f3_inst_0, f3_inst_1} <= {f2_inst_0, f2_inst_1};
        end
    end
endmodule

module F3_F4_Reg #(parameter DATAWIDTH = 32)(
    input  logic clk, rst, stall, poison,
    input  logic                 f3_valid,
    input  logic [DATAWIDTH-1:0] f3_pc_0, f3_pc_1, f3_inst_0, f3_inst_1,
    output logic                 f4_valid,
    output logic [DATAWIDTH-1:0] f4_pc_0, f4_pc_1, f4_inst_0, f4_inst_1
);
    always_ff @(posedge clk) begin
        if (rst || poison) f4_valid <= 1'b0;
        else if (!stall)   f4_valid <= f3_valid;
    end
    always_ff @(posedge clk) begin
        if (!stall) begin
            {f4_pc_0, f4_pc_1}     <= {f3_pc_0, f3_pc_1};
            {f4_inst_0, f4_inst_1} <= {f3_inst_0, f3_inst_1};
        end
    end
endmodule

module F4_F5_Reg #(parameter DATAWIDTH = 32)(
    input  logic clk, rst, stall, poison,
    input  logic                 f4_valid,
    input  logic [DATAWIDTH-1:0] f4_pc_0, f4_pc_1, f4_inst_0, f4_inst_1,
    input  logic                 f4_pred_taken_0, f4_pred_taken_1,
    input  logic [DATAWIDTH-1:0] f4_pred_tgt_0, f4_pred_tgt_1,
    input  logic                 f4_nlp_hit,
    input  logic [DATAWIDTH-1:0] f4_nlp_target,

    output logic                 f5_valid,
    output logic [DATAWIDTH-1:0] f5_pc_0, f5_pc_1, f5_inst_0, f5_inst_1,
    output logic                 f5_pred_taken_0, f5_pred_taken_1,
    output logic [DATAWIDTH-1:0] f5_pred_tgt_0, f5_pred_tgt_1,
    output logic                 f5_nlp_hit,
    output logic [DATAWIDTH-1:0] f5_nlp_target
);
    always_ff @(posedge clk) begin
        if (rst || poison) f5_valid <= 1'b0;
        else if (!stall)   f5_valid <= f4_valid;
    end
    always_ff @(posedge clk) begin
        if (!stall) begin
            {f5_pc_0, f5_pc_1}     <= {f4_pc_0, f4_pc_1};
            {f5_inst_0, f5_inst_1} <= {f4_inst_0, f4_inst_1};
            {f5_pred_taken_0, f5_pred_taken_1} <= {f4_pred_taken_0, f4_pred_taken_1};
            {f5_pred_tgt_0, f5_pred_tgt_1}     <= {f4_pred_tgt_0, f4_pred_tgt_1};
            f5_nlp_hit   <= f4_nlp_hit;
            f5_nlp_target <= f4_nlp_target;
        end
    end
endmodule

// ==============================================================================
// 后端 E-Block (Decode, Execute & Memory) - 深度解耦分布注毒网络
// ==============================================================================

module ID_RF_Reg #(parameter DATAWIDTH = 32)(
    input  logic clk, rst, stall, poison,
    input  logic                 id_valid, id_is_M,
    input  logic [DATAWIDTH-1:0] id_pc, id_inst, id_imm, id_branch_target, id_ret_pc,
    input  logic [4:0]           id_rd, id_rs1, id_rs2,
    input  logic                 id_RegWen, id_MemWen, id_IsBranch, id_AluSrcB,
    input  logic [1:0]           id_JmpType, id_WbSel, id_AluSrcA,
    input  logic [3:0]           id_alu_ctrl,
    input  logic [2:0]           id_funct3,
    input  logic [11:0]          id_csr_idx,
    input  logic                 id_CsrWen, id_CsrImmSel, id_IsEcall, id_IsEbreak, id_IsMret,
    input  logic [1:0]           id_CsrOp,
    input  logic                 id_pred_taken,
    input  logic [DATAWIDTH-1:0] id_pred_target,

    output logic                 rf_valid, rf_is_M,
    output logic [DATAWIDTH-1:0] rf_pc, rf_inst, rf_imm, rf_branch_target, rf_ret_pc,
    output logic [4:0]           rf_rd, rf_rs1, rf_rs2,
    output logic                 rf_RegWen, rf_MemWen, rf_IsBranch, rf_AluSrcB,
    output logic [1:0]           rf_JmpType, rf_WbSel, rf_AluSrcA,
    output logic [3:0]           rf_alu_ctrl,
    output logic [2:0]           rf_funct3,
    output logic [11:0]          rf_csr_idx,
    output logic                 rf_CsrWen, rf_CsrImmSel, rf_IsEcall, rf_IsEbreak, rf_IsMret,
    output logic [1:0]           rf_CsrOp,
    output logic                 rf_pred_taken,
    output logic [DATAWIDTH-1:0] rf_pred_target
);
    always_ff @(posedge clk) begin
        if (rst || poison) rf_valid <= 1'b0;
        else if (!stall)   rf_valid <= id_valid;
    end
    always_ff @(posedge clk) begin
        if (!stall) begin
            {rf_pc, rf_inst, rf_imm, rf_branch_target, rf_ret_pc} <= {id_pc, id_inst, id_imm, id_branch_target, id_ret_pc};
            {rf_rd, rf_rs1, rf_rs2} <= {id_rd, id_rs1, id_rs2};
            {rf_RegWen, rf_MemWen, rf_IsBranch, rf_AluSrcB} <= {id_RegWen, id_MemWen, id_IsBranch, id_AluSrcB};
            {rf_JmpType, rf_WbSel, rf_AluSrcA} <= {id_JmpType, id_WbSel, id_AluSrcA};
            {rf_alu_ctrl, rf_funct3, rf_is_M} <= {id_alu_ctrl, id_funct3, id_is_M};
            {rf_csr_idx, rf_CsrWen, rf_CsrImmSel, rf_IsEcall, rf_IsEbreak, rf_IsMret, rf_CsrOp} <= 
            {id_csr_idx, id_CsrWen, id_CsrImmSel, id_IsEcall, id_IsEbreak, id_IsMret, id_CsrOp};
            {rf_pred_taken, rf_pred_target} <= {id_pred_taken, id_pred_target};
        end
    end
endmodule

module RF_EX1_Reg #(parameter DATAWIDTH = 32)(
    input  logic clk, rst, stall, poison,
    input  logic                 rf_valid, rf_is_M,
    input  logic [DATAWIDTH-1:0] rf_pc, rf_inst, rf_imm, rf_branch_target, rf_ret_pc,
    input  logic [DATAWIDTH-1:0] rf_fw_rs1_data, rf_fw_rs2_data, // 已完成前递路由的数据
    input  logic [4:0]           rf_rd,
    input  logic                 rf_RegWen, rf_MemWen, rf_IsBranch, rf_AluSrcB,
    input  logic [1:0]           rf_JmpType, rf_WbSel, rf_AluSrcA,
    input  logic [3:0]           rf_alu_ctrl,
    input  logic [2:0]           rf_funct3,
    input  logic [11:0]          rf_csr_idx,
    input  logic                 rf_CsrWen, rf_CsrImmSel, rf_IsEcall, rf_IsEbreak, rf_IsMret,
    input  logic [1:0]           rf_CsrOp,
    input  logic                 rf_pred_taken,
    input  logic [DATAWIDTH-1:0] rf_pred_target,

    output logic                 ex1_valid, ex1_is_M,
    output logic [DATAWIDTH-1:0] ex1_pc, ex1_inst, ex1_imm, ex1_branch_target, ex1_ret_pc,
    output logic [DATAWIDTH-1:0] ex1_fw_rs1_data, ex1_fw_rs2_data,
    output logic [4:0]           ex1_rd,
    output logic                 ex1_RegWen, ex1_MemWen, ex1_IsBranch, ex1_AluSrcB,
    output logic [1:0]           ex1_JmpType, ex1_WbSel, ex1_AluSrcA,
    output logic [3:0]           ex1_alu_ctrl,
    output logic [2:0]           ex1_funct3,
    output logic [11:0]          ex1_csr_idx,
    output logic                 ex1_CsrWen, ex1_CsrImmSel, ex1_IsEcall, ex1_IsEbreak, ex1_IsMret,
    output logic [1:0]           ex1_CsrOp,
    output logic                 ex1_pred_taken,
    output logic [DATAWIDTH-1:0] ex1_pred_target
);
    always_ff @(posedge clk) begin
        if (rst || poison) ex1_valid <= 1'b0;
        else if (!stall)   ex1_valid <= rf_valid;
    end
    always_ff @(posedge clk) begin
        if (!stall) begin
            {ex1_pc, ex1_inst, ex1_imm, ex1_branch_target, ex1_ret_pc} <= {rf_pc, rf_inst, rf_imm, rf_branch_target, rf_ret_pc};
            {ex1_fw_rs1_data, ex1_fw_rs2_data} <= {rf_fw_rs1_data, rf_fw_rs2_data};
            ex1_rd <= rf_rd;
            {ex1_RegWen, ex1_MemWen, ex1_IsBranch, ex1_AluSrcB} <= {rf_RegWen, rf_MemWen, rf_IsBranch, rf_AluSrcB};
            {ex1_JmpType, ex1_WbSel, ex1_AluSrcA} <= {rf_JmpType, rf_WbSel, rf_AluSrcA};
            {ex1_alu_ctrl, ex1_funct3, ex1_is_M} <= {rf_alu_ctrl, rf_funct3, rf_is_M};
            {ex1_csr_idx, ex1_CsrWen, ex1_CsrImmSel, ex1_IsEcall, ex1_IsEbreak, ex1_IsMret, ex1_CsrOp} <=
            {rf_csr_idx, rf_CsrWen, rf_CsrImmSel, rf_IsEcall, rf_IsEbreak, rf_IsMret, rf_CsrOp};
            {ex1_pred_taken, ex1_pred_target} <= {rf_pred_taken, rf_pred_target};
        end
        // 注毒时彻底切断幽灵控制信号，防止 HDU 误判 / MDU 误启动
        if (poison) begin
            ex1_is_M   <= 1'b0;
            ex1_RegWen <= 1'b0;
            ex1_MemWen <= 1'b0;
        end
    end
endmodule

module EX1_BR_Reg #(parameter DATAWIDTH = 32)(
    input  logic clk, rst, stall, poison,
    input  logic                 ex1_valid,
    input  logic [DATAWIDTH-1:0] ex1_pc, ex1_inst, ex1_ret_pc, ex1_branch_target,
    // 删除了 ex1_csr_rdata
    input  logic [DATAWIDTH-1:0] ex1_alu_res, ex1_fw_rs1_data, ex1_fw_rs2_data, ex1_agu_res,
    input  logic [4:0]           ex1_rd,
    input  logic                 ex1_RegWen, ex1_MemWen, ex1_IsBranch,
    input  logic [1:0]           ex1_JmpType, ex1_WbSel,
    input  logic [2:0]           ex1_funct3,
    input  logic                 ex1_pred_taken,
    input  logic [DATAWIDTH-1:0] ex1_pred_target,

    output logic                 br_valid,
    output logic [DATAWIDTH-1:0] br_pc, br_inst, br_ret_pc, br_branch_target,
    // 删除了 br_csr_rdata
    output logic [DATAWIDTH-1:0] br_alu_res, br_fw_rs1_data, br_fw_rs2_data, br_agu_res,
    output logic [4:0]           br_rd,
    output logic                 br_RegWen, br_MemWen, br_IsBranch,
    output logic [1:0]           br_JmpType, br_WbSel,
    output logic [2:0]           br_funct3,
    output logic                 br_pred_taken,
    output logic [DATAWIDTH-1:0] br_pred_target
);
    always_ff @(posedge clk) begin
        if (rst || poison) br_valid <= 1'b0;
        else if (!stall)   br_valid <= ex1_valid;
    end
    always_ff @(posedge clk) begin
        if (!stall && !poison) begin
            {br_pc, br_inst, br_ret_pc, br_branch_target} <= {ex1_pc, ex1_inst, ex1_ret_pc, ex1_branch_target};
            // 剔除了对 csr_rdata 的赋值传递
            {br_alu_res, br_fw_rs1_data, br_fw_rs2_data, br_agu_res} <= 
            {ex1_alu_res, ex1_fw_rs1_data, ex1_fw_rs2_data, ex1_agu_res};
            br_rd <= ex1_rd;
            {br_RegWen, br_MemWen, br_IsBranch, br_JmpType, br_WbSel, br_funct3} <= 
            {ex1_RegWen, ex1_MemWen, ex1_IsBranch, ex1_JmpType, ex1_WbSel, ex1_funct3};
            {br_pred_taken, br_pred_target} <= {ex1_pred_taken, ex1_pred_target};
        end
    end
endmodule

module BR_MEM1_Reg #(parameter DATAWIDTH = 32)(
    input  logic clk, rst, stall, poison,
    input  logic                 br_valid,
    input  logic [DATAWIDTH-1:0] br_pc, br_inst, br_ret_pc,
    input  logic [DATAWIDTH-1:0] br_alu_res, br_fw_rs2_data, br_agu_res, br_csr_rdata,
    input  logic [4:0]           br_rd,
    input  logic                 br_RegWen, br_MemWen,
    input  logic [1:0]           br_WbSel,
    input  logic [2:0]           br_funct3,

    output logic                 mem1_valid,
    output logic [DATAWIDTH-1:0] mem1_pc, mem1_inst, mem1_ret_pc,
    output logic [DATAWIDTH-1:0] mem1_alu_res, mem1_fw_rs2_data, mem1_agu_res, mem1_csr_rdata,
    output logic [4:0]           mem1_rd,
    output logic                 mem1_RegWen, mem1_MemWen,
    output logic [1:0]           mem1_WbSel,
    output logic [2:0]           mem1_funct3
);
    always_ff @(posedge clk) begin
        if (rst || poison) mem1_valid <= 1'b0;
        else if (!stall)   mem1_valid <= br_valid;
    end
    always_ff @(posedge clk) begin
        if (!stall) begin
            {mem1_pc, mem1_inst, mem1_ret_pc} <= {br_pc, br_inst, br_ret_pc};
            {mem1_alu_res, mem1_fw_rs2_data, mem1_agu_res, mem1_csr_rdata} <= {br_alu_res, br_fw_rs2_data, br_agu_res, br_csr_rdata};
            mem1_rd <= br_rd;
            {mem1_RegWen, mem1_MemWen, mem1_WbSel, mem1_funct3} <= {br_RegWen, br_MemWen, br_WbSel, br_funct3};
        end
    end
endmodule

module MEM1_MEM2_Reg #(parameter DATAWIDTH = 32)(
    input  logic clk, rst, stall, poison,
    input  logic                 mem1_valid,
    input  logic [DATAWIDTH-1:0] mem1_pc, mem1_inst, mem1_ret_pc,
    input  logic [DATAWIDTH-1:0] mem1_alu_res, mem1_agu_res, mem1_csr_rdata,
    input  logic [4:0]           mem1_rd,
    input  logic                 mem1_RegWen,
    input  logic [1:0]           mem1_WbSel,
    input  logic [2:0]           mem1_funct3,

    output logic                 mem2_valid,
    output logic [DATAWIDTH-1:0] mem2_pc, mem2_inst, mem2_ret_pc,
    output logic [DATAWIDTH-1:0] mem2_alu_res, mem2_agu_res, mem2_csr_rdata,
    output logic [4:0]           mem2_rd,
    output logic                 mem2_RegWen,
    output logic [1:0]           mem2_WbSel,
    output logic [2:0]           mem2_funct3
);
    always_ff @(posedge clk) begin
        if (rst || poison) mem2_valid <= 1'b0;
        else if (!stall)   mem2_valid <= mem1_valid;
    end
    always_ff @(posedge clk) begin
        if (!stall) begin
            {mem2_pc, mem2_inst, mem2_ret_pc} <= {mem1_pc, mem1_inst, mem1_ret_pc};
            {mem2_alu_res, mem2_agu_res, mem2_csr_rdata} <= {mem1_alu_res, mem1_agu_res, mem1_csr_rdata};
            mem2_rd <= mem1_rd;
            {mem2_RegWen, mem2_WbSel, mem2_funct3} <= {mem1_RegWen, mem1_WbSel, mem1_funct3};
        end
    end
endmodule

module MEM2_WB_Reg #(parameter DATAWIDTH = 32)(
    input  logic clk, rst, stall, poison,
    input  logic                 mem2_valid,
    input  logic [DATAWIDTH-1:0] mem2_pc, mem2_inst,
    input  logic [DATAWIDTH-1:0] mem2_non_load_data, mem2_perip_rdata,
    input  logic [1:0]           mem2_agu_res_1_0,
    input  logic [2:0]           mem2_funct3,
    input  logic [1:0]           mem2_WbSel,
    input  logic [4:0]           mem2_rd,
    input  logic                 mem2_RegWen,

    output logic                 wb_valid,
    output logic [DATAWIDTH-1:0] wb_pc, wb_inst,
    output logic [DATAWIDTH-1:0] wb_non_load_data, wb_perip_rdata,
    output logic [1:0]           wb_agu_res_1_0,
    output logic [2:0]           wb_funct3,
    output logic [1:0]           wb_WbSel,
    output logic [4:0]           wb_rd,
    output logic                 wb_RegWen
);
    (* DONT_TOUCH = "TRUE" *) logic [DATAWIDTH-1:0] r_wb_perip_rdata;
    (* DONT_TOUCH = "TRUE" *) logic [1:0]           r_wb_agu_res_1_0;
    (* DONT_TOUCH = "TRUE" *) logic [2:0]           r_wb_funct3;

    assign wb_perip_rdata = r_wb_perip_rdata;
    assign wb_agu_res_1_0 = r_wb_agu_res_1_0;
    assign wb_funct3      = r_wb_funct3;

    always_ff @(posedge clk) begin
        if (rst || poison) wb_valid <= 1'b0;
        else if (!stall)   wb_valid <= mem2_valid;
    end
    always_ff @(posedge clk) begin
        if (!stall) begin
            {wb_pc, wb_inst} <= {mem2_pc, mem2_inst};
            wb_non_load_data <= mem2_non_load_data;
            r_wb_perip_rdata <= mem2_perip_rdata; 
            r_wb_agu_res_1_0 <= mem2_agu_res_1_0;
            r_wb_funct3      <= mem2_funct3;
            wb_rd            <= mem2_rd;
            wb_RegWen        <= mem2_RegWen;
            wb_WbSel         <= mem2_WbSel;
        end
    end
endmodule
