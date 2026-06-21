`timescale 1ns / 1ps
`include "defines.sv"
`default_nettype none

/**
 * 模块名称：myCPU
 * 架构定义：15级非对称解耦流水线 (5级前端取指 + 1级解耦指令队列 + 9级后端执行控制)
 * 核心优化：全域时序重定向、分布式同步注毒网络、EX1级实时算术旁路前递
 */
module myCPU (
    // === 全局时钟与复位网络 (Clock & Reset Network) ===
    input  wire          cpu_rst,       // 异步复位信号，高电平有效
    input  wire          cpu_clk,       // 主时钟信号

    // === 前端 I-ROM 存储器总线接口 (64-bit 非对称并行取指) ===
    output logic [31:0]  irom_addr,     // 预取指令物理地址，对齐 32-bit 边界
    input  wire  [63:0]  irom_data,     // 64-bit 双字并行总线，单周期注入两条指令
    
    // === 后端外设与 DRAM 数据存储器总线接口 (Peripheral & Data Memory Interface) ===
    output logic [31:0]  perip_addr,    // 访存数据物理地址
    output logic         perip_wen,     // 存储器写使能信号，高电平执行物理写入
    output logic [ 3:0]  perip_mask,    // 字节选择掩码 (Byte Mask)，对应单字、半字、字节对齐
    output logic [31:0]  perip_wdata,   // 待写入存储器的数据物理总线
    input  wire  [31:0]  perip_rdata    // 从存储器/外设返回的单字读取数据总线
);

    // --- 架构核心参数定义 (Micro-architectural Parameters) ---
    parameter DATAWIDTH = 32;
    parameter RESET_VAL = 32'h8000_0000; // 硬件系统复位向量基地址

    // =========================================================================
    // 全局控制、流水线反压 (Backpressure) 与分布式注毒 (Poison) 信号声明
    // =========================================================================
    
    // 流水线挂起 (Stall) 互锁总线
    logic stall_frontend;               // 前端 F1-F5 级流水线物理挂起信号
    logic iq_almost_full;               // 指令队列 (Instruction Queue) 将满反压信号
    logic stall_EX1;                    // EX1 阶段因多周期乘除法运算引发的挂起信号
    logic stall_req_mdu;                // 乘除法单元 (Multiplier-Divider Unit) 内部忙碌反压请求
    logic hd_stall_RF;                  // 冒险检测单元 (Hazard Detection Unit) 触发的寄存器读阶段挂起
    logic stall_RF;                     // RF 级寄存器组物理挂起控制线
    logic stall_ID;                     // ID 级译码器物理挂起控制线
    logic stall_IQ_pop;                 // 指令队列出队（Pop）阻断信号

    // 控制流异常与冲刷 (Flush) 全局广播网
    logic f5_micro_flush;               // F5 级局部微冲刷，用于纠正 TAGE 预测覆盖的气泡
    logic br_flush;                     // 后端物理真实分支决断触发的全局致命冲刷
    logic br_take_trap;                 // 异常中断/环境调用 (Trap/Ecall/Mret) 状态跳转使能
    logic br_mispredict;                // BR 级确认为真实分支预测失败 (Branch Misprediction)
    logic hd_flush_RF_EX1;              // 因 加载-使用冒险 (Load-Use Hazard) 注入物理气泡的冲刷控制线

    // 分布式同步注毒网络 (Distributed Synchronization Poison Network)
    // 信号不接入触发器异步端，通过使能端与有效位（Valid Bit）强行改写为 1'b0 实现拦截
    logic poison_F1_F4;                 // 覆盖 F1 至 F4 取指级的同步毒药信号
    logic poison_F5;                    // 覆盖 F5 取指决策级的同步毒药信号
    logic poison_IQ;                    // 重置指令队列读写指针的同步毒药信号
    logic poison_ID;                    // 覆盖 ID 译码级的同步毒药信号
    logic poison_RF;                    // 覆盖 RF 寄存器读取级的同步毒药信号
    logic poison_EX1;                   // 覆盖 EX1 执行级的同步毒药信号
    logic poison_BR;                    // 覆盖 BR 分支决断级的同步毒药信号

    // =========================================================================
    // 物理控制流拦截网络映射逻辑 (Control Pipeline Routing Logic)
    // =========================================================================
    assign stall_frontend = iq_almost_full;
    assign stall_EX1      = stall_req_mdu;
    assign stall_RF       = stall_EX1 | hd_stall_RF;
    assign stall_ID       = stall_RF; 
    assign stall_IQ_pop   = stall_ID;

    assign br_flush       = br_take_trap | br_mispredict;
    
    // 分布式拦截拓扑关系映射
    assign poison_F1_F4   = br_flush | f5_micro_flush;
    assign poison_F5      = br_flush;
    assign poison_IQ      = br_flush;
    assign poison_ID      = br_flush;
    assign poison_RF      = br_flush;
    assign poison_EX1     = br_flush | hd_flush_RF_EX1; // 分支失败或数据冒险时就地截断并转化为 NOP 气泡
    assign poison_BR      = stall_EX1 | br_flush;
    // 后端乘除法阻塞或发生全局冲刷时，就地截断并转化为 NOP 气泡，彻底防止 EX1 阶段的推测性指令逃逸至 BR

    // =========================================================================
    // Stage 1 & 2: F1 & F2 级 (程序计数器生成、双字并行取指与分支预测并行查表)
    // =========================================================================
    
    // 物理信号连线声明
    logic [31:0] f1_pc_0, f1_pc_1;      // F1 级并行生成的双路 PC 虚线
    logic [31:0] actual_next_pc;        // 多路选择器裁决出的下一周期绝对物理 PC 值
    logic [31:0] br_actual_target;      // 后端 BR 级计算出的真实控制流目标跳转地址
    logic [31:0] trap_pc;               // CSR 异常处理单元生成的陷阱中断入口地址
    
    assign f1_pc_1 = f1_pc_0 + 4;       // 双字对齐的次路取指地址生成
    assign irom_addr = f1_pc_0;         // 绑定 I-ROM 物理驱动总线

    // 🌟 核心控制流多路选择决策链 (PC Selector Priority Tree)
    // 优先级严格限制：异常陷阱响应 (Trap) > 后端真实控制流纠正 (BR Mispredict) > 前端 TAGE 覆盖微冲刷 > 顺序 +8 推进
    assign actual_next_pc = br_take_trap   ? trap_pc :
                            br_mispredict  ? br_actual_target :
                            f5_micro_flush ? (f5_pred_taken_0 ? f5_pred_tgt_0 : f5_pred_tgt_1) :
                            stall_frontend ? f1_pc_0 :
                                             (f1_pc_0 + 8);

    // 程序计数器 (Program Counter) 物理寄存器例化
    PC #(DATAWIDTH, RESET_VAL) pc_inst (
        .clk(cpu_clk), 
        .rst(cpu_rst),
        .npc(actual_next_pc), 
        .pc_out(f1_pc_0)
    );

    // F1 -> F2 级流水线时序寄存器屏障例化
    logic f2_valid; 
    logic [31:0] f2_pc_0, f2_pc_1;
    logic [31:0] f2_inst_0, f2_inst_1;
    
    F1_F2_Reg #(DATAWIDTH) f1_f2_reg (
        .clk(cpu_clk),
        .rst(cpu_rst),
        .stall(stall_frontend),
        .poison(poison_F1_F4),
        .f1_pc_0(f1_pc_0),
        .f1_pc_1(f1_pc_1),
        .f1_inst_0(f1_inst_0),
        .f1_inst_1(f1_inst_1),
        .f2_pc_0(f2_pc_0),
        .f2_pc_1(f2_pc_1),
        .f2_inst_0(f2_inst_0),
        .f2_inst_1(f2_inst_1),
        .f2_valid(f2_valid)
    );
    
    // 拆分 64-bit I-ROM 物理总线至非对称的双向单字通道
    logic [31:0] f1_inst_0, f1_inst_1;
    assign f1_inst_0 = irom_data[31:0];
    assign f1_inst_1 = irom_data[63:32];

    // 分支预测器 (Branch Predictor) 双路并行物理例化 (TAGE-like / BHT 混合拓扑)
    logic f2_pred_taken_0, f2_pred_taken_1;
    logic [31:0] f2_pred_tgt_0, f2_pred_tgt_1;
    logic br_is_jump_or_branch, br_actual_taken;
    logic [31:0] br_pc;

    // 主路分支预测器 (处理 PC_0 处的跳转控制流)
    BranchPredictor #(32, 10) bp_inst_0 (
        .clk(cpu_clk), 
        .if1_pc(f1_pc_0), 
        .if2_pc(f2_pc_0),
        .if2_pred_taken(f2_pred_taken_0), 
        .if2_pred_target(f2_pred_tgt_0),
        .ex_is_branch(br_is_jump_or_branch), 
        .ex_pc(br_pc), 
        .ex_actual_taken(br_actual_taken), 
        .ex_actual_target(br_actual_target)
    );
    
    // 次路分支预测器 (处理 PC_1 处的跳转控制流，不更新预测存储阵列以防止硬件端口物理写入冲突)
    BranchPredictor #(32, 10) bp_inst_1 (
        .clk(cpu_clk), 
        .if1_pc(f1_pc_1), 
        .if2_pc(f2_pc_1),
        .if2_pred_taken(f2_pred_taken_1), 
        .if2_pred_target(f2_pred_tgt_1),
        .ex_is_branch(1'b0), 
        .ex_pc(32'b0), 
        .ex_actual_taken(1'b0), 
        .ex_actual_target(32'b0)
    );

    // =========================================================================
    // Stage 3 & 4: F3 & F4 级 (取指延时、指令对齐与预测结果同步)
    // =========================================================================

    // F2 -> F3 级流水线寄存器屏障
    logic f3_valid; 
    logic [31:0] f3_pc_0, f3_pc_1, f3_inst_0, f3_inst_1;
    
    F2_F3_Reg #(DATAWIDTH) f2_f3_reg (
        .clk(cpu_clk), 
        .rst(cpu_rst), 
        .stall(stall_frontend), 
        .poison(poison_F1_F4),
        .f2_valid(f2_valid), 
        .f2_pc_0(f2_pc_0), 
        .f2_pc_1(f2_pc_1), 
        .f2_inst_0(f2_inst_0), 
        .f2_inst_1(f2_inst_1),
        .f3_valid(f3_valid), 
        .f3_pc_0(f3_pc_0), 
        .f3_pc_1(f3_pc_1), 
        .f3_inst_0(f3_inst_0), 
        .f3_inst_1(f3_inst_1)
    );

    // F3 -> F4 级流水线寄存器屏障
    logic f4_valid; 
    logic [31:0] f4_pc_0, f4_pc_1, f4_inst_0, f4_inst_1;
    
    F3_F4_Reg #(DATAWIDTH) f3_f4_reg (
        .clk(cpu_clk), 
        .rst(cpu_rst), 
        .stall(stall_frontend), 
        .poison(poison_F1_F4),
        .f3_valid(f3_valid), 
        .f3_pc_0(f3_pc_0), 
        .f3_pc_1(f3_pc_1), 
        .f3_inst_0(f3_inst_0), 
        .f3_inst_1(f3_inst_1),
        .f4_valid(f4_valid), 
        .f4_pc_0(f4_pc_0), 
        .f4_pc_1(f4_pc_1), 
        .f4_inst_0(f4_inst_0), 
        .f4_inst_1(f4_inst_1)
    );

    // 🌟 预测信号的时序重同步 (Predict Signal Resynchronization) 与 预译码屏蔽 (Pre-Decode Masking)
    
    // 1. 提取 F2 阶段返回指令的低 7 位操作码 (Opcode)
    wire [6:0] f2_opcode_0 = f2_inst_0[6:0];
    wire [6:0] f2_opcode_1 = f2_inst_1[6:0];

    // 2. 粗略预译码：判断是否为真实的控制流指令
    //    Branch(1100011), JAL(1101111), JALR(1100111)
    wire f2_is_ctrl_0 = (f2_opcode_0 == 7'b1100011) | (f2_opcode_0 == 7'b1101111) | (f2_opcode_0 == 7'b1100111);
    wire f2_is_ctrl_1 = (f2_opcode_1 == 7'b1100011) | (f2_opcode_1 == 7'b1101111) | (f2_opcode_1 == 7'b1100111);

    // 3. 拦截过滤：只有在真正是控制流指令的前提下，才允许采信 TAGE/BHT 的 Taken 预测
    wire real_f2_pred_taken_0 = f2_pred_taken_0 & f2_is_ctrl_0;
    wire real_f2_pred_taken_1 = f2_pred_taken_1 & f2_is_ctrl_1;

    logic f4_pred_taken_0, f4_pred_taken_1;
    logic [31:0] f4_pred_tgt_0, f4_pred_tgt_1;
    
    // 4. 将过滤后的纯净预测信号旁路至 F4 级
    assign {f4_pred_taken_0, f4_pred_tgt_0} = f3_valid ? {real_f2_pred_taken_0, f2_pred_tgt_0} : 33'b0;
    assign {f4_pred_taken_1, f4_pred_tgt_1} = f3_valid ? {real_f2_pred_taken_1, f2_pred_tgt_1} : 33'b0;

    // =========================================================================
    // Stage 5: F5 级 (微冲刷决策与非对称缓冲注入)
    // =========================================================================
    
    logic f5_valid; 
    logic [31:0] f5_pc_0, f5_pc_1, f5_inst_0, f5_inst_1;
    logic f5_pred_taken_0, f5_pred_taken_1; 
    logic [31:0] f5_pred_tgt_0, f5_pred_tgt_1;
    
    F4_F5_Reg #(DATAWIDTH) f4_f5_reg (
        .clk(cpu_clk), 
        .rst(cpu_rst), 
        .stall(stall_frontend), 
        .poison(poison_F5),
        .f4_valid(f4_valid), 
        .f4_pc_0(f4_pc_0), .f4_pc_1(f4_pc_1), .f4_inst_0(f4_inst_0), .f4_inst_1(f4_inst_1),
        .f4_pred_taken_0(f4_pred_taken_0), .f4_pred_taken_1(f4_pred_taken_1), 
        .f4_pred_tgt_0(f4_pred_tgt_0), .f4_pred_tgt_1(f4_pred_tgt_1),
        
        .f5_valid(f5_valid), 
        .f5_pc_0(f5_pc_0), .f5_pc_1(f5_pc_1), .f5_inst_0(f5_inst_0), .f5_inst_1(f5_inst_1),
        .f5_pred_taken_0(f5_pred_taken_0), .f5_pred_taken_1(f5_pred_taken_1), 
        .f5_pred_tgt_0(f5_pred_tgt_0), .f5_pred_tgt_1(f5_pred_tgt_1)
    );
    
    // 生成局部微冲刷信号：只要双字中任意一条指令预测为 Taken，即触发 F1-F4 的推测状态废弃
    assign f5_micro_flush = f5_valid & (f5_pred_taken_0 | f5_pred_taken_1);

    // =========================================================================
    // D-Block: 解耦中端 (非对称环形队列与译码器)
    // =========================================================================
    
    // --- 指令队列 (Instruction Queue) 物理例化 ---
    // 负责吸收前端 64-bit 带宽带来的吞吐盈余，向后端提供平滑的 32-bit 单发流
    logic id_valid_raw, id_valid; 
    logic [31:0] id_pc, id_inst_raw, id_inst;
    logic id_pred_taken; 
    logic [31:0] id_pred_target;
    
    InstructionQueue #(8, 32) iq_inst (
        .clk(cpu_clk), 
        .rst(cpu_rst), 
        .flush(poison_IQ), // 接入最高优先级的后端真实异常重置网络
        
        // Push 端口 0 (第一条指令无条件尝试推入)
        .push_valid_0(f5_valid), 
        .push_pc_0(f5_pc_0), .push_inst_0(f5_inst_0), 
        .push_pred_taken_0(f5_pred_taken_0), .push_pred_target_0(f5_pred_tgt_0),
        
        // Push 端口 1 (若第一条指令发生跳转，则第二条指令处于被覆盖的阴影区，强制使其无效)
        .push_valid_1(f5_valid & ~f5_pred_taken_0), 
        .push_pc_1(f5_pc_1), .push_inst_1(f5_inst_1), 
        .push_pred_taken_1(f5_pred_taken_1), .push_pred_target_1(f5_pred_tgt_1),
        
        .almost_full(iq_almost_full), // 触发 F1-F5 反压的边界信号
        
        // Pop 端口 (单字出队至 ID 级)
        .pop_ready(~stall_IQ_pop), 
        .pop_valid(id_valid_raw),
        .pop_pc(id_pc), 
        .pop_inst(id_inst_raw), 
        .pop_pred_taken(id_pred_taken), 
        .pop_pred_target(id_pred_target)
    );

    // ID 级分布式注毒拦截器
    // 若系统发生冲刷，强行向后端注入 NOP 气泡 (0x00000013 即 addi x0, x0, 0)
    assign id_valid = id_valid_raw & ~poison_ID;
    assign id_inst  = id_valid ? id_inst_raw : 32'h00000013; 
    
    logic [31:0] id_ret_pc = id_pc + 4; // 提前计算返回地址，切断 BranchUnit 到 ID 的时序长径
    
    // 乘除法扩展 (M-Extension) 预解码标识
    logic id_is_M = (id_inst[6:0] == 7'b0110011) && (id_inst[31:25] == 7'b0000001);

    // =========================================================================
    // 控制流译码器 (Control & Decoder Modules)
    // =========================================================================
    logic id_IsBranch, id_RegWen, id_MemWen, id_AluSrcB, id_CsrWen, id_CsrImmSel, id_IsEcall, id_IsEbreak, id_IsMret;
    logic [1:0] id_JmpType, id_WbSel, id_AluSrcA, id_CsrOp;
    logic [3:0] id_alu_ctrl; 
    logic [31:0] id_imm, id_branch_target;

    Control control_inst (
        .inst(id_inst), 
        .IsBranch(id_IsBranch), .JmpType(id_JmpType), 
        .RegWen(id_RegWen), .MemWen(id_MemWen), .WbSel(id_WbSel), 
        .AluSrcA(id_AluSrcA), .AluSrcB(id_AluSrcB), 
        .CsrWen(id_CsrWen), .CsrOp(id_CsrOp), .CsrImmSel(id_CsrImmSel), 
        .IsEcall(id_IsEcall), .IsEbreak(id_IsEbreak), .IsMret(id_IsMret)
    );
    
    IMMGEN #(DATAWIDTH) immgen_inst (
        .instr(id_inst), 
        .imm(id_imm)
    );
    
    ACTL actl_inst (
        .opcode(id_inst[6:0]), 
        .funct3(id_inst[14:12]), 
        .funct7(id_inst[31:25]), 
        .alu_ctrl(id_alu_ctrl)
    );
    
    assign id_branch_target = id_pc + id_imm; // ID 级预计算分支目标地址

    // =========================================================================
    // Stage 6: RF 级 (通用寄存器组读取与译码信息传递)
    // =========================================================================
    
    logic rf_valid, rf_is_M, rf_RegWen, rf_MemWen, rf_IsBranch, rf_AluSrcB, rf_CsrWen, rf_CsrImmSel, rf_IsEcall, rf_IsEbreak, rf_IsMret;
    logic [31:0] rf_pc, rf_inst, rf_imm, rf_branch_target, rf_ret_pc, rf_pred_target;
    logic [4:0]  rf_rd, rf_rs1, rf_rs2; 
    logic [1:0]  rf_JmpType, rf_WbSel, rf_AluSrcA, rf_CsrOp;
    logic [3:0]  rf_alu_ctrl; 
    logic [2:0]  rf_funct3; 
    logic [11:0] rf_csr_idx; 
    logic rf_pred_taken;

    ID_RF_Reg #(DATAWIDTH) id_rf_reg (
        .clk(cpu_clk), .rst(cpu_rst), .stall(stall_RF), .poison(poison_RF),
        .id_valid(id_valid), .id_is_M(id_is_M), .id_pc(id_pc), .id_inst(id_inst), .id_imm(id_imm), .id_branch_target(id_branch_target), .id_ret_pc(id_ret_pc),
        .id_rd(id_inst[11:7]), .id_rs1(id_inst[19:15]), .id_rs2(id_inst[24:20]),
        .id_RegWen(id_RegWen), .id_MemWen(id_MemWen), .id_IsBranch(id_IsBranch), .id_AluSrcB(id_AluSrcB), .id_JmpType(id_JmpType), .id_WbSel(id_WbSel), .id_AluSrcA(id_AluSrcA),
        .id_alu_ctrl(id_alu_ctrl), .id_funct3(id_inst[14:12]), .id_csr_idx(id_inst[31:20]), .id_CsrWen(id_CsrWen), .id_CsrImmSel(id_CsrImmSel), .id_IsEcall(id_IsEcall), .id_IsEbreak(id_IsEbreak), .id_IsMret(id_IsMret), .id_CsrOp(id_CsrOp),
        .id_pred_taken(id_pred_taken), .id_pred_target(id_pred_target),
        
        .rf_valid(rf_valid), .rf_is_M(rf_is_M), .rf_pc(rf_pc), .rf_inst(rf_inst), .rf_imm(rf_imm), .rf_branch_target(rf_branch_target), .rf_ret_pc(rf_ret_pc),
        .rf_rd(rf_rd), .rf_rs1(rf_rs1), .rf_rs2(rf_rs2),
        .rf_RegWen(rf_RegWen), .rf_MemWen(rf_MemWen), .rf_IsBranch(rf_IsBranch), .rf_AluSrcB(rf_AluSrcB), .rf_JmpType(rf_JmpType), .rf_WbSel(rf_WbSel), .rf_AluSrcA(rf_AluSrcA),
        .rf_alu_ctrl(rf_alu_ctrl), .rf_funct3(rf_funct3), .rf_csr_idx(rf_csr_idx), .rf_CsrWen(rf_CsrWen), .rf_CsrImmSel(rf_CsrImmSel), .rf_IsEcall(rf_IsEcall), .rf_IsEbreak(rf_IsEbreak), .rf_IsMret(rf_IsMret), .rf_CsrOp(rf_CsrOp),
        .rf_pred_taken(rf_pred_taken), .rf_pred_target(rf_pred_target)
    );

    logic [31:0] rf_rs1_data_raw, rf_rs2_data_raw; 
    logic [31:0] wb_data; 
    logic [4:0]  wb_rd; 
    logic        wb_RegWen;
    
    // 🌟 修正项：严格拦截被注毒指令的物理状态写入
    RF #(5, DATAWIDTH) u_rf (
        .clk(cpu_clk), .rst(cpu_rst), .wen(wb_valid & wb_RegWen), .waddr(wb_rd), .wdata(wb_data),
        .rR1(rf_rs1), .rR2(rf_rs2), .rR1_data(rf_rs1_data_raw), .rR2_data(rf_rs2_data_raw)
    );

    // =========================================================================
    // Stage 7: EX1 级 (执行逻辑与前递闭环)
    // =========================================================================

    logic ex1_valid, ex1_is_M, ex1_RegWen, ex1_MemWen, ex1_IsBranch, ex1_AluSrcB, ex1_CsrWen, ex1_CsrImmSel, ex1_IsEcall, ex1_IsEbreak, ex1_IsMret;
    logic [31:0] ex1_pc, ex1_inst, ex1_imm, ex1_branch_target, ex1_ret_pc, ex1_pred_target;
    logic [31:0] ex1_rs1_data_raw, ex1_rs2_data_raw; // 接收来自 RF 级的原始读出数据
    logic [4:0]  ex1_rd, ex1_rs1, ex1_rs2;
    logic [1:0]  ex1_JmpType, ex1_WbSel, ex1_AluSrcA, ex1_CsrOp; 
    logic [3:0]  ex1_alu_ctrl; 
    logic [2:0]  ex1_funct3; 
    logic [11:0] ex1_csr_idx; 
    logic ex1_pred_taken;

    RF_EX1_Reg #(DATAWIDTH) rf_ex1_reg (
        .clk(cpu_clk), .rst(cpu_rst), .stall(stall_EX1), .poison(poison_EX1),
        .rf_valid(rf_valid), .rf_is_M(rf_is_M), .rf_pc(rf_pc), .rf_inst(rf_inst), .rf_imm(rf_imm), .rf_branch_target(rf_branch_target), .rf_ret_pc(rf_ret_pc),
        .rf_fw_rs1_data(rf_rs1_data_raw), .rf_fw_rs2_data(rf_rs2_data_raw), .rf_rd(rf_rd), // 将未前递的数据送入 EX1
        .rf_RegWen(rf_RegWen), .rf_MemWen(rf_MemWen), .rf_IsBranch(rf_IsBranch), .rf_AluSrcB(rf_AluSrcB), .rf_JmpType(rf_JmpType), .rf_WbSel(rf_WbSel), .rf_AluSrcA(rf_AluSrcA),
        .rf_alu_ctrl(rf_alu_ctrl), .rf_funct3(rf_funct3), .rf_csr_idx(rf_csr_idx), .rf_CsrWen(rf_CsrWen), .rf_CsrImmSel(rf_CsrImmSel), .rf_IsEcall(rf_IsEcall), .rf_IsEbreak(rf_IsEbreak), .rf_IsMret(rf_IsMret), .rf_CsrOp(rf_CsrOp),
        .rf_pred_taken(rf_pred_taken), .rf_pred_target(rf_pred_target),
        
        .ex1_valid(ex1_valid), .ex1_is_M(ex1_is_M), .ex1_pc(ex1_pc), .ex1_inst(ex1_inst), .ex1_imm(ex1_imm), .ex1_branch_target(ex1_branch_target), .ex1_ret_pc(ex1_ret_pc),
        .ex1_fw_rs1_data(ex1_rs1_data_raw), .ex1_fw_rs2_data(ex1_rs2_data_raw), .ex1_rd(ex1_rd),
        .ex1_RegWen(ex1_RegWen), .ex1_MemWen(ex1_MemWen), .ex1_IsBranch(ex1_IsBranch), .ex1_AluSrcB(ex1_AluSrcB), .ex1_JmpType(ex1_JmpType), .ex1_WbSel(ex1_WbSel), .ex1_AluSrcA(ex1_AluSrcA),
        .ex1_alu_ctrl(ex1_alu_ctrl), .ex1_funct3(ex1_funct3), .ex1_csr_idx(ex1_csr_idx), .ex1_CsrWen(ex1_CsrWen), .ex1_CsrImmSel(ex1_CsrImmSel), .ex1_IsEcall(ex1_IsEcall), .ex1_IsEbreak(ex1_IsEbreak), .ex1_IsMret(ex1_IsMret), .ex1_CsrOp(ex1_CsrOp),
        .ex1_pred_taken(ex1_pred_taken), .ex1_pred_target(ex1_pred_target)
    );
    
    // 从指令中直接提取以保障前递多路选择器的实时性
    assign ex1_rs1 = ex1_inst[19:15];
    assign ex1_rs2 = ex1_inst[24:20];

    // 🌟 修正项：前递网络移位至 EX1 级实时判决，确保与数据流周期绝对对齐
    logic [2:0] real_ex_forward_A, real_ex_forward_B;
    logic br_RegWen, mem1_RegWen, mem2_RegWen; 
    logic [4:0] br_rd, mem1_rd, mem2_rd;
    logic [31:0] br_fw_data, mem1_fw_data, mem2_fw_data;

    // 🌟 修正项：前递网络必须且只能监听有效指令，彻底切断幽灵数据的旁路污染
    ForwardingUnit fw_inst (
        .id_rs1(ex1_rs1), .id_rs2(ex1_rs2),
        .ex_RegWen  (br_valid & br_RegWen),     .ex_rd  (br_rd),   // 下一级：BR
        .mem1_RegWen(mem1_valid & mem1_RegWen), .mem1_rd(mem1_rd), // 下下级：MEM1
        .mem2_RegWen(mem2_valid & mem2_RegWen), .mem2_rd(mem2_rd), // 下下下级：MEM2
        .wb_RegWen  (wb_valid & wb_RegWen),     .wb_rd  (wb_rd),   // 下下下下级：WB
        .id_forward_A(real_ex_forward_A), .id_forward_B(real_ex_forward_B)
    );

    logic [31:0] ex1_fw_rs1_data, ex1_fw_rs2_data;
    always_comb begin
        case(real_ex_forward_A)
            3'b100: ex1_fw_rs1_data = br_fw_data;
            3'b011: ex1_fw_rs1_data = mem1_fw_data;
            3'b010: ex1_fw_rs1_data = mem2_fw_data;
            3'b001: ex1_fw_rs1_data = wb_data;
            default: ex1_fw_rs1_data = ex1_rs1_data_raw;
        endcase
        case(real_ex_forward_B)
            3'b100: ex1_fw_rs2_data = br_fw_data;
            3'b011: ex1_fw_rs2_data = mem1_fw_data;
            3'b010: ex1_fw_rs2_data = mem2_fw_data;
            3'b001: ex1_fw_rs2_data = wb_data;
            default: ex1_fw_rs2_data = ex1_rs2_data_raw;
        endcase
    end

    // ALU 与 MDU 运算单元逻辑
    logic [31:0] ex1_alu_op1, ex1_alu_op2, ex1_alu_res, final_ex_alu_res;
    assign ex1_alu_op1 = (ex1_AluSrcA == 2'b10) ? 32'b0 : (ex1_AluSrcA == 2'b01) ? ex1_pc : ex1_fw_rs1_data;
    assign ex1_alu_op2 = ex1_AluSrcB ? ex1_imm : ex1_fw_rs2_data;

    ALU #(DATAWIDTH) alu_inst (.A(ex1_alu_op1), .B(ex1_alu_op2), .ALUControl(ex1_alu_ctrl), .Result(ex1_alu_res));
    
    logic [31:0] mdu_res; logic mdu_busy, mdu_done;
    logic mdu_start;
    always_comb mdu_start = ex1_valid && ex1_is_M && !mdu_busy && !mdu_done;
    always_comb stall_req_mdu = ex1_valid && ex1_is_M && !mdu_done;
    
    MDU mdu_inst (
        .clk(cpu_clk), .rst(cpu_rst), .start(mdu_start), 
        .funct3(ex1_funct3), .a(ex1_fw_rs1_data), .b(ex1_fw_rs2_data), 
        .result(mdu_res), .busy(mdu_busy), .done(mdu_done)
    );
    
    assign final_ex_alu_res = ex1_is_M ? mdu_res : ex1_alu_res;

    logic [31:0] ex1_agu_res;
    AGU #(DATAWIDTH) agu_inst (.base(ex1_fw_rs1_data), .offset(ex1_imm), .addr(ex1_agu_res));

    // =========================================================================
    // Stage 8: BR 级 (分支物理决断与 CSR 写)
    // =========================================================================
    
    logic br_valid, br_MemWen, br_IsBranch;
    logic [31:0] br_inst, br_ret_pc, br_branch_target, br_alu_res, br_fw_rs1_data, br_fw_rs2_data, br_agu_res, br_csr_rdata, br_pred_target;
    logic [1:0] br_JmpType, br_WbSel; logic [2:0] br_funct3; logic br_pred_taken;

    EX1_BR_Reg #(DATAWIDTH) ex1_br_reg (
        .clk(cpu_clk), .rst(cpu_rst), .stall(1'b0), .poison(poison_BR),
        .ex1_valid(ex1_valid), .ex1_pc(ex1_pc), .ex1_inst(ex1_inst), .ex1_ret_pc(ex1_ret_pc), .ex1_branch_target(ex1_branch_target),
        .ex1_alu_res(final_ex_alu_res), .ex1_fw_rs1_data(ex1_fw_rs1_data), .ex1_fw_rs2_data(ex1_fw_rs2_data), .ex1_agu_res(ex1_agu_res),
        .ex1_rd(ex1_rd), .ex1_RegWen(ex1_RegWen), .ex1_MemWen(ex1_MemWen), .ex1_IsBranch(ex1_IsBranch), .ex1_JmpType(ex1_JmpType), .ex1_WbSel(ex1_WbSel), .ex1_funct3(ex1_funct3),
        .ex1_pred_taken(ex1_pred_taken), .ex1_pred_target(ex1_pred_target),
        
        .br_valid(br_valid), .br_pc(br_pc), .br_inst(br_inst), .br_ret_pc(br_ret_pc), .br_branch_target(br_branch_target),
        .br_alu_res(br_alu_res), .br_fw_rs1_data(br_fw_rs1_data), .br_fw_rs2_data(br_fw_rs2_data), .br_agu_res(br_agu_res),
        .br_rd(br_rd), .br_RegWen(br_RegWen), .br_MemWen(br_MemWen), .br_IsBranch(br_IsBranch), .br_JmpType(br_JmpType), .br_WbSel(br_WbSel), .br_funct3(br_funct3),
        .br_pred_taken(br_pred_taken), .br_pred_target(br_pred_target)
    );

    // 分支比对信号已在前端 F1 阶段预先声明，此处直接赋值
    assign br_is_jump_or_branch = br_IsBranch || (br_JmpType != 2'b00);

    // 🌟 修正项：已移除悬空的 pc_plus_4 端口
    BranchUnit #(DATAWIDTH) bu_inst (
        .imm(32'b0), .rs1_data(br_fw_rs1_data), .rs2_data(br_fw_rs2_data),
        .precalc_branch_target(br_branch_target), .precalc_pc_plus_4(br_ret_pc),
        .trap_pc(trap_pc), .Branch(br_IsBranch), .Jump(br_JmpType), .funct3(br_funct3),
        .next_pc(br_actual_target), .actual_taken(br_actual_taken) 
    );
    
    // 分支比对纠错逻辑
    logic target_mismatch, branch_mispredict, target_mispredict;
    always_comb begin
        if (br_JmpType == 2'b10) target_mismatch = (br_actual_target != br_pred_target);
        else if (br_JmpType == 2'b11) target_mismatch = (br_pred_target != trap_pc);
        else target_mismatch = (br_pred_target != br_branch_target);
    end
    assign branch_mispredict = br_actual_taken ^ br_pred_taken;
    assign target_mispredict = br_actual_taken & br_pred_taken & target_mismatch;
    assign br_mispredict = br_valid & ((br_is_jump_or_branch & (branch_mispredict | target_mispredict)) | (~br_is_jump_or_branch & br_pred_taken));

    // CSR 解析与状态更新逻辑
    logic br_IsEcall, br_IsEbreak, br_IsMret, br_CsrWen, br_CsrImmSel; 
    logic [11:0] br_csr_idx; 
    logic [1:0] br_CsrOp;
    
    assign br_IsEcall = br_inst[6:0] == 7'b1110011 && br_inst[31:20] == 12'h000;
    assign br_IsEbreak = br_inst[6:0] == 7'b1110011 && br_inst[31:20] == 12'h001;
    assign br_IsMret = br_inst[6:0] == 7'b1110011 && br_inst[31:20] == 12'h302;
    assign br_CsrWen = br_inst[6:0] == 7'b1110011 && br_inst[14:12] != 3'b000;
    assign br_CsrImmSel = br_inst[14];
    assign br_CsrOp = {br_inst[13:12] == 2'b11, br_inst[13:12] == 2'b10};
    assign br_csr_idx = br_inst[31:20];

    logic [31:0] br_csr_wdata;
    assign br_csr_wdata = br_CsrImmSel ? {27'b0, br_inst[19:15]} : br_fw_rs1_data;
    logic br_actual_csr_wen = br_valid && br_CsrWen && !((br_CsrOp != 2'b00) && (br_inst[19:15] == 5'b0));
    assign br_take_trap = br_valid & (br_IsEcall | br_IsEbreak | br_IsMret);

    CSR #(DATAWIDTH) csr_inst (
        .clk(cpu_clk), .rst(cpu_rst), .pc(br_pc),
        .csr_idx(br_csr_idx), .wdata(br_csr_wdata), .csr_op(br_CsrOp), .csr_wen(br_actual_csr_wen),
        .ecall(br_valid & br_IsEcall), .ebreak(br_valid & br_IsEbreak), .mret(br_valid & br_IsMret),
        .rdata(br_csr_rdata), .trap_pc(trap_pc)
    );
    assign br_fw_data = (br_WbSel == 2'b01) ? br_ret_pc : (br_WbSel == 2'b11) ? br_csr_rdata : br_alu_res;

    // =========================================================================
    // Stage 9, 10, 11: MEM1, MEM2, WB 物理级联
    // =========================================================================
    
    logic mem1_valid, mem1_MemWen; 
    logic [31:0] mem1_pc, mem1_inst, mem1_ret_pc, mem1_alu_res, mem1_fw_rs2_data, mem1_agu_res, mem1_csr_rdata; 
    logic [1:0] mem1_WbSel; 
    logic [2:0] mem1_funct3;
    
    BR_MEM1_Reg #(DATAWIDTH) br_mem1_reg (
        .clk(cpu_clk), .rst(cpu_rst), .stall(1'b0), .poison(1'b0),
        .br_valid(br_valid), .br_pc(br_pc), .br_inst(br_inst), .br_ret_pc(br_ret_pc), .br_alu_res(br_alu_res), .br_fw_rs2_data(br_fw_rs2_data), .br_agu_res(br_agu_res), .br_csr_rdata(br_csr_rdata), .br_rd(br_rd), .br_RegWen(br_RegWen), .br_MemWen(br_MemWen), .br_WbSel(br_WbSel), .br_funct3(br_funct3),
        .mem1_valid(mem1_valid), .mem1_pc(mem1_pc), .mem1_inst(mem1_inst), .mem1_ret_pc(mem1_ret_pc), .mem1_alu_res(mem1_alu_res), .mem1_fw_rs2_data(mem1_fw_rs2_data), .mem1_agu_res(mem1_agu_res), .mem1_csr_rdata(mem1_csr_rdata), .mem1_rd(mem1_rd), .mem1_RegWen(mem1_RegWen), .mem1_MemWen(mem1_MemWen), .mem1_WbSel(mem1_WbSel), .mem1_funct3(mem1_funct3)
    );
    
    assign perip_addr = mem1_agu_res;
    assign perip_wen  = mem1_valid & mem1_MemWen;
    
    StoreAlign #(DATAWIDTH) store_align_inst (
        .addr_offset(mem1_agu_res[1:0]), .wdata_in(mem1_fw_rs2_data), .size_mask(mem1_funct3[1:0]), 
        .MemWrite(mem1_valid & mem1_MemWen), .wmask_out(perip_mask), .wdata_out(perip_wdata)
    );
    
    // MEM1 级旁路网络的数据合并
    assign mem1_fw_data = (mem1_WbSel == 2'b01) ? mem1_ret_pc : (mem1_WbSel == 2'b11) ? mem1_csr_rdata : mem1_alu_res;

    logic mem2_valid; 
    logic [31:0] mem2_pc, mem2_inst, mem2_ret_pc, mem2_alu_res, mem2_agu_res, mem2_csr_rdata; 
    logic [1:0] mem2_WbSel; 
    logic [2:0] mem2_funct3;
    
    MEM1_MEM2_Reg #(DATAWIDTH) mem1_mem2_reg (
        .clk(cpu_clk), .rst(cpu_rst), .stall(1'b0), .poison(1'b0),
        .mem1_valid(mem1_valid), .mem1_pc(mem1_pc), .mem1_inst(mem1_inst), .mem1_ret_pc(mem1_ret_pc), .mem1_alu_res(mem1_alu_res), .mem1_agu_res(mem1_agu_res), .mem1_csr_rdata(mem1_csr_rdata), .mem1_rd(mem1_rd), .mem1_RegWen(mem1_RegWen), .mem1_WbSel(mem1_WbSel), .mem1_funct3(mem1_funct3),
        .mem2_valid(mem2_valid), .mem2_pc(mem2_pc), .mem2_inst(mem2_inst), .mem2_ret_pc(mem2_ret_pc), .mem2_alu_res(mem2_alu_res), .mem2_agu_res(mem2_agu_res), .mem2_csr_rdata(mem2_csr_rdata), .mem2_rd(mem2_rd), .mem2_RegWen(mem2_RegWen), .mem2_WbSel(mem2_WbSel), .mem2_funct3(mem2_funct3)
    );
    
    logic [31:0] mem2_non_load_data;
    assign mem2_non_load_data = (mem2_WbSel == 2'b01) ? mem2_ret_pc : (mem2_WbSel == 2'b11) ? mem2_csr_rdata : mem2_alu_res;
    assign mem2_fw_data = (mem2_WbSel == 2'b10) ? perip_rdata : mem2_non_load_data;

    logic wb_valid; 
    logic [31:0] wb_pc, wb_inst, wb_non_load_data, wb_perip_rdata; 
    logic [1:0] wb_agu_res_1_0, wb_WbSel; 
    logic [2:0] wb_funct3;
    
    MEM2_WB_Reg #(DATAWIDTH) mem2_wb_reg (
        .clk(cpu_clk), .rst(cpu_rst), .stall(1'b0), .poison(1'b0),
        .mem2_valid(mem2_valid), .mem2_pc(mem2_pc), .mem2_inst(mem2_inst), .mem2_non_load_data(mem2_non_load_data), .mem2_perip_rdata(perip_rdata), .mem2_agu_res_1_0(mem2_agu_res[1:0]), .mem2_funct3(mem2_funct3), .mem2_WbSel(mem2_WbSel), .mem2_rd(mem2_rd), .mem2_RegWen(mem2_RegWen),
        .wb_valid(wb_valid), .wb_pc(wb_pc), .wb_inst(wb_inst), .wb_non_load_data(wb_non_load_data), .wb_perip_rdata(wb_perip_rdata), .wb_agu_res_1_0(wb_agu_res_1_0), .wb_funct3(wb_funct3), .wb_WbSel(wb_WbSel), .wb_rd(wb_rd), .wb_RegWen(wb_RegWen)
    );

    // 组合逻辑写入对齐 (纯净的 Load 字节提取与扩展)
    logic [7:0] wb_byte_data; 
    logic [15:0] wb_half_data; 
    logic [31:0] wb_rdata_ext;
    
    always_comb begin
        case(wb_agu_res_1_0)
            2'b00: wb_byte_data = wb_perip_rdata[ 7: 0]; 
            2'b01: wb_byte_data = wb_perip_rdata[15: 8];
            2'b10: wb_byte_data = wb_perip_rdata[23:16]; 
            2'b11: wb_byte_data = wb_perip_rdata[31:24];
        endcase
        wb_half_data = wb_agu_res_1_0[1] ? wb_perip_rdata[31:16] : wb_perip_rdata[15:0];
        case (wb_funct3)
            3'b000: wb_rdata_ext = {{24{wb_byte_data[7]}}, wb_byte_data}; 
            3'b100: wb_rdata_ext = {24'b0, wb_byte_data};
            3'b001: wb_rdata_ext = {{16{wb_half_data[15]}}, wb_half_data}; 
            3'b101: wb_rdata_ext = {16'b0, wb_half_data};
            default: wb_rdata_ext = wb_perip_rdata;
        endcase
    end
    assign wb_data = (wb_WbSel == 2'b10) ? wb_rdata_ext : wb_non_load_data;

    // =========================================================================
    // 危险检测与时序阻断网 (Hazard Detection Unit)
    // =========================================================================
    
    // 🌟 修正项：阻断毒药指令发起的非必要流水线挂起请求
    HazardDetectionUnit hd_inst (
        .id_rs1(rf_rs1), .id_rs2(rf_rs2), .id_opcode(rf_inst[6:0]),
        .ex_RegWen(ex1_valid & ex1_RegWen), .ex_WbSel(ex1_WbSel), .ex_rd(ex1_rd),
        .mem1_RegWen(br_valid & br_RegWen), .mem1_WbSel(br_WbSel), .mem1_rd(br_rd),
        .ls_RegWen(mem1_valid & mem1_RegWen), .ls_WbSel(mem1_WbSel), .ls_rd(mem1_rd),
        .stall_ID(hd_stall_RF), .flush_ID_EX(hd_flush_RF_EX1)
    );

    // =========================================================================
    // 🌟 DiffTest 指令提交与 CSR 影子同步网络
    // =========================================================================
`ifdef NPC_TEST
    import "DPI-C" context function void set_csr_scope();

    // 计算 BR 阶段新写值
    logic [31:0] br_next_csr_val;
    always_comb begin
        case(br_CsrOp)
            2'b00: br_next_csr_val = br_csr_wdata;
            2'b01: br_next_csr_val = br_csr_rdata | br_csr_wdata;
            2'b10: br_next_csr_val = br_csr_rdata & ~br_csr_wdata;
            default: br_next_csr_val = br_csr_wdata;
        endcase
    end

    // 专供 DiffTest 的旁路延迟管线 (Shadow Pipeline)
    logic        mem1_csr_wen_diff, mem2_csr_wen_diff, wb_csr_wen_diff;
    logic [11:0] mem1_csr_idx_diff, mem2_csr_idx_diff, wb_csr_idx_diff;
    logic [31:0] mem1_csr_val_diff, mem2_csr_val_diff, wb_csr_val_diff;
    logic        mem1_ecall_diff,   mem2_ecall_diff,   wb_ecall_diff;
    logic        mem1_ebreak_diff,  mem2_ebreak_diff,  wb_ebreak_diff;
    logic        mem1_mret_diff,    mem2_mret_diff,    wb_mret_diff;
    
    always_ff @(posedge cpu_clk) begin
        if (cpu_rst) begin
            mem1_csr_wen_diff <= 0; mem2_csr_wen_diff <= 0; wb_csr_wen_diff <= 0;
            mem1_ecall_diff   <= 0; mem2_ecall_diff   <= 0; wb_ecall_diff   <= 0;
            mem1_ebreak_diff  <= 0; mem2_ebreak_diff  <= 0; wb_ebreak_diff  <= 0;
            mem1_mret_diff    <= 0; mem2_mret_diff    <= 0; wb_mret_diff    <= 0;
        end else begin
            // 🌟 BR -> MEM1 
            mem1_csr_wen_diff <= br_valid & br_actual_csr_wen;
            mem1_ecall_diff   <= br_valid & br_IsEcall;
            mem1_ebreak_diff  <= br_valid & br_IsEbreak;
            mem1_mret_diff    <= br_valid & br_IsMret;
            mem1_csr_idx_diff <= br_csr_idx;
            mem1_csr_val_diff <= br_next_csr_val;

            // 🌟 MEM1 -> MEM2
            mem2_csr_wen_diff <= mem1_csr_wen_diff;
            mem2_csr_idx_diff <= mem1_csr_idx_diff;
            mem2_csr_val_diff <= mem1_csr_val_diff;
            mem2_ecall_diff   <= mem1_ecall_diff;
            mem2_ebreak_diff  <= mem1_ebreak_diff;
            mem2_mret_diff    <= mem1_mret_diff;

            // 🌟 MEM2 -> WB
            wb_csr_wen_diff   <= mem2_csr_wen_diff;
            wb_csr_idx_diff   <= mem2_csr_idx_diff;
            wb_csr_val_diff   <= mem2_csr_val_diff;
            wb_ecall_diff     <= mem2_ecall_diff;
            wb_ebreak_diff    <= mem2_ebreak_diff;
            wb_mret_diff      <= mem2_mret_diff;
        end
    end

    // DiffTest 专属影子 CSR 寄存器，由 WB 级统一结算
    logic [31:0] diff_mstatus = 32'h1800;
    logic [31:0] diff_mtvec   = 32'h0;
    logic [31:0] diff_mscratch= 32'h0;
    logic [31:0] diff_mepc    = 32'h0;
    logic [31:0] diff_mcause  = 32'h0;

    always_ff @(posedge cpu_clk) begin
        if (cpu_rst) begin
            diff_mstatus <= 32'h1800;
            diff_mtvec   <= 32'h0;
            diff_mscratch <= 32'h0;
            diff_mepc    <= 32'h0;
            diff_mcause  <= 32'h0;
        end else begin
            if (wb_ecall_diff) begin
                diff_mepc    <= wb_pc;
                diff_mcause  <= 32'h0000_000B;
                diff_mstatus <= {diff_mstatus[31:13], 2'b11, diff_mstatus[10:8], diff_mstatus[3], diff_mstatus[6:4], 1'b0, diff_mstatus[2:0]};
            end else if (wb_ebreak_diff) begin
                diff_mepc    <= wb_pc;
                diff_mcause  <= 32'h0000_0003;
                diff_mstatus <= {diff_mstatus[31:13], 2'b11, diff_mstatus[10:8], diff_mstatus[3], diff_mstatus[6:4], 1'b0, diff_mstatus[2:0]};
            end else if (wb_mret_diff) begin
                diff_mstatus <= {diff_mstatus[31:13], 2'b00, diff_mstatus[10:8], 1'b1, diff_mstatus[6:4], diff_mstatus[7], diff_mstatus[2:0]};
            end else if (wb_csr_wen_diff) begin
                case(wb_csr_idx_diff)
                    12'h300: diff_mstatus <= wb_csr_val_diff;
                    12'h305: diff_mtvec   <= wb_csr_val_diff;
                    12'h340: diff_mscratch <= wb_csr_val_diff;
                    12'h341: diff_mepc    <= wb_csr_val_diff;
                    12'h342: diff_mcause  <= wb_csr_val_diff;
                    default: ;
                endcase
            end
        end
    end

    export "DPI-C" function get_csr;
    function int get_csr(input int idx);
        case(idx)
            32'h300: return diff_mstatus;
            32'h305: return diff_mtvec;
            32'h340: return diff_mscratch;
            32'h341: return diff_mepc;
            32'h342: return diff_mcause;
            default: return 0;
        endcase
    endfunction

    initial begin
        set_csr_scope();
    end
`endif

endmodule
