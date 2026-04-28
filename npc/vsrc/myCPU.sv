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
    logic [31:0] id_branch_target; // 从 ID 阶段算好的分支目标地址
    logic [31:0] id_imm, id_rs1_data, id_rs2_data, id_ret_pc;
    logic        id_IsBranch, id_RegWen, id_MemWen, id_AluSrcB;
    logic [1:0]  id_JmpType, id_WbSel, id_AluSrcA;
    logic [3:0]  id_alu_ctrl;
    logic        id_CsrWen, id_CsrImmSel, id_IsEcall, id_IsEbreak, id_IsMret;
    logic [1:0]  id_CsrOp;
    logic [1:0]  id_forward_A, id_forward_B;

    // --- EX 阶段分支预测流水线寄存器 ---
    logic        ex_pred_taken;
    logic [31:0] ex_pred_target;

    // EX Stage
    logic [31:0] ex_pc, ex_rs1_data, ex_rs2_data, ex_imm, ex_ret_pc;
    logic [31:0] ex_branch_target; // 修复：必须声明这根 32 位的线！
    logic [4:0]  ex_rd, ex_rs1, ex_rs2;
    logic        ex_RegWen, ex_MemWen, ex_IsBranch, ex_AluSrcB;
    logic [1:0]  ex_JmpType, ex_WbSel, ex_AluSrcA;
    logic [3:0]  ex_alu_ctrl;
    logic [2:0]  ex_funct3;
    logic [11:0] ex_csr_idx;
    logic        ex_CsrWen, ex_CsrImmSel, ex_IsEcall, ex_IsEbreak, ex_IsMret;
    logic [1:0]  ex_CsrOp;
    logic [31:0] ex_csr_rdata;
    logic [31:0] ex_csr_wdata;     // 修复：声明写 CSR 的 32 位线！
    logic        ex_actual_csr_wen;
    logic [31:0] ex_alu_op1, ex_alu_op2, ex_alu_res;
    logic        ex_take_trap;
    logic [31:0] trap_pc;
    logic [31:0] forwarded_rs1, forwarded_rs2; 
    logic [1:0]  ex_forward_A, ex_forward_B; 
    logic [31:0] ex_agu_res;

    `ifdef NPC_TEST
    logic [31:0] ex_inst;  // 🌟 新增：承接 EX 阶段的机器码
    `endif
    logic        ex_valid; // 🌟 新增：承接 EX 阶段的有效信号
    
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
    
    // 🌟 添加 MAX_FANOUT 属性，强制 Vivado 复制寄存器/连线以降低扇出延迟
    (* MAX_FANOUT = "16" *) logic flush_IF1_IF2_net;
    (* MAX_FANOUT = "16" *) logic flush_IF2_ID_net;
    (* MAX_FANOUT = "16" *) logic flush_ID_EX_net;
    
    assign stall_EX  = 1'b0;
    assign stall_MEM = 1'b0;
    assign flush_EX_MEM = 1'b0;
    assign flush_MEM_WB = 1'b0;

    logic hd_stall_IF, hd_flush_ID_EX;

    HazardDetectionUnit hd_inst (
        .id_rs1      (id_inst[19:15]),
        .id_rs2      (id_inst[24:20]),
        .id_opcode   (id_inst[6:0]),
        .ex_RegWen   (ex_RegWen),
        .ex_WbSel    (ex_WbSel),
        .ex_rd       (ex_rd),
        .mem1_WbSel   (mem1_WbSel),
        .mem1_rd      (mem1_rd),
        .stall_IF    (hd_stall_IF),
        .stall_ID    (stall_ID),
        .flush_ID_EX (hd_flush_ID_EX)
    );

    // Load-Use 冒险时，IF1 和 IF2 必须同时停顿
    assign stall_IF1 = hd_stall_IF;
    assign stall_IF2 = hd_stall_IF;

    /// 建立预测信号防火墙！只有 IF2 数据有效时，预测才算数
    wire valid_if2_pred_taken = if2_pred_taken && if2_valid;

    // 🌟 冲刷逻辑核心更新：赋值给 _net 信号
    assign flush_IF1_IF2_net = ex_mispredict | ex_take_trap | (valid_if2_pred_taken & ~stall_IF2);
    assign flush_IF2_ID_net  = ex_mispredict | ex_take_trap;
    assign flush_ID_EX_net   = ex_mispredict | ex_take_trap | hd_flush_ID_EX;

    // 终极 PC 路由逻辑 
// 🌟 修复：必须让异常和预测失败拥有最高优先级，强行打断任何 Stall！
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
        
        .if1_pc(if1_pc),                   // 发送地址给 BRAM
        .if2_pc(if2_pc),                   // 校验 Tag
        .if2_pred_taken(if2_pred_taken),   // 接收预测结果
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
        if (cpu_rst) begin // 🌟 只保留全局复位
            id_pred_taken  <= 1'b0;
            id_pred_target <= 32'b0;
        end else if (flush_IF2_ID_net) begin // 🌟 把 flush 拆分到这里
            id_pred_taken  <= 1'b0;
            id_pred_target <= 32'b0;
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
        .alu_ctrl (id_alu_ctrl)
    );

    ForwardingUnit fw_inst (
        .id_rs1(id_inst[19:15]), .id_rs2(id_inst[24:20]),
        .ex_RegWen  (ex_RegWen),   .ex_rd  (ex_rd),
        .mem1_RegWen(mem1_RegWen), .mem1_rd(mem1_rd),
        // 👇 恢复连回 MEM2 阶段的信号
        .mem2_RegWen(mem2_RegWen), .mem2_rd(mem2_rd),
        .id_forward_A(id_forward_A), .id_forward_B(id_forward_B)
    );

    // 在 ID 阶段独立且提前算好分支目标地址！
    assign id_branch_target = id_pc + id_imm;

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
        .id_branch_target(id_branch_target), // 流水传递预计算地址
        .id_valid(id_valid),   // 🌟 连入 ID 阶段的有效信号
        `ifdef NPC_TEST
        .id_inst(id_inst),     // 🌟 连入 ID 阶段的机器码
        .ex_inst(ex_inst),     // 🌟 连出到刚刚声明的 ex_inst
        `endif
        .ex_valid(ex_valid),   // 🌟 连出到刚刚声明的 ex_valid
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
            ex_pred_target <= 32'b0;
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
            2'b10:   forwarded_rs1 = mem2_fw_data; // 🌟 使用通道 B：不含 BRAM 的纯组合逻辑线
            2'b01:   forwarded_rs1 = wb_data;      // WB 阶段的 Load 数据在这里前递
            default: forwarded_rs1 = ex_rs1_data;
        endcase
    end
    always_comb begin
        case (ex_forward_B) 
            2'b11:   forwarded_rs2 = mem1_fw_data;
            2'b10:   forwarded_rs2 = mem2_fw_data; // 🌟 同上
            2'b01:   forwarded_rs2 = wb_data;
            default: forwarded_rs2 = ex_rs2_data;
        endcase
    end

    // ----------------------------------------
    // 分支决断
    // ----------------------------------------
    assign ex_is_jump_or_branch = ex_IsBranch || (ex_JmpType != 2'b00);

    BranchUnit #(DATAWIDTH) bu_inst (
        .imm(ex_imm), 
        .rs1_data(forwarded_rs1), .rs2_data(forwarded_rs2),
        
        .precalc_branch_target(ex_branch_target), 
        .precalc_pc_plus_4(ex_ret_pc), 
        
        .trap_pc(32'b0), 
        .Branch(ex_IsBranch), .Jump(ex_JmpType), .funct3(ex_funct3),
        .next_pc(ex_actual_target), .pc_plus_4(ex_pc_plus_4),
        .actual_taken(ex_actual_taken) // 🌟 接收新信号，直接知道是否跳转
    );

    // 🌟 极简优化：把 JALR 加法和多路选择器剥离开，让比较器提前并行计算！
    wire [31:0] fast_jalr_target = (forwarded_rs1 + ex_imm) & ~32'h1;
    
    // 直接在这里做并行判断，彻底绕开 BranchUnit 内部的 PC MUX 延迟
    wire target_mismatch = (ex_JmpType == 2'b10) ? (ex_pred_target != fast_jalr_target) : 
                           (ex_JmpType == 2'b11) ? (ex_pred_target != trap_pc) :
                                                   (ex_pred_target != ex_branch_target);

    wire branch_mispredict = ex_actual_taken ^ ex_pred_taken;
    wire target_mispredict = ex_actual_taken & ex_pred_taken & target_mismatch;
    
    // 🌟 优化：只有当 EX 阶段的指令真实有效时，才允许触发分支预测失败
    assign ex_mispredict = ex_valid & (
        (ex_is_jump_or_branch & (branch_mispredict | target_mispredict)) |
        (~ex_is_jump_or_branch & ex_pred_taken)
    );

    // 决定回退地址：直接剥离 MUX！
    // 因为 BranchUnit 中，如果分支不成立，ex_actual_target 原本就是 PC+4。
    // 所以无需使用条件选择，直接连线即可，消灭 32位 MUX！
    assign recovery_pc = ex_actual_target;

    // ----------------------------------------
    // 常规运算单元
    // ----------------------------------------
    assign ex_alu_op1 = (ex_AluSrcA == 2'b10) ? 32'b0 :
                        (ex_AluSrcA == 2'b01) ? ex_pc : forwarded_rs1;
    assign ex_alu_op2 =  ex_AluSrcB           ? ex_imm : forwarded_rs2;

    ALU #(DATAWIDTH) alu_inst (
        .A(ex_alu_op1), .B(ex_alu_op2), .ALUControl(ex_alu_ctrl), .Result(ex_alu_res)
    );

    AGU #(DATAWIDTH) agu_inst (
        .base   (forwarded_rs1), 
        .offset (ex_imm),
        .addr   (ex_agu_res)
    );

    assign ex_csr_wdata = ex_CsrImmSel ? {27'b0, ex_rs1} : forwarded_rs1;
    assign ex_actual_csr_wen = ex_CsrWen && !((ex_CsrOp == 2'b10 || ex_CsrOp == 2'b11) && (ex_rs1 == 5'b0));

    CSR #(DATAWIDTH) csr_inst (
        .clk(cpu_clk), .rst(cpu_rst), .pc(ex_pc),
        .csr_idx(ex_csr_idx), .wdata(ex_csr_wdata), .csr_op(ex_CsrOp), .csr_wen(ex_actual_csr_wen),
        .ecall(ex_IsEcall), .ebreak(ex_IsEbreak), .mret(ex_IsMret),
        .rdata(ex_csr_rdata), .trap_pc(trap_pc)
    );

    assign ex_take_trap = ex_IsEcall | ex_IsEbreak | ex_IsMret;

    // 🌟 新增：在 EX 阶段就根据 WbSel 提前把前递数据算好！
    logic [31:0] ex_fw_data;
    assign ex_fw_data = (ex_WbSel == 2'b01) ? ex_ret_pc :
                        (ex_WbSel == 2'b11) ? ex_csr_rdata : ex_alu_res;

    EX_MEM1_Reg #(DATAWIDTH) ex_mem1_reg (
        .clk(cpu_clk), .rst(cpu_rst), .flush(1'b0), .stall(1'b0),
        .ex_alu_res(ex_alu_res), .ex_agu_res(ex_agu_res),      
        .ex_rs2_data(forwarded_rs2), .ex_ret_pc(ex_ret_pc),
        .ex_rd(ex_rd), .ex_RegWen(ex_RegWen), .ex_MemWen(ex_MemWen), .ex_WbSel(ex_WbSel), .ex_funct3(ex_funct3),
        .ex_csr_rdata(ex_csr_rdata),
        .ex_fw_data(ex_fw_data),       // 🌟 连上计算好的输入
        
        .mem1_alu_res(mem1_alu_res), .mem1_agu_res(mem1_agu_res),    
        .mem1_rs2_data(mem1_rs2_data), .mem1_ret_pc(mem1_ret_pc),
        .mem1_rd(mem1_rd), .mem1_RegWen(mem1_RegWen), .mem1_MemWen(mem1_MemWen), 
        .mem1_WbSel(mem1_WbSel), .mem1_funct3(mem1_funct3), .mem1_csr_rdata(mem1_csr_rdata),
        .mem1_fw_data(mem1_fw_data)    // 🌟 连上输出
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
        .mem1_fw_data(mem1_fw_data),   // 🌟 连上输入
        
        .mem2_alu_res(mem2_alu_res), .mem2_agu_res(mem2_agu_res), .mem2_ret_pc(mem2_ret_pc), .mem2_csr_rdata(mem2_csr_rdata),
        .mem2_rd(mem2_rd), .mem2_RegWen(mem2_RegWen), .mem2_WbSel(mem2_WbSel), .mem2_funct3(mem2_funct3),
        .mem2_fw_data(mem2_fw_data)    // 🌟 连上输出
    );

    // ==========================================
    // Stage 6: MEM2 (Memory Read Process) 🌟 极大简化
    // ==========================================
    logic [31:0] mem2_non_load_data;
    
    // 通道 A：提前算好除了 Load 以外的写回数据 (避开关键路径)
    always_comb begin
        case (mem2_WbSel) 
            2'b01:   mem2_non_load_data = mem2_ret_pc;
            2'b11:   mem2_non_load_data = mem2_csr_rdata;
            default: mem2_non_load_data = mem2_alu_res;
        endcase
    end

    // 声明 WB 阶段的新增连线
    logic [31:0] wb_non_load_data, wb_perip_rdata;
    logic [1:0]  wb_agu_res_1_0;
    logic [2:0]  wb_funct3;
    logic [1:0]  wb_WbSel;

    // 流水线寄存器：直接锁存最晚到达的 perip_rdata，切割违例路径！
    MEM2_WB_Reg #(DATAWIDTH) mem2_wb_reg (
        .clk(cpu_clk), .rst(cpu_rst), .flush(1'b0), .stall(1'b0),
        
        .mem2_non_load_data(mem2_non_load_data), 
        .mem2_perip_rdata  (perip_rdata),       // 🌟 让 BRAM 数据一出 IP 就直接打入寄存器
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
    // Stage 7: WB (Write Back) 🌟 对齐逻辑移到这里
    // ==========================================
    logic [31:0] wb_rdata_ext;

    // 因为 wb_perip_rdata 来自上方的本地 D 触发器，所以算这段逻辑速度极快
    always_comb begin
        case (wb_funct3)
            3'b000: begin // LB : 字节选择 + 符号扩展
                case(wb_agu_res_1_0)
                    2'b00: wb_rdata_ext = {{24{wb_perip_rdata[ 7]}}, wb_perip_rdata[ 7: 0]};
                    2'b01: wb_rdata_ext = {{24{wb_perip_rdata[15]}}, wb_perip_rdata[15: 8]};
                    2'b10: wb_rdata_ext = {{24{wb_perip_rdata[23]}}, wb_perip_rdata[23:16]};
                    2'b11: wb_rdata_ext = {{24{wb_perip_rdata[31]}}, wb_perip_rdata[31:24]};
                endcase
            end
            3'b100: begin // LBU : 字节选择 + 零扩展
                case(wb_agu_res_1_0)
                    2'b00: wb_rdata_ext = {24'b0, wb_perip_rdata[ 7: 0]};
                    2'b01: wb_rdata_ext = {24'b0, wb_perip_rdata[15: 8]};
                    2'b10: wb_rdata_ext = {24'b0, wb_perip_rdata[23:16]};
                    2'b11: wb_rdata_ext = {24'b0, wb_perip_rdata[31:24]};
                endcase
            end
            3'b001: begin // LH : 半字选择 + 符号扩展
                case(wb_agu_res_1_0[1])
                    1'b0: wb_rdata_ext = {{16{wb_perip_rdata[15]}}, wb_perip_rdata[15: 0]};
                    1'b1: wb_rdata_ext = {{16{wb_perip_rdata[31]}}, wb_perip_rdata[31:16]};
                endcase
            end
            3'b101: begin // LHU : 半字选择 + 零扩展
                case(wb_agu_res_1_0[1])
                    1'b0: wb_rdata_ext = {16'b0, wb_perip_rdata[15: 0]};
                    1'b1: wb_rdata_ext = {16'b0, wb_perip_rdata[31:16]};
                endcase
            end
            default: wb_rdata_ext = wb_perip_rdata; // LW : 整体透传
        endcase
    end

    // 🌟 终极写回数据选择 (从 MEM2 阶段移交到了 WB 阶段)
    assign wb_data = (wb_WbSel == 2'b10) ? wb_rdata_ext : wb_non_load_data;

    // 通用寄存器组 (Register File) 实例化
    // 读端口由 ID 阶段的指令驱动
    // 写端口由 WB 阶段的流水线寄存器驱动
    RF #(5, DATAWIDTH) rf_inst (
        .clk(cpu_clk), 
        .rst(cpu_rst), 
        
        // 🌟 写端口 (属于 Stage 7: WB)
        .wen      (wb_RegWen), 
        .waddr    (wb_rd), 
        .wdata    (wb_data),    // 从 MEM2_WB_Reg 直接流出的最终结果
        
        // 🌟 读端口 (属于 Stage 3: ID)
        .rR1      (id_inst[19:15]), 
        .rR2      (id_inst[24:20]), 
        .rR1_data (id_rs1_data), 
        .rR2_data (id_rs2_data)
    );

endmodule
