`timescale 1ns / 1ps
`include "defines.sv"
`default_nettype none

module myCPU (
    input  wire          cpu_rst,
    input  wire          cpu_clk,

    output logic [31:0]  irom_addr,
    input  wire  [31:0]  irom_data,
    
    output logic [31:0]  perip_addr,
    output logic         perip_wen,
    output logic [ 3:0]  perip_mask,
    output logic [31:0]  perip_wdata,
    
    input  wire  [31:0]  perip_rdata
);
    parameter DATAWIDTH = 32;
    parameter RESET_VAL = 32'h8000_0000;

    // ==========================================
    // 全局信号提前声明
    // ==========================================
    // IF1 Stage (Address Generation)
    logic [31:0] if1_pc, actual_next_pc;

    // IF2 Stage (Fetch & Predict)
    logic [31:0] if2_pc, if2_inst;
    logic        if2_valid;
    logic        if2_pred_taken;
    logic [31:0] if2_pred_target;

    // --- ID 阶段分支预测流水线寄存器 ---
    logic        id_pred_taken;
    logic [31:0] id_pred_target;
    
    // ID Stage
    logic [31:0] id_pc, id_inst, id_inst_raw;
    logic        id_valid;
    logic [31:0] id_branch_target;
    logic [31:0] id_imm, id_rs1_data, id_rs2_data, id_ret_pc;
    logic        id_IsBranch, id_RegWen, id_MemWen, id_AluSrcB;
    logic [1:0]  id_JmpType, id_WbSel, id_AluSrcA;
    logic [4:0]  id_alu_ctrl;  // ★ 5bit: Zba/Zbs/Zbb/Zbkb
    logic        id_CsrWen, id_CsrImmSel, id_IsEcall, id_IsEbreak, id_IsMret;
    logic [1:0]  id_CsrOp;
    logic [1:0]  id_forward_A, id_forward_B;

    // --- EX 阶段分支预测流水线寄存器 ---
    logic        ex_pred_taken;
    logic [31:0] ex_pred_target;

    // EX Stage
    logic [31:0] ex_pc, ex_rs1_data, ex_rs2_data, ex_imm, ex_ret_pc;
    logic [31:0] ex_branch_target;
    logic [4:0]  ex_rd, ex_rs1, ex_rs2;
    logic        ex_RegWen, ex_MemWen, ex_IsBranch, ex_AluSrcB;
    logic [1:0]  ex_JmpType, ex_WbSel, ex_AluSrcA;
    logic [4:0]  ex_alu_ctrl;  // ★ 5bit: Zba/Zbs/Zbb/Zbkb
    logic [2:0]  ex_funct3;
    logic [11:0] ex_csr_idx;
    logic        ex_CsrWen, ex_CsrImmSel, ex_IsEcall, ex_IsEbreak, ex_IsMret;
    logic [1:0]  ex_CsrOp;
    logic [31:0] ex_csr_rdata;
    logic [31:0] ex_csr_wdata;     
    logic        ex_actual_csr_wen;
    logic [31:0] ex_alu_op1, ex_alu_op2, ex_alu_res;
    logic        ex_take_trap;
    logic [31:0] trap_pc;
    logic [31:0] forwarded_rs1, forwarded_rs2;
    logic [31:0] branch_rs1, branch_rs2;
    logic [1:0]  ex_forward_A, ex_forward_B; 
    logic [31:0] ex_agu_res;

    `ifdef NPC_TEST
    logic [31:0] ex_inst;
    `endif
    logic        ex_valid;
    
    // --- EX阶段实际决断与预测验证信号 ---
    logic [31:0] ex_actual_target;
    logic [31:0] ex_pc_plus_4;
    logic        ex_actual_taken;
    logic        ex_mispredict;
    logic [31:0] recovery_pc;
    logic        ex_is_jump_or_branch;

    // MEM Stage
    // MEM1
    logic [31:0] mem1_alu_res, mem1_rs2_data, mem1_ret_pc, mem1_agu_res, mem1_csr_rdata;
    logic [4:0]  mem1_rd;
    logic        mem1_RegWen, mem1_MemWen;
    logic [1:0]  mem1_WbSel;
    logic [2:0]  mem1_funct3;
    logic [31:0] mem1_fw_data;

    // MEM2
    logic [31:0] mem2_alu_res, mem2_ret_pc, mem2_agu_res, mem2_csr_rdata;
    logic [4:0]  mem2_rd;
    logic        mem2_RegWen;
    logic [1:0]  mem2_WbSel;
    logic [2:0]  mem2_funct3;
    logic [31:0] mem2_rdata_align, mem2_rdata_ext;
    logic [31:0] mem2_final_data;
    logic [31:0] mem2_fw_data;

    // WB Stage
    logic [31:0] wb_data;
    logic [31:0] wb_non_load_data, wb_perip_rdata;
    logic [1:0]  wb_agu_res_1_0;
    logic [2:0]  wb_funct3;
    logic [1:0]  wb_WbSel;
    logic [4:0]  wb_rd;
    logic        wb_RegWen;

    // ==========================================
    // 全局控制信号与冒险检测
    // ==========================================
    logic stall_IF1, stall_IF2;
    logic stall_ID;
    logic stall_EX;
    logic stall_MEM, flush_EX_MEM;
    logic flush_MEM_WB;
    
    (* MAX_FANOUT = "4" *) logic flush_IF1_IF2_net;
    (* MAX_FANOUT = "4" *) logic flush_IF2_ID_net;
    (* MAX_FANOUT = "4" *) logic flush_ID_EX_net;
    
    // 🌟 增加：M 扩展相关信号
    logic id_is_M, ex_is_M;
    logic [31:0] mdu_res;
    logic mdu_busy, mdu_done;
    logic stall_req_mdu;
    logic flush_EX_MEM1_net;

    // 🌟 修改：响应 MDU 的 stall
    assign stall_EX  = stall_req_mdu; 
    assign stall_MEM = 1'b0;
    assign flush_EX_MEM = 1'b0;
    assign flush_MEM_WB = 1'b0;

    // 🌟 修改：重命名内部变量以防冲突
    logic hd_stall_IF, hd_flush_ID_EX, hd_stall_ID;
    HazardDetectionUnit hd_inst (
        .id_rs1      (id_inst[19:15]),
        .id_rs2      (id_inst[24:20]),
        .id_opcode   (id_inst[6:0]),
        .ex_RegWen   (ex_RegWen),
        .ex_WbSel    (ex_WbSel),
        .ex_rd       (ex_rd),
        .mem1_WbSel  (mem1_WbSel),
        .mem1_rd     (mem1_rd),
        .mem2_RegWen (mem2_RegWen),
        .mem2_rd     (mem2_rd),
        .stall_IF    (hd_stall_IF),
        .stall_ID    (hd_stall_ID),  // 🌟 使用重命名后的线
        .flush_ID_EX (hd_flush_ID_EX)
    );

    assign stall_req_mdu = ex_valid & ex_is_M & ~mdu_done;

    // 🌟 修改：Load-Use 和 MDU 除法冲突时，所有前级全部停顿
    assign stall_IF1 = hd_stall_IF | stall_req_mdu;
    assign stall_IF2 = hd_stall_IF | stall_req_mdu;
    assign stall_ID  = hd_stall_ID | stall_req_mdu;

    // 🌟 新增：当 EX 被卡住时，向下游(MEM1)插入空指令(气泡)
    assign flush_EX_MEM1_net = stall_req_mdu;

    /// 建立预测信号防火墙！只有 IF2 数据有效时，预测才算数
    wire valid_if2_pred_taken = if2_pred_taken && if2_valid;

    // 冲刷逻辑核心更新：赋值给 _net 信号
    wire redirect_flush = ex_mispredict | ex_take_trap;
    wire id_ex_redirect_flush = redirect_flush & ~stall_req_mdu;
    wire load_use_flush_id_ex = hd_flush_ID_EX & ~stall_req_mdu;
    assign flush_IF1_IF2_net = redirect_flush | (valid_if2_pred_taken & ~stall_IF2);
    assign flush_IF2_ID_net  = redirect_flush;
    assign flush_ID_EX_net   = id_ex_redirect_flush | load_use_flush_id_ex;

    // 终极 PC 路由逻辑 
    // 必须让异常和预测失败拥有最高优先级，强行打断任何 Stall！
    assign actual_next_pc = ex_take_trap   ? trap_pc :
                            ex_mispredict  ? recovery_pc :
                            stall_IF1      ? if1_pc :
                            valid_if2_pred_taken ? if2_pred_target : 
                                             (if1_pc + 4);

    // ==========================================
    // Stage 1: IF1 (Address Generation)
    // ==========================================
    assign irom_addr = stall_IF1 ? if2_pc : if1_pc;
    
    PC #(DATAWIDTH, RESET_VAL) pc_inst (
        .clk(cpu_clk), .rst(cpu_rst),
        .npc(actual_next_pc), .pc_out(if1_pc)
    );

    // ==========================================
    // Stage 1.5: IF1/IF2 Pipeline Register
    // ==========================================
    IF1_IF2_Reg #(DATAWIDTH) if1_if2_reg (
        .clk(cpu_clk), .rst(cpu_rst), .flush(flush_IF1_IF2_net), .stall(stall_IF2),
        .if1_pc(if1_pc),
        .if2_pc(if2_pc), .if2_valid(if2_valid)
    );

    // ==========================================
    // Stage 2: IF2 (Instruction Fetch & Predict)
    // ==========================================
    assign if2_inst = irom_data;

    // 实例化高容量同步分支预测器 (1024 项)
    BranchPredictor #(32, 10) bp_inst (
        .clk(cpu_clk),
        .if1_pc(if1_pc),                   
        .if2_pc(if2_pc),                   
        .if2_pred_taken(if2_pred_taken),   
        .if2_pred_target(if2_pred_target),
        
        .ex_is_branch(ex_is_jump_or_branch),
        .ex_pc(ex_pc),
        .ex_actual_taken(ex_actual_taken),
        .ex_actual_target(ex_actual_target)
    );

    // ==========================================
    // Stage 2.5: IF2/ID Pipeline Register
    // ==========================================
    IF2_ID_Reg #(DATAWIDTH) if2_id_reg (
        .clk(cpu_clk), .rst(cpu_rst), .flush(flush_IF2_ID_net), .stall(stall_ID),
        .if2_pc(if2_pc), .if2_inst(if2_inst), .if2_valid(if2_valid),
        .id_pc(id_pc), .id_inst_raw(id_inst_raw), .id_valid(id_valid) 
    );

    // 传递预测状态 (IF2 -> ID)
    always_ff @(posedge cpu_clk) begin
        if (cpu_rst) begin 
            id_pred_taken  <= 1'b0;
            id_pred_target <= 32'b0;
        end else if (flush_IF2_ID_net) begin 
            id_pred_taken  <= 1'b0;
        end else if (!stall_ID) begin
            id_pred_taken  <= valid_if2_pred_taken;
            id_pred_target <= if2_pred_target;
        end
    end

    // ==========================================
    // Stage 3: ID (Instruction Decode)
    // ==========================================
    // 若无效或被冲刷，塞入 NOP (addi x0, x0, 0)
    assign id_inst = id_valid ? id_inst_raw : 32'h00000013; 

    assign id_ret_pc = id_pc + 4; 

    // 🌟 新增：在 ID 阶段解析 M 扩展指令
    assign id_is_M = (id_inst[6:0] == 7'b0110011) && (id_inst[31:25] == 7'b0000001);

    Control control_inst (
        .inst      (id_inst), 
        .IsBranch  (id_IsBranch), .JmpType (id_JmpType),
        .RegWen    (id_RegWen),   .MemWen  (id_MemWen),
        .WbSel     (id_WbSel),    .AluSrcA (id_AluSrcA), .AluSrcB (id_AluSrcB),
        .CsrWen(id_CsrWen), .CsrOp(id_CsrOp), .CsrImmSel(id_CsrImmSel), 
        .IsEcall(id_IsEcall), .IsEbreak(id_IsEbreak), .IsMret(id_IsMret)
    );

    IMMGEN #(DATAWIDTH) immgen_inst (.instr(id_inst), .imm(id_imm));

    ACTL actl_inst (
        .opcode   (id_inst[6:0]), .funct3 (id_inst[14:12]), .funct7 (id_inst[31:25]),
        .shamt    (id_inst[24:20]),  // ★ Zbb/Zbkb: 区分子指令
        .alu_ctrl (id_alu_ctrl)
    );

    ForwardingUnit fw_inst (
        .id_rs1(id_inst[19:15]), .id_rs2(id_inst[24:20]),
        .ex_RegWen  (ex_RegWen),   .ex_rd  (ex_rd),
        .mem1_RegWen(mem1_RegWen), .mem1_rd(mem1_rd),
        .mem2_RegWen(mem2_RegWen), .mem2_rd(mem2_rd),
        .id_forward_A(id_forward_A), .id_forward_B(id_forward_B)
    );

    // 在 ID 阶段独立且提前算好分支目标地址！
    assign id_branch_target = id_pc + id_imm;

    // 在 ID 阶段提前算好减法，剥离 EX 阶段的关键路径！
    wire [31:0] id_expected_rs1_0 = id_pred_target - id_imm;
    wire [31:0] id_expected_rs1_1 = id_pred_target - id_imm + 32'd1;

    logic [31:0] ex_expected_rs1_0, ex_expected_rs1_1; // 接收传出来的线

    ID_EX_Reg #(DATAWIDTH) id_ex_reg (
        .clk(cpu_clk), .rst(cpu_rst), .flush(flush_ID_EX_net), .stall(stall_EX),
        .id_pc(id_pc), .id_rs1_data(id_rs1_data), .id_rs2_data(id_rs2_data), .id_imm(id_imm), .id_ret_pc(id_ret_pc),
        .id_rd(id_inst[11:7]), .id_rs1(id_inst[19:15]), .id_rs2(id_inst[24:20]),
        .id_RegWen(id_RegWen), .id_MemWen(id_MemWen), .id_IsBranch(id_IsBranch), .id_AluSrcB(id_AluSrcB),
        .id_JmpType(id_JmpType), .id_WbSel(id_WbSel), .id_AluSrcA(id_AluSrcA),
        .id_alu_ctrl(id_alu_ctrl), .id_funct3(id_inst[14:12]),
        .id_csr_idx(id_inst[31:20]), .id_CsrWen(id_CsrWen), .id_CsrImmSel(id_CsrImmSel), 
        .id_IsEcall(id_IsEcall), .id_IsEbreak(id_IsEbreak), .id_IsMret(id_IsMret), .id_CsrOp(id_CsrOp),
        .id_forward_A(id_forward_A), .id_forward_B(id_forward_B),
        .id_branch_target(id_branch_target), 
        .id_valid(id_valid),
        
        .id_is_M(id_is_M),     // 🌟 新增连入 M 扩展标志
        .ex_is_M(ex_is_M),     // 🌟 新增连出 M 扩展标志

        // 🌟 新增连线
        .id_expected_rs1_0(id_expected_rs1_0),
        .id_expected_rs1_1(id_expected_rs1_1),
        .ex_expected_rs1_0(ex_expected_rs1_0),
        .ex_expected_rs1_1(ex_expected_rs1_1),

        `ifdef NPC_TEST
        .id_inst(id_inst),     
        .ex_inst(ex_inst),     
        `endif
        .ex_valid(ex_valid),   
        .ex_pc(ex_pc), .ex_rs1_data(ex_rs1_data), .ex_rs2_data(ex_rs2_data), .ex_imm(ex_imm), .ex_ret_pc(ex_ret_pc),
        .ex_rd(ex_rd), .ex_rs1(ex_rs1), .ex_rs2(ex_rs2),
        .ex_RegWen(ex_RegWen), .ex_MemWen(ex_MemWen), .ex_IsBranch(ex_IsBranch), .ex_AluSrcB(ex_AluSrcB),
        .ex_JmpType(ex_JmpType), .ex_WbSel(ex_WbSel), .ex_AluSrcA(ex_AluSrcA),
        .ex_alu_ctrl(ex_alu_ctrl), .ex_funct3(ex_funct3),
        .ex_csr_idx(ex_csr_idx), .ex_CsrWen(ex_CsrWen), .ex_CsrImmSel(ex_CsrImmSel),
        .ex_IsEcall(ex_IsEcall), .ex_IsEbreak(ex_IsEbreak), .ex_IsMret(ex_IsMret), .ex_CsrOp(ex_CsrOp),
        .ex_forward_A(ex_forward_A), .ex_forward_B(ex_forward_B),
        .ex_branch_target(ex_branch_target)
    );

    // 传递预测状态 (ID -> EX)
    always_ff @(posedge cpu_clk) begin
        if (cpu_rst) begin
            ex_pred_taken  <= 1'b0;
            ex_pred_target <= 32'b0;
        end else if (flush_ID_EX_net) begin
            ex_pred_taken  <= 1'b0;
        end else if (!stall_EX) begin
            ex_pred_taken  <= id_pred_taken;
            ex_pred_target <= id_pred_target;
        end
    end

    // ==========================================
    // Stage 4: EX (Execute) & Branch Resolution
    // ==========================================
    always_comb begin
        case (ex_forward_A) 
            2'b11:   forwarded_rs1 = mem1_fw_data;
            2'b10:   forwarded_rs1 = mem2_fw_data; 
            2'b01:   forwarded_rs1 = wb_data;
            default: forwarded_rs1 = ex_rs1_data;
        endcase
    end
    always_comb begin
        case (ex_forward_B) 
            2'b11:   forwarded_rs2 = mem1_fw_data;
            2'b10:   forwarded_rs2 = mem2_fw_data; 
            2'b01:   forwarded_rs2 = wb_data;
            default: forwarded_rs2 = ex_rs2_data;
        endcase
    end
    always_comb begin
        case (ex_forward_A)
            2'b11:   branch_rs1 = mem1_fw_data;
            2'b10:   branch_rs1 = mem2_fw_data;
            default: branch_rs1 = ex_rs1_data;
        endcase
    end
    always_comb begin
        case (ex_forward_B)
            2'b11:   branch_rs2 = mem1_fw_data;
            2'b10:   branch_rs2 = mem2_fw_data;
            default: branch_rs2 = ex_rs2_data;
        endcase
    end

    // ----------------------------------------
    // 分支决断
    // ----------------------------------------
    assign ex_is_jump_or_branch = ex_IsBranch || (ex_JmpType != 2'b00);

    BranchUnit #(DATAWIDTH) bu_inst (
        .imm(ex_imm), 
        .rs1_data(branch_rs1), .rs2_data(branch_rs2),
        
        .precalc_branch_target(ex_branch_target), 
        .precalc_pc_plus_4(ex_ret_pc), 
        
        .trap_pc(trap_pc),
        .Branch(ex_IsBranch), .Jump(ex_JmpType), .funct3(ex_funct3),
        .next_pc(ex_actual_target), .pc_plus_4(ex_pc_plus_4),
        .actual_taken(ex_actual_taken) 
    );

    // 🌟🌟 300MHz 终极黑魔法：前推至 ID 的减法器 + EX 纯并行比较器 🌟🌟
    // 注意：这里的 ex_expected_rs1_0 直接来自寄存器，不再包含加法逻辑！
    wire jalr_match = (branch_rs1 == ex_expected_rs1_0) || (branch_rs1 == ex_expected_rs1_1);

    logic target_mismatch;
    always_comb begin
        if (ex_JmpType == 2'b10) begin
            // 直接取反，省去串行的 32位比较器
            target_mismatch = !jalr_match;
        end else if (ex_JmpType == 2'b11) begin
            target_mismatch = (ex_pred_target != trap_pc);
        end else begin
            target_mismatch = (ex_pred_target != ex_branch_target);
        end
    end

    wire branch_mispredict = ex_actual_taken ^ ex_pred_taken;
    wire target_mispredict = ex_actual_taken & ex_pred_taken & target_mismatch;

    assign ex_mispredict = ex_valid & (
        (ex_is_jump_or_branch & (branch_mispredict | target_mispredict)) |
        (~ex_is_jump_or_branch & ex_pred_taken)
    );
    
    assign recovery_pc = ex_actual_target;

    // ----------------------------------------
    // 常规运算单元与 MDU
    // ----------------------------------------
    assign ex_alu_op1 = (ex_AluSrcA == 2'b10) ? 32'b0 :
                        (ex_AluSrcA == 2'b01) ? ex_pc : forwarded_rs1;
    assign ex_alu_op2 =  ex_AluSrcB           ? ex_imm : forwarded_rs2;

    ALU #(DATAWIDTH) alu_inst (
        .A(ex_alu_op1), .B(ex_alu_op2), .ALUControl(ex_alu_ctrl), .Result(ex_alu_res)
    );

    wire mdu_start = ex_valid & ex_is_M & ~mdu_busy & ~mdu_done;

    MDU mdu_inst (
        .clk(cpu_clk), 
        .rst(cpu_rst),
        .start(mdu_start), 
        .funct3(ex_funct3),
        .a(forwarded_rs1), 
        .b(forwarded_rs2),
        .result(mdu_res),
        .busy(mdu_busy), 
        .done(mdu_done)
    );

    // 🌟 新增：MUX 将 MDU 结果和 ALU 结果合并
    logic [31:0] final_ex_alu_res;
    assign final_ex_alu_res = ex_is_M ? mdu_res : ex_alu_res;

    AGU #(DATAWIDTH) agu_inst (
        .base   (forwarded_rs1), 
        .offset (ex_imm),
        .addr   (ex_agu_res)
    );

    assign ex_csr_wdata = ex_CsrImmSel ? {27'b0, ex_rs1} : forwarded_rs1;
    assign ex_actual_csr_wen = ex_CsrWen && !((ex_CsrOp != 2'b00) && (ex_rs1 == 5'b0));

    CSR #(DATAWIDTH) csr_inst (
        .clk(cpu_clk), .rst(cpu_rst), .pc(ex_pc),
        .csr_idx(ex_csr_idx), .wdata(ex_csr_wdata), .csr_op(ex_CsrOp), .csr_wen(ex_actual_csr_wen),
        .ecall(ex_IsEcall), .ebreak(ex_IsEbreak), .mret(ex_IsMret),
        .rdata(ex_csr_rdata), .trap_pc(trap_pc)
    );

    assign ex_take_trap = ex_valid & (ex_IsEcall | ex_IsEbreak | ex_IsMret);

    // 🌟 修改：在写回选择网络中使用 final_ex_alu_res
    logic [31:0] ex_fw_data;
    assign ex_fw_data = (ex_WbSel == 2'b01) ? ex_ret_pc :
                        (ex_WbSel == 2'b11) ? ex_csr_rdata : final_ex_alu_res;

    EX_MEM1_Reg #(DATAWIDTH) ex_mem1_reg (
        .clk(cpu_clk), .rst(cpu_rst), 
        .flush(flush_EX_MEM1_net),  // 🌟 修改：响应 MDU 的流水线气泡插入
        .stall(1'b0),
        .ex_alu_res(final_ex_alu_res), // 🌟 修改：传入含有乘除法结果的最终数据      
        .ex_agu_res(ex_agu_res),      
        .ex_rs2_data(forwarded_rs2), .ex_ret_pc(ex_ret_pc),
        .ex_rd(ex_rd), .ex_RegWen(ex_RegWen), .ex_MemWen(ex_MemWen), .ex_WbSel(ex_WbSel), .ex_funct3(ex_funct3),
        .ex_csr_rdata(ex_csr_rdata),
        .ex_fw_data(ex_fw_data),       
        
        .mem1_alu_res(mem1_alu_res), .mem1_agu_res(mem1_agu_res),    
        .mem1_rs2_data(mem1_rs2_data), .mem1_ret_pc(mem1_ret_pc),
        .mem1_rd(mem1_rd), .mem1_RegWen(mem1_RegWen), .mem1_MemWen(mem1_MemWen), 
        .mem1_WbSel(mem1_WbSel), .mem1_funct3(mem1_funct3), .mem1_csr_rdata(mem1_csr_rdata),
        .mem1_fw_data(mem1_fw_data)    
    );

    // ==========================================
    // Stage 5: MEM1 (Memory Access Request)
    // ==========================================
    assign perip_addr = mem1_agu_res;
    assign perip_wen  = mem1_MemWen;

    StoreAlign #(DATAWIDTH) store_align_inst (
        .addr_offset (mem1_agu_res[1:0]), 
        .wdata_in    (mem1_rs2_data),
        .size_mask   (mem1_funct3[1:0]), 
        .MemWrite    (mem1_MemWen),
        .wmask_out   (perip_mask),   
        .wdata_out   (perip_wdata)   
    );

    MEM1_MEM2_Reg #(DATAWIDTH) mem1_mem2_reg (
        .clk(cpu_clk), .rst(cpu_rst), .flush(1'b0), .stall(1'b0),
        .mem1_alu_res(mem1_alu_res), .mem1_agu_res(mem1_agu_res), .mem1_ret_pc(mem1_ret_pc), .mem1_csr_rdata(mem1_csr_rdata),
        .mem1_rd(mem1_rd), .mem1_RegWen(mem1_RegWen), .mem1_WbSel(mem1_WbSel), .mem1_funct3(mem1_funct3),
        .mem1_fw_data(mem1_fw_data),   
        
        .mem2_alu_res(mem2_alu_res), .mem2_agu_res(mem2_agu_res), .mem2_ret_pc(mem2_ret_pc), .mem2_csr_rdata(mem2_csr_rdata),
        .mem2_rd(mem2_rd), .mem2_RegWen(mem2_RegWen), .mem2_WbSel(mem2_WbSel), .mem2_funct3(mem2_funct3),
        .mem2_fw_data(mem2_fw_data)    
    );

    // ==========================================
    // Stage 6: MEM2 (Memory Read Process)
    // ==========================================
    logic [31:0] mem2_non_load_data;
    always_comb begin
        case (mem2_WbSel) 
            2'b01:   mem2_non_load_data = mem2_ret_pc;
            2'b11:   mem2_non_load_data = mem2_csr_rdata;
            default: mem2_non_load_data = mem2_alu_res;
        endcase
    end

    // 🌟 MEM2 阶段变得极其清爽，只负责查 Bridge 数据并打拍，彻底消灭 -1.86ns 的违例！
    MEM2_WB_Reg #(DATAWIDTH) mem2_wb_reg (
        .clk(cpu_clk), .rst(cpu_rst), .flush(1'b0), .stall(1'b0),
        
        .mem2_non_load_data(mem2_non_load_data), 
        .mem2_perip_rdata  (perip_rdata),       
        .mem2_agu_res_1_0  (mem2_agu_res[1:0]),
        .mem2_funct3       (mem2_funct3),
        .mem2_WbSel        (mem2_WbSel),
        .mem2_rd           (mem2_rd), 
        .mem2_RegWen       (mem2_RegWen),
        
        .wb_non_load_data  (wb_non_load_data),
        .wb_perip_rdata    (wb_perip_rdata),
        .wb_agu_res_1_0    (wb_agu_res_1_0),
        .wb_funct3         (wb_funct3),
        .wb_WbSel          (wb_WbSel),
        .wb_rd             (wb_rd), 
        .wb_RegWen         (wb_RegWen)
    );

    // ==========================================
    // Stage 7: WB (Write Back)
    // ==========================================
    logic [7:0]  wb_byte_data;
    logic [15:0] wb_half_data;
    always_comb begin
        case (wb_agu_res_1_0)
            2'b00: wb_byte_data = wb_perip_rdata[ 7: 0];
            2'b01: wb_byte_data = wb_perip_rdata[15: 8];
            2'b10: wb_byte_data = wb_perip_rdata[23:16];
            2'b11: wb_byte_data = wb_perip_rdata[31:24];
        endcase
        wb_half_data = wb_agu_res_1_0[1] ? wb_perip_rdata[31:16] : wb_perip_rdata[15:0];
    end

    logic [31:0] wb_rdata_ext;
    always_comb begin
        case (wb_funct3)
            3'b000: wb_rdata_ext = {{24{wb_byte_data[7]}}, wb_byte_data};
            3'b100: wb_rdata_ext = {24'b0, wb_byte_data};
            3'b001: wb_rdata_ext = {{16{wb_half_data[15]}}, wb_half_data};
            3'b101: wb_rdata_ext = {16'b0, wb_half_data};
            default: wb_rdata_ext = wb_perip_rdata;
        endcase
    end

    assign wb_data = (wb_WbSel == 2'b10) ? wb_rdata_ext : wb_non_load_data;
    RF #(5, DATAWIDTH) rf_inst (
        .clk(cpu_clk), 
        .rst(cpu_rst), 
        
        .wen      (wb_RegWen), 
        .waddr    (wb_rd), 
        .wdata    (wb_data),    
        
        .rR1      (id_inst[19:15]), 
        .rR2      (id_inst[24:20]), 
        .rR1_data (id_rs1_data), 
        .rR2_data (id_rs2_data)
    );
    


`ifdef NPC_TEST
    // ---- DiffTest CSR 组合逻辑 ----
    logic [31:0] ex_next_csr_val;
    always_comb begin
        case (ex_CsrOp)
            2'b00: ex_next_csr_val = ex_csr_wdata;
            2'b01: ex_next_csr_val = ex_csr_rdata | ex_csr_wdata;
            2'b10: ex_next_csr_val = ex_csr_rdata & ~ex_csr_wdata;
            default: ex_next_csr_val = ex_csr_wdata;
        endcase
    end

    // ---- 流水线提交探针 (由 difftest_hooks 驱动) ----
    logic wb_valid;
    logic [31:0] wb_pc;

    // ==========================================
    // DiffTest 流水线提交追踪 (独立模块)
    // ==========================================
    difftest_hooks u_difftest (
        .clk               (cpu_clk),
        .rst               (cpu_rst),
        .ex_valid          (ex_valid),
        .ex_pc             (ex_pc),
        .ex_IsEcall        (ex_IsEcall),
        .ex_IsEbreak       (ex_IsEbreak),
        .ex_IsMret         (ex_IsMret),
        .ex_actual_csr_wen (ex_actual_csr_wen),
        .ex_csr_idx        (ex_csr_idx),
        .ex_next_csr_val   (ex_next_csr_val),
        .flush_EX_MEM1     (flush_EX_MEM1_net),
        .wb_valid          (wb_valid),
        .wb_pc             (wb_pc)
    );

    // ==========================================
    // 性能计数器 (独立模块)
    // ==========================================
    perf_counters u_perf (
        .clk                     (cpu_clk),
        .rst                     (cpu_rst),
        .wb_valid                (wb_valid),
        .wb_WbSel                (wb_WbSel),
        .wb_funct3               (wb_funct3),
        .wb_rd                   (wb_rd),
        .wb_RegWen               (wb_RegWen),
        .wb_data                 (wb_data),
        .ex_forward_A            (ex_forward_A),
        .ex_forward_B            (ex_forward_B),
        .load_use_flush_id_ex    (load_use_flush_id_ex),
        .stall_req_mdu           (stall_req_mdu),
        .redirect_flush          (redirect_flush),
        .valid_if2_pred_taken    (valid_if2_pred_taken),
        .stall_IF2               (stall_IF2),
        .mem1_MemWen             (mem1_MemWen),
        .mem1_agu_res            (mem1_agu_res)
    );
`endif

endmodule
