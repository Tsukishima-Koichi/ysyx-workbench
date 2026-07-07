`timescale 1ns / 1ps
`include "defines.sv"
`default_nettype none

/**
 * myCPU_Dual — 双发射非对称解耦流水线
 * 前端 64-bit 取指 -> IQ 缓冲 -> 后端双路 ALU 并行执行
 * inst0: 全指令支持 (ALU/Branch/Load/Store/CSR/MDU)
 * inst1: 受限 (仅简单 ALU 指令, 无依赖时与 inst0 并行发射)
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
    input  wire  [31:0]  perip_rdata,   // 从存储器/外设返回的单字读取数据总线
    output logic         br_valid_out,   // BR stage valid (for dead_loop gating)
    output logic [31:0]  br_target_out   // BR stage branch target
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
    // 高扇出约束: 强制 EDA 工具复制寄存器，以空间换时序收敛
    (* max_fanout = "16" *) logic f5_micro_flush;   // F5→F1-F4 微冲刷广播
    (* max_fanout = "16" *) logic br_flush;          // BR→全流水线致命冲刷广播
    logic br_take_trap;                 // 异常中断/环境调用 (Trap/Ecall/Mret) 状态跳转使能
    logic br_mispredict_0;              // inst0 分支预测失败
    logic br_mispredict_1;              // inst1 分支预测失败 (Phase 4)
    logic hd_flush_RF_EX1_0;            // inst0 加载-使用冒险冲刷
    logic hd_flush_RF_EX1_1;            // inst1 加载-使用冒险冲刷

    // 分布式同步注毒网络 (Distributed Synchronization Poison Network)
    // 信号不接入触发器异步端，通过使能端与有效位（Valid Bit）强行改写为 1'b0 实现拦截
    // equivalent_register_removal=no: 防止综合器将注毒寄存器合并优化掉
    (* equivalent_register_removal = "no" *) logic poison_F1_F4;
    (* equivalent_register_removal = "no" *) logic poison_F5;
    (* equivalent_register_removal = "no" *) logic poison_IQ;
    (* equivalent_register_removal = "no" *) logic poison_ID;
    (* equivalent_register_removal = "no" *) logic poison_RF;
    (* equivalent_register_removal = "no" *) logic poison_EX1_0;
    (* equivalent_register_removal = "no" *) logic poison_EX1_1;
    (* equivalent_register_removal = "no" *) logic poison_BR_0;
    (* equivalent_register_removal = "no" *) logic poison_BR_1;

    // NLP (Next-Line Predictor) 信号
    logic        nlp_hit;
    logic [31:0] nlp_target;

    // TAGE 方向预测器信号
    logic        tage_f5_pred_taken;
    logic        tage_f5_has_provider;
    logic [1:0]  tage_f5_provider_idx;

    // NLP 流水线通道 (F1→F2→[bypass]→F4→F5)
    logic        f2_nlp_hit, f4_nlp_hit, f5_nlp_hit;
    logic [31:0] f2_nlp_target, f4_nlp_target, f5_nlp_target;

    // F5 聚合预测结果 (TAGE/BHT → 微冲刷目标)
    logic [31:0] f5_micro_target;

    // =========================================================================
    // 物理控制流拦截网络映射逻辑 (Control Pipeline Routing Logic)
    // =========================================================================
    assign stall_frontend = iq_almost_full;
    assign stall_EX1      = stall_req_mdu;
    assign stall_RF       = stall_EX1 | hd_stall_RF;
    assign stall_ID       = stall_RF; 
    assign stall_IQ_pop   = stall_ID;

    // Per-pipeline flush preparation (Phase 2: split signals, keep identical behavior)
    // br_mispredict_0 assigned later (after BranchUnit)
    assign br_mispredict_1 = 1'b0;  // Phase 4: add inst1 BranchUnit
    // hd_flush_RF_EX1_0 driven by HDU instance below
    assign hd_flush_RF_EX1_1 = hd_flush_RF_EX1_0;  // Same: load-use flushes both pipelines

    assign br_flush       = br_take_trap | br_mispredict_0 | br_mispredict_1;

    // 分布式拦截拓扑关系映射
    // early_flush: RF 级提前解析, 冲刷 F1→ID (比 BR 级提前 2 拍)
    assign poison_F1_F4   = br_flush | f5_micro_flush;
    assign poison_F5      = br_flush;
    assign poison_IQ      = br_flush;
    assign poison_ID      = br_flush;
    assign poison_RF      = br_flush;
    assign poison_EX1_0   = br_flush | hd_flush_RF_EX1_0;
    assign poison_EX1_1   = br_flush | hd_flush_RF_EX1_1;
    assign poison_BR_0    = stall_EX1 | br_flush;
    assign poison_BR_1    = stall_EX1 | br_flush;
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

    // 🌟 PC 选择器 (NLP 快径 + TAGE/NLP-aware 微冲刷 + RF 提前解析)
    assign actual_next_pc = br_take_trap    ? trap_pc :
                            br_mispredict_0 ? br_actual_target :
                            br_mispredict_1 ? br_actual_target_1 :
                            early_flush     ? early_flush_target :
                            f5_micro_flush  ? f5_micro_target :
                            stall_frontend  ? f1_pc_0 :
                            nlp_hit         ? nlp_target :
                                              (f1_pc_0 + 8);

    // 程序计数器 (Program Counter) 物理寄存器例化
    PC #(DATAWIDTH, RESET_VAL) pc_inst (
        .clk(cpu_clk),
        .rst(cpu_rst),
        .npc(actual_next_pc),
        .pc_out(f1_pc_0)
    );

    // NLP (Next-Line Predictor) — F1 级 0-cycle LUTRAM 快径预测器
    // 8-bit tag 消除索引碰撞，训练端口绑定到 BR 级
    NLP #(.INDEX_BITS(8), .TAG_BITS(8), .DATAWIDTH(DATAWIDTH)) nlp_inst (
        .clk(cpu_clk), .rst(cpu_rst),
        .f1_pc(f1_pc_0),
        .nlp_target(nlp_target), .nlp_hit(nlp_hit),
        // 学习所有真实分支/跳转 (排除 trap: ECALL/EBREAK/MRET)
        .update_valid(br_valid & (br_IsBranch | (br_JmpType == 2'b01) | (br_JmpType == 2'b10)) & br_actual_taken),
        .update_pc(br_pc), .update_target(br_actual_target)
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
        .f1_nlp_hit(nlp_hit),
        .f1_nlp_target(nlp_target),
        .f2_pc_0(f2_pc_0),
        .f2_pc_1(f2_pc_1),
        .f2_inst_0(f2_inst_0),
        .f2_inst_1(f2_inst_1),
        .f2_valid(f2_valid),
        .f2_nlp_hit(f2_nlp_hit),
        .f2_nlp_target(f2_nlp_target)
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
    logic [31:0] br_pc_1;  // inst1 BR PC

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

    // TAGE 方向预测器 — 4 表几何历史长度，F2→F3→F4→F5 内部流水线
    // 在高频下提供高精度方向预测，在 F5 覆盖 BHT 的预测结果
    wire [31:0] tage_ghr_unused;
    TAGE #(.NUM_TABLES(4), .INDEX_BITS(10), .TAG_BITS(8), .GHR_WIDTH(32)) tage_inst (
        .clk(cpu_clk), .rst(cpu_rst),
        .f2_pc(f2_pc_0),
        .f5_pred_taken(tage_f5_pred_taken),
        .f5_has_provider(tage_f5_has_provider),
        .f5_provider_idx(tage_f5_provider_idx),
        .update_valid(br_valid),
        .update_pc(br_pc),
        .update_taken(br_actual_taken),
        .update_is_branch(br_is_jump_or_branch),  // tables: all branches/jumps
        .update_ghr(br_IsBranch),                 // GHR: conditional branches only
        .ghr(tage_ghr_unused)
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

    // 预译码：无条件跳转 (JAL, JALR) 用于阻断同拍第二条指令推入 IQ
    wire f2_is_uncond_0 = (f2_opcode_0 == 7'b1101111) | (f2_opcode_0 == 7'b1100111);
    wire f2_is_uncond_1 = (f2_opcode_1 == 7'b1101111) | (f2_opcode_1 == 7'b1100111);

    // 3. 拦截过滤：只有在真正是控制流指令的前提下，才允许采信 BHT 的 Taken 预测
    wire real_f2_pred_taken_0 = f2_pred_taken_0 & f2_is_ctrl_0;
    wire real_f2_pred_taken_1 = f2_pred_taken_1 & f2_is_ctrl_1;

    logic f4_pred_taken_0, f4_pred_taken_1;
    logic [31:0] f4_pred_tgt_0, f4_pred_tgt_1;
    
    // 4. 将过滤后的纯净预测信号旁路至 F4 级
    assign {f4_pred_taken_0, f4_pred_tgt_0} = f3_valid ? {real_f2_pred_taken_0, f2_pred_tgt_0} : 33'b0;
    assign {f4_pred_taken_1, f4_pred_tgt_1} = f3_valid ? {real_f2_pred_taken_1, f2_pred_tgt_1} : 33'b0;
    // NLP 同样以 bypass 方式从 F2 旁路至 F4 (与 BTB 预测保持时序对齐)
    assign {f4_nlp_hit, f4_nlp_target} = f3_valid ? {f2_nlp_hit, f2_nlp_target} : {1'b0, 32'b0};

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
        .f4_nlp_hit(f4_nlp_hit), .f4_nlp_target(f4_nlp_target),

        .f5_valid(f5_valid),
        .f5_pc_0(f5_pc_0), .f5_pc_1(f5_pc_1), .f5_inst_0(f5_inst_0), .f5_inst_1(f5_inst_1),
        .f5_pred_taken_0(f5_pred_taken_0), .f5_pred_taken_1(f5_pred_taken_1),
        .f5_pred_tgt_0(f5_pred_tgt_0), .f5_pred_tgt_1(f5_pred_tgt_1),
        .f5_nlp_hit(f5_nlp_hit), .f5_nlp_target(f5_nlp_target)
    );
    
    // TAGE/NLP-aware 微冲刷 — TAGE(10-bit) 与 BTB(10-bit) 索引已对齐
    // TAGE 的 "add" 能力需要门控: 只有 BTB 命中 (有有效目标) 时才允许 TAGE 新增 taken 预测
    // 否则 T0 aliasing 导致非分支指令被误判为 taken，微冲刷重定向到垃圾地址 (如 0x0)
    wire tage_add_taken = tage_f5_has_provider && tage_f5_pred_taken && (f5_pred_tgt_0 != '0);
    wire f5_pc0_taken = f5_pred_taken_0 ?
        (tage_f5_has_provider ? tage_f5_pred_taken : 1'b1) :              // BHT taken: TAGE validates
        tage_add_taken;                                                    // TAGE adds with BTB gate
    wire f5_any_taken = f5_pc0_taken | f5_pred_taken_1;

    assign f5_micro_target = f5_pc0_taken    ? f5_pred_tgt_0 :
                             f5_pred_taken_1 ? f5_pred_tgt_1 :
                                               (f5_pc_0 + 32'd8);
    assign f5_micro_flush = f5_valid & (
        ( f5_nlp_hit & ~f5_any_taken) |          // NLP over-predict → undo
        (~f5_nlp_hit &  f5_any_taken)             // NLP missed → correct
    );


    // =========================================================================
    // =========================================================================
    // 后端别名: 桥接前端已声明信号与后端 inst0 信号
    // 这些信号在 F1-F5 段已声明, 此处 assign 连接而非重新声明
    // =========================================================================
    assign br_is_jump_or_branch = br_IsBranch_0 || (br_JmpType_0 != 2'b00);
    // br_actual_target, br_actual_taken, br_pc 在前端已声明, 在 BR 段赋值
    // br_valid, br_IsBranch, br_JmpType 的别名在各自的 assign/always 块中

    // 前端 NLP 训练用的 BR 信号 (桥接到 inst0)
    wire        br_valid    = br_valid_0;
    wire        br_IsBranch = br_IsBranch_0;
    wire [1:0]  br_JmpType  = br_JmpType_0;

    // cpu_dual.sv 需要的信号 (ex1 from inst0)
    wire ex1_valid          = ex1_valid_0;
    wire ex1_IsEbreak       = ex1_IsEbreak_0;
    wire [1:0] ex1_JmpType  = ex1_JmpType_0;
    wire [31:0] ex1_pc      = ex1_pc_0;
    wire [31:0] ex1_branch_target = ex1_br_tgt_0;
    wire [31:0] id_inst     = id_inst_0;
    // wb_valid, wb_pc for cpu_dual commit (inst0 only)
    wire wb_valid = wb_valid_0;
    wire [31:0] wb_pc = wb_pc_0;

    // =========================================================================
    // 双发射指令队列 (InstructionQueue)
    // =========================================================================
    logic [1:0]  dual_pop_count;
    logic        id_valid_raw_0, id_valid_raw_1;
    logic [31:0] id_pc_0, id_pc_1, id_inst_raw_0, id_inst_raw_1;
    logic        id_pred_taken_0, id_pred_taken_1;
    logic [31:0] id_pred_target_0, id_pred_target_1;

    InstructionQueue #(32, 32) iq_inst (
        .clk(cpu_clk), .rst(cpu_rst), .flush(poison_IQ),
        .push_valid_0(f5_valid & ~stall_frontend),
        .push_pc_0(f5_pc_0), .push_inst_0(f5_inst_0),
        .push_pred_taken_0(f5_pred_taken_0), .push_pred_target_0(f5_pred_tgt_0),
        // 仅当 inst0 不是无条件跳转时推入 inst1
        // 条件分支始终推入其延迟槽指令; 若分支实际跳转, br_flush 会清除错误路径
        .push_valid_1(f5_valid & ~stall_frontend &
                      ~((f5_inst_0[6:0] == 7'b1101111) | (f5_inst_0[6:0] == 7'b1100111))),
        .push_pc_1(f5_pc_1),
        .push_inst_1(f5_inst_1),
        .push_pred_taken_1(f5_pred_taken_1), .push_pred_target_1(f5_pred_tgt_1),
        .almost_full(iq_almost_full),
        .pop_ready(~stall_IQ_pop), .pop_count(dual_pop_count),
        .pop_valid_0(id_valid_raw_0), .pop_valid_1(id_valid_raw_1),
        .pop_pc_0(id_pc_0), .pop_pc_1(id_pc_1),
        .pop_inst_0(id_inst_raw_0), .pop_inst_1(id_inst_raw_1),
        .pop_pred_taken_0(id_pred_taken_0), .pop_pred_taken_1(id_pred_taken_1),
        .pop_pred_target_0(id_pred_target_0), .pop_pred_target_1(id_pred_target_1)
    );

    // ID 级毒药拦截 + NOP
    logic id_valid_0, id_valid_1;
    logic [31:0] id_inst_0, id_inst_1;
    assign id_valid_0 = id_valid_raw_0 & ~poison_ID;
    assign id_valid_1 = id_valid_raw_1 & ~poison_ID & id_valid_0;
    assign id_inst_0  = id_valid_0 ? id_inst_raw_0 : 32'h00000013;
    assign id_inst_1  = id_valid_1 ? id_inst_raw_1 : 32'h00000013;
    // Explicit funct3/rd/rs1/rs2 extraction to avoid potential part-select issues
    wire [2:0] id_f3_0 = {id_inst_0[14], id_inst_0[13], id_inst_0[12]};
    wire [2:0] id_f3_1 = {id_inst_1[14], id_inst_1[13], id_inst_1[12]};
    wire [4:0] id_rd_0  = {id_inst_0[11], id_inst_0[10], id_inst_0[9], id_inst_0[8], id_inst_0[7]};
    wire [4:0] id_rs1_0 = {id_inst_0[19], id_inst_0[18], id_inst_0[17], id_inst_0[16], id_inst_0[15]};
    wire [4:0] id_rs2_0 = {id_inst_0[24], id_inst_0[23], id_inst_0[22], id_inst_0[21], id_inst_0[20]};
    wire [4:0] id_rd_1  = {id_inst_1[11], id_inst_1[10], id_inst_1[9], id_inst_1[8], id_inst_1[7]};
    wire [4:0] id_rs1_1 = {id_inst_1[19], id_inst_1[18], id_inst_1[17], id_inst_1[16], id_inst_1[15]};
    wire [4:0] id_rs2_1 = {id_inst_1[24], id_inst_1[23], id_inst_1[22], id_inst_1[21], id_inst_1[20]};
    wire [31:0] id_ret_pc_0 = id_pc_0 + 4;
    wire [31:0] id_ret_pc_1 = id_pc_1 + 4;

    // =========================================================================
    // 双路译码
    // =========================================================================
    logic id_IsBranch_0, id_RegWen_0, id_MemWen_0, id_AluSrcB_0, id_CsrWen_0, id_CsrImmSel_0, id_IsEcall_0, id_IsEbreak_0, id_IsMret_0;
    logic [1:0] id_JmpType_0, id_WbSel_0, id_AluSrcA_0, id_CsrOp_0;
    logic [3:0] id_alu_ctrl_0;
    logic [31:0] id_imm_0, id_branch_target_0;
    wire id_is_M_0 = (id_inst_0[6:0] == 7'b0110011) && (id_inst_0[31:25] == 7'b0000001);

    Control c0(.inst(id_inst_0), .IsBranch(id_IsBranch_0), .JmpType(id_JmpType_0),
        .RegWen(id_RegWen_0), .MemWen(id_MemWen_0), .WbSel(id_WbSel_0),
        .AluSrcA(id_AluSrcA_0), .AluSrcB(id_AluSrcB_0),
        .CsrWen(id_CsrWen_0), .CsrOp(id_CsrOp_0), .CsrImmSel(id_CsrImmSel_0),
        .IsEcall(id_IsEcall_0), .IsEbreak(id_IsEbreak_0), .IsMret(id_IsMret_0));
    IMMGEN #(DATAWIDTH) ig0(.instr(id_inst_0), .imm(id_imm_0));
    ACTL al0(.opcode(id_inst_0[6:0]), .funct3(id_f3_0), .funct7(id_inst_0[31:25]), .alu_ctrl(id_alu_ctrl_0));
    assign id_branch_target_0 = id_pc_0 + id_imm_0;

    // inst1 译码
    logic id_IsBranch_1, id_RegWen_1, id_MemWen_1, id_AluSrcB_1, id_CsrWen_1, id_CsrImmSel_1, id_IsEcall_1, id_IsEbreak_1, id_IsMret_1;
    logic [1:0] id_JmpType_1, id_WbSel_1, id_AluSrcA_1, id_CsrOp_1;
    logic [3:0] id_alu_ctrl_1;
    logic [31:0] id_imm_1, id_branch_target_1;
    wire id_is_M_1 = (id_inst_1[6:0] == 7'b0110011) && (id_inst_1[31:25] == 7'b0000001);

    Control c1(.inst(id_inst_1), .IsBranch(id_IsBranch_1), .JmpType(id_JmpType_1),
        .RegWen(id_RegWen_1), .MemWen(id_MemWen_1), .WbSel(id_WbSel_1),
        .AluSrcA(id_AluSrcA_1), .AluSrcB(id_AluSrcB_1),
        .CsrWen(id_CsrWen_1), .CsrOp(id_CsrOp_1), .CsrImmSel(id_CsrImmSel_1),
        .IsEcall(id_IsEcall_1), .IsEbreak(id_IsEbreak_1), .IsMret(id_IsMret_1));
    IMMGEN #(DATAWIDTH) ig1(.instr(id_inst_1), .imm(id_imm_1));
    ACTL al1(.opcode(id_inst_1[6:0]), .funct3(id_f3_1), .funct7(id_inst_1[31:25]), .alu_ctrl(id_alu_ctrl_1));
    assign id_branch_target_1 = id_pc_1 + id_imm_1;

    // =========================================================================
    // 双发射判定
    // =========================================================================
    wire inst1_simple_alu = !id_IsBranch_1 && (id_JmpType_1 == 2'b00) &&
        !id_MemWen_1 && (id_WbSel_1 != 2'b10) && !id_is_M_1 &&
        !id_IsEcall_1 && !id_IsEbreak_1 && !id_IsMret_1 && !id_CsrWen_1;
    wire waw_conflict = id_RegWen_0 && id_RegWen_1 && (id_rd_0 != 5'd0) &&
                        (id_rd_0 == id_rd_1);
    wire load_use_0_to_1 = (id_WbSel_0 == 2'b10) && id_RegWen_0 && (id_rd_0 != 5'd0) &&
        (((id_rs1_1 != 5'd0) && (id_rd_0 == id_rs1_1)) ||
         ((id_rs2_1 != 5'd0) && (id_rd_0 == id_rs2_1)));
    wire pc_adjacent = (id_pc_1 == id_pc_0 + 4);
    // RAW hazard: inst0 reads a register that inst1 writes (inst1→inst0 dependency)
    wire raw_1_to_0 = id_RegWen_1 && (id_rd_1 != 5'd0) &&
        (((id_rs1_0 != 5'd0) && (id_rd_1 == id_rs1_0)) ||
         ((id_rs2_0 != 5'd0) && (id_rd_1 == id_rs2_0)));
    // Load-inst0 dual-issue is safe: load_use_0_to_1 already blocks load→inst1 hazard
    // RAW inst1→inst0 prevented by raw_1_to_0 check
    wire load_use_1_to_0 = (id_WbSel_1 == 2'b10) && id_RegWen_1 && (id_rd_1 != 5'd0) &&
        (((id_rs1_0 != 5'd0) && (id_rd_1 == id_rs1_0)) ||
         ((id_rs2_0 != 5'd0) && (id_rd_1 == id_rs2_0)));
    // Structural hazard checks
    wire inst0_mem  = (id_WbSel_0 == 2'b10) || id_MemWen_0;
    wire inst1_mem  = (id_WbSel_1 == 2'b10) || id_MemWen_1;
    wire inst0_ctrl = id_IsBranch_0 || (id_JmpType_0 != 2'b00) || id_IsEcall_0 || id_IsEbreak_0 || id_IsMret_0;
    wire inst1_ctrl = id_IsBranch_1 || (id_JmpType_1 != 2'b00) || id_IsEcall_1 || id_IsEbreak_1 || id_IsMret_1;

    // TEMP: keep old restrictions while infrastructure matures
    // Full symmetric can_dual (commented): see plan.md for final version
    wire inst1_simple_alu_keep = !id_IsBranch_1 && (id_JmpType_1 == 2'b00) &&
        !id_MemWen_1 && (id_WbSel_1 != 2'b10) && !id_is_M_1 &&
        !id_IsEcall_1 && !id_IsEbreak_1 && !id_IsMret_1 && !id_CsrWen_1;
    wire can_dual = id_valid_1 && pc_adjacent && inst1_simple_alu_keep
        && !waw_conflict && !load_use_0_to_1 && !raw_1_to_0 && !inst0_ctrl;
    assign dual_pop_count = can_dual ? 2'd2 : (id_valid_0 ? 2'd1 : 2'd0);

    // =========================================================================
    // Stage 6: RF 级 (双路寄存器读取)
    // =========================================================================
    logic rf_valid_0, rf_valid_1;
    logic [31:0] rf_pc_0, rf_pc_1, rf_inst_0, rf_inst_1, rf_imm_0, rf_imm_1;
    logic [31:0] rf_branch_target_0, rf_branch_target_1, rf_ret_pc_0, rf_ret_pc_1;
    logic [31:0] rf_pred_target_0, rf_pred_target_1;
    logic [4:0]  rf_rd_0, rf_rd_1, rf_rs1_0, rf_rs1_1, rf_rs2_0, rf_rs2_1;
    logic [1:0]  rf_JmpType_0, rf_JmpType_1, rf_WbSel_0, rf_WbSel_1;
    logic [1:0]  rf_AluSrcA_0, rf_AluSrcA_1, rf_CsrOp_0, rf_CsrOp_1;
    logic [3:0]  rf_alu_ctrl_0, rf_alu_ctrl_1;
    logic [2:0]  rf_funct3_0, rf_funct3_1;
    logic [11:0] rf_csr_idx_0, rf_csr_idx_1;
    logic rf_pred_taken_0, rf_pred_taken_1;
    logic rf_RegWen_0, rf_RegWen_1, rf_MemWen_0, rf_MemWen_1;
    logic rf_IsBranch_0, rf_IsBranch_1, rf_AluSrcB_0, rf_AluSrcB_1;
    logic rf_CsrWen_0, rf_CsrWen_1, rf_CsrImmSel_0, rf_CsrImmSel_1;
    logic rf_IsEcall_0, rf_IsEcall_1, rf_IsEbreak_0, rf_IsEbreak_1, rf_IsMret_0, rf_IsMret_1;
    logic rf_is_M_0, rf_is_M_1;

    // inst0 pipeline register
    ID_RF_Reg #(DATAWIDTH) id_rf_0 (
        .clk(cpu_clk), .rst(cpu_rst), .stall(stall_RF), .poison(poison_RF),
        .id_valid(id_valid_0), .id_is_M(id_is_M_0), .id_pc(id_pc_0), .id_inst(id_inst_0),
        .id_imm(id_imm_0), .id_branch_target(id_branch_target_0), .id_ret_pc(id_ret_pc_0),
        .id_rd(id_rd_0), .id_rs1(id_rs1_0), .id_rs2(id_rs2_0),
        .id_RegWen(id_RegWen_0), .id_MemWen(id_MemWen_0), .id_IsBranch(id_IsBranch_0),
        .id_AluSrcB(id_AluSrcB_0), .id_JmpType(id_JmpType_0), .id_WbSel(id_WbSel_0),
        .id_AluSrcA(id_AluSrcA_0), .id_alu_ctrl(id_alu_ctrl_0),
        .id_funct3(id_f3_0), .id_csr_idx(id_inst_0[31:20]),
        .id_CsrWen(id_CsrWen_0), .id_CsrImmSel(id_CsrImmSel_0),
        .id_IsEcall(id_IsEcall_0), .id_IsEbreak(id_IsEbreak_0), .id_IsMret(id_IsMret_0),
        .id_CsrOp(id_CsrOp_0), .id_pred_taken(id_pred_taken_0), .id_pred_target(id_pred_target_0),
        .rf_valid(rf_valid_0), .rf_is_M(rf_is_M_0), .rf_pc(rf_pc_0), .rf_inst(rf_inst_0),
        .rf_imm(rf_imm_0), .rf_branch_target(rf_branch_target_0), .rf_ret_pc(rf_ret_pc_0),
        .rf_rd(rf_rd_0), .rf_rs1(rf_rs1_0), .rf_rs2(rf_rs2_0),
        .rf_RegWen(rf_RegWen_0), .rf_MemWen(rf_MemWen_0), .rf_IsBranch(rf_IsBranch_0),
        .rf_AluSrcB(rf_AluSrcB_0), .rf_JmpType(rf_JmpType_0), .rf_WbSel(rf_WbSel_0),
        .rf_AluSrcA(rf_AluSrcA_0), .rf_alu_ctrl(rf_alu_ctrl_0), .rf_funct3(rf_funct3_0),
        .rf_csr_idx(rf_csr_idx_0), .rf_CsrWen(rf_CsrWen_0), .rf_CsrImmSel(rf_CsrImmSel_0),
        .rf_IsEcall(rf_IsEcall_0), .rf_IsEbreak(rf_IsEbreak_0), .rf_IsMret(rf_IsMret_0),
        .rf_CsrOp(rf_CsrOp_0), .rf_pred_taken(rf_pred_taken_0), .rf_pred_target(rf_pred_target_0)
    );

    // inst1 pipeline register (only valid when can_dual)
    logic id_valid_1_eff;
    assign id_valid_1_eff = id_valid_1 & can_dual;
    ID_RF_Reg #(DATAWIDTH) id_rf_1 (
        .clk(cpu_clk), .rst(cpu_rst), .stall(stall_RF), .poison(poison_RF),
        .id_valid(id_valid_1_eff), .id_is_M(id_is_M_1), .id_pc(id_pc_1), .id_inst(id_inst_1),
        .id_imm(id_imm_1), .id_branch_target(id_branch_target_1), .id_ret_pc(id_ret_pc_1),
        .id_rd(id_rd_1), .id_rs1(id_rs1_1), .id_rs2(id_rs2_1),
        .id_RegWen(id_RegWen_1), .id_MemWen(id_MemWen_1), .id_IsBranch(id_IsBranch_1),
        .id_AluSrcB(id_AluSrcB_1), .id_JmpType(id_JmpType_1), .id_WbSel(id_WbSel_1),
        .id_AluSrcA(id_AluSrcA_1), .id_alu_ctrl(id_alu_ctrl_1),
        .id_funct3(id_f3_1), .id_csr_idx(id_inst_1[31:20]),
        .id_CsrWen(id_CsrWen_1), .id_CsrImmSel(id_CsrImmSel_1),
        .id_IsEcall(id_IsEcall_1), .id_IsEbreak(id_IsEbreak_1), .id_IsMret(id_IsMret_1),
        .id_CsrOp(id_CsrOp_1), .id_pred_taken(id_pred_taken_1), .id_pred_target(id_pred_target_1),
        .rf_valid(rf_valid_1), .rf_is_M(rf_is_M_1), .rf_pc(rf_pc_1), .rf_inst(rf_inst_1),
        .rf_imm(rf_imm_1), .rf_branch_target(rf_branch_target_1), .rf_ret_pc(rf_ret_pc_1),
        .rf_rd(rf_rd_1), .rf_rs1(rf_rs1_1), .rf_rs2(rf_rs2_1),
        .rf_RegWen(rf_RegWen_1), .rf_MemWen(rf_MemWen_1), .rf_IsBranch(rf_IsBranch_1),
        .rf_AluSrcB(rf_AluSrcB_1), .rf_JmpType(rf_JmpType_1), .rf_WbSel(rf_WbSel_1),
        .rf_AluSrcA(rf_AluSrcA_1), .rf_alu_ctrl(rf_alu_ctrl_1), .rf_funct3(rf_funct3_1),
        .rf_csr_idx(rf_csr_idx_1), .rf_CsrWen(rf_CsrWen_1), .rf_CsrImmSel(rf_CsrImmSel_1),
        .rf_IsEcall(rf_IsEcall_1), .rf_IsEbreak(rf_IsEbreak_1), .rf_IsMret(rf_IsMret_1),
        .rf_CsrOp(rf_CsrOp_1), .rf_pred_taken(rf_pred_taken_1), .rf_pred_target(rf_pred_target_1)
    );

    // RF: 4-read 2-write
    logic [31:0] rf_rs1_dat_0, rf_rs2_dat_0, rf_rs1_dat_1, rf_rs2_dat_1;
    logic [31:0] wb_data_0, wb_data_1;
    logic [4:0]  wb_rd_0, wb_rd_1;
    logic        wb_RegWen_0, wb_RegWen_1;

    RF #(5, DATAWIDTH) u_rf (
        .clk(cpu_clk), .rst(cpu_rst),
        .wen0  (wb_valid_0 & wb_RegWen_0),  .waddr0(wb_rd_0),  .wdata0(wb_data_0),
        .wen1  (wb_valid_1 & wb_RegWen_1),  .waddr1(wb_rd_1),  .wdata1(wb_data_1),
        .rR1_0(rf_rs1_0), .rR2_0(rf_rs2_0), .rR1_1(rf_rs1_1), .rR2_1(rf_rs2_1),
        .rR1_0_data(rf_rs1_dat_0), .rR2_0_data(rf_rs2_dat_0),
        .rR1_1_data(rf_rs1_dat_1), .rR2_1_data(rf_rs2_dat_1)
    );

    // =========================================================================
    // RF 级提前分支解析 (inst0 only, inst1 is never a branch)
    // =========================================================================
    wire rf_is_ctrl_0 = rf_IsBranch_0 || (rf_JmpType_0 != 2'b00);
    wire rs1_raw_0 = (rf_rs1_0 != 5'b0) && (
        (ex1_valid_0  & ex1_RegWen_0  & (ex1_rd_0  == rf_rs1_0)) |
        (br_valid_0   & br_RegWen_0   & (br_rd_0   == rf_rs1_0)) |
        (mem1_valid_0 & mem1_RegWen_0 & (mem1_rd_0 == rf_rs1_0)) );
    wire rs2_raw_0 = (rf_rs2_0 != 5'b0) && (
        (ex1_valid_0  & ex1_RegWen_0  & (ex1_rd_0  == rf_rs2_0)) |
        (br_valid_0   & br_RegWen_0   & (br_rd_0   == rf_rs2_0)) |
        (mem1_valid_0 & mem1_RegWen_0 & (mem1_rd_0 == rf_rs2_0)) );
    wire rf_raw_haz = rs1_raw_0 | rs2_raw_0;
    wire rf_eq  = (rf_rs1_dat_0 == rf_rs2_dat_0);
    wire rf_lts = ($signed(rf_rs1_dat_0) < $signed(rf_rs2_dat_0));
    wire rf_ltu = (rf_rs1_dat_0 < rf_rs2_dat_0);
    logic rf_take;
    always_comb begin
        rf_take = 1'b0;
        if (rf_IsBranch_0)
            case (rf_funct3_0)
                3'b000: rf_take = rf_eq;  3'b001: rf_take = !rf_eq;
                3'b100: rf_take = rf_lts; 3'b101: rf_take = !rf_lts;
                3'b110: rf_take = rf_ltu; 3'b111: rf_take = !rf_ltu;
                default: rf_take = 1'b0;
            endcase
    end
    wire rf_act_taken = (rf_JmpType_0 != 2'b00) || (rf_IsBranch_0 && rf_take);
    wire [31:0] rf_jalr_tgt = (rf_rs1_dat_0 + rf_imm_0) & ~32'h1;
    wire [31:0] early_tgt = (rf_JmpType_0 == 2'b10) ? rf_jalr_tgt :
                            (rf_act_taken)         ? rf_branch_target_0 : rf_ret_pc_0;
    wire early_misp = rf_valid_0 & rf_is_ctrl_0 & ~rf_raw_haz &
                      ~(rf_IsEcall_0 | rf_IsEbreak_0 | rf_IsMret_0) &
                      (rf_act_taken ^ rf_pred_taken_0);
    logic early_done;
    always_ff @(posedge cpu_clk) begin
        if (cpu_rst || !rf_valid_0) early_done <= 1'b0;
        else if (early_misp) early_done <= 1'b1;
    end
    (* max_fanout = "16" *) wire early_flush = early_misp & ~early_done;
    wire [31:0] early_flush_target = early_tgt;

    // =========================================================================
    // Stage 7: EX1 级 (双 ALU + inter-inst forwarding)
    // =========================================================================
    logic ex1_valid_0, ex1_valid_1;
    logic [31:0] ex1_pc_0, ex1_pc_1, ex1_inst_0, ex1_inst_1;
    logic [31:0] ex1_imm_0, ex1_imm_1, ex1_br_tgt_0, ex1_br_tgt_1, ex1_ret_pc_0, ex1_ret_pc_1;
    logic [31:0] ex1_pred_tgt_0, ex1_pred_tgt_1;
    logic [31:0] ex1_rs1_raw_0, ex1_rs1_raw_1, ex1_rs2_raw_0, ex1_rs2_raw_1;
    logic [4:0]  ex1_rd_0, ex1_rd_1, ex1_rs1_0, ex1_rs1_1, ex1_rs2_0, ex1_rs2_1;
    logic [1:0]  ex1_JmpType_0, ex1_JmpType_1, ex1_WbSel_0, ex1_WbSel_1;
    logic [1:0]  ex1_AluSrcA_0, ex1_AluSrcA_1, ex1_CsrOp_0, ex1_CsrOp_1;
    logic [3:0]  ex1_alu_ctrl_0, ex1_alu_ctrl_1;
    logic [2:0]  ex1_funct3_0, ex1_funct3_1;
    logic [11:0] ex1_csr_idx_0, ex1_csr_idx_1;
    logic ex1_is_M_0, ex1_is_M_1, ex1_RegWen_0, ex1_RegWen_1, ex1_MemWen_0, ex1_MemWen_1;
    logic ex1_IsBranch_0, ex1_IsBranch_1, ex1_AluSrcB_0, ex1_AluSrcB_1;
    logic ex1_CsrWen_0, ex1_CsrWen_1, ex1_CsrImmSel_0, ex1_CsrImmSel_1;
    logic ex1_IsEcall_0, ex1_IsEcall_1, ex1_IsEbreak_0, ex1_IsEbreak_1, ex1_IsMret_0, ex1_IsMret_1;
    logic ex1_pred_taken_0, ex1_pred_taken_1;

    // inst0 EX1 register
    RF_EX1_Reg #(DATAWIDTH) rf_ex1_0 (
        .clk(cpu_clk), .rst(cpu_rst), .stall(stall_EX1), .poison(poison_EX1_0),
        .rf_valid(rf_valid_0), .rf_is_M(rf_is_M_0), .rf_pc(rf_pc_0), .rf_inst(rf_inst_0),
        .rf_imm(rf_imm_0), .rf_branch_target(rf_branch_target_0), .rf_ret_pc(rf_ret_pc_0),
        .rf_fw_rs1_data(rf_rs1_dat_0), .rf_fw_rs2_data(rf_rs2_dat_0),
        .rf_rd(rf_rd_0), .rf_RegWen(rf_RegWen_0), .rf_MemWen(rf_MemWen_0),
        .rf_IsBranch(rf_IsBranch_0), .rf_AluSrcB(rf_AluSrcB_0),
        .rf_JmpType(rf_JmpType_0), .rf_WbSel(rf_WbSel_0), .rf_AluSrcA(rf_AluSrcA_0),
        .rf_alu_ctrl(rf_alu_ctrl_0), .rf_funct3(rf_funct3_0), .rf_csr_idx(rf_csr_idx_0),
        .rf_CsrWen(rf_CsrWen_0), .rf_CsrImmSel(rf_CsrImmSel_0),
        .rf_IsEcall(rf_IsEcall_0), .rf_IsEbreak(rf_IsEbreak_0), .rf_IsMret(rf_IsMret_0),
        .rf_CsrOp(rf_CsrOp_0), .rf_pred_taken(rf_pred_taken_0), .rf_pred_target(rf_pred_target_0),
        .ex1_valid(ex1_valid_0), .ex1_is_M(ex1_is_M_0), .ex1_pc(ex1_pc_0),
        .ex1_inst(ex1_inst_0), .ex1_imm(ex1_imm_0),
        .ex1_branch_target(ex1_br_tgt_0), .ex1_ret_pc(ex1_ret_pc_0),
        .ex1_fw_rs1_data(ex1_rs1_raw_0), .ex1_fw_rs2_data(ex1_rs2_raw_0),
        .ex1_rd(ex1_rd_0), .ex1_RegWen(ex1_RegWen_0), .ex1_MemWen(ex1_MemWen_0),
        .ex1_IsBranch(ex1_IsBranch_0), .ex1_AluSrcB(ex1_AluSrcB_0),
        .ex1_JmpType(ex1_JmpType_0), .ex1_WbSel(ex1_WbSel_0), .ex1_AluSrcA(ex1_AluSrcA_0),
        .ex1_alu_ctrl(ex1_alu_ctrl_0), .ex1_funct3(ex1_funct3_0), .ex1_csr_idx(ex1_csr_idx_0),
        .ex1_CsrWen(ex1_CsrWen_0), .ex1_CsrImmSel(ex1_CsrImmSel_0),
        .ex1_IsEcall(ex1_IsEcall_0), .ex1_IsEbreak(ex1_IsEbreak_0), .ex1_IsMret(ex1_IsMret_0),
        .ex1_CsrOp(ex1_CsrOp_0), .ex1_pred_taken(ex1_pred_taken_0), .ex1_pred_target(ex1_pred_tgt_0)
    );

    // inst1 EX1 register (valid only when can_dual)
    RF_EX1_Reg #(DATAWIDTH) rf_ex1_1 (
        .clk(cpu_clk), .rst(cpu_rst), .stall(stall_EX1), .poison(poison_EX1_1),
        .rf_valid(rf_valid_1), .rf_is_M(rf_is_M_1), .rf_pc(rf_pc_1), .rf_inst(rf_inst_1),
        .rf_imm(rf_imm_1), .rf_branch_target(rf_branch_target_1), .rf_ret_pc(rf_ret_pc_1),
        .rf_fw_rs1_data(rf_rs1_dat_1), .rf_fw_rs2_data(rf_rs2_dat_1),
        .rf_rd(rf_rd_1), .rf_RegWen(rf_RegWen_1), .rf_MemWen(rf_MemWen_1),
        .rf_IsBranch(rf_IsBranch_1), .rf_AluSrcB(rf_AluSrcB_1),
        .rf_JmpType(rf_JmpType_1), .rf_WbSel(rf_WbSel_1), .rf_AluSrcA(rf_AluSrcA_1),
        .rf_alu_ctrl(rf_alu_ctrl_1), .rf_funct3(rf_funct3_1), .rf_csr_idx(rf_csr_idx_1),
        .rf_CsrWen(rf_CsrWen_1), .rf_CsrImmSel(rf_CsrImmSel_1),
        .rf_IsEcall(rf_IsEcall_1), .rf_IsEbreak(rf_IsEbreak_1), .rf_IsMret(rf_IsMret_1),
        .rf_CsrOp(rf_CsrOp_1), .rf_pred_taken(rf_pred_taken_1), .rf_pred_target(rf_pred_target_1),
        .ex1_valid(ex1_valid_1), .ex1_is_M(ex1_is_M_1), .ex1_pc(ex1_pc_1),
        .ex1_inst(ex1_inst_1), .ex1_imm(ex1_imm_1),
        .ex1_branch_target(ex1_br_tgt_1), .ex1_ret_pc(ex1_ret_pc_1),
        .ex1_fw_rs1_data(ex1_rs1_raw_1), .ex1_fw_rs2_data(ex1_rs2_raw_1),
        .ex1_rd(ex1_rd_1), .ex1_RegWen(ex1_RegWen_1), .ex1_MemWen(ex1_MemWen_1),
        .ex1_IsBranch(ex1_IsBranch_1), .ex1_AluSrcB(ex1_AluSrcB_1),
        .ex1_JmpType(ex1_JmpType_1), .ex1_WbSel(ex1_WbSel_1), .ex1_AluSrcA(ex1_AluSrcA_1),
        .ex1_alu_ctrl(ex1_alu_ctrl_1), .ex1_funct3(ex1_funct3_1), .ex1_csr_idx(ex1_csr_idx_1),
        .ex1_CsrWen(ex1_CsrWen_1), .ex1_CsrImmSel(ex1_CsrImmSel_1),
        .ex1_IsEcall(ex1_IsEcall_1), .ex1_IsEbreak(ex1_IsEbreak_1), .ex1_IsMret(ex1_IsMret_1),
        .ex1_CsrOp(ex1_CsrOp_1), .ex1_pred_taken(ex1_pred_taken_1), .ex1_pred_target(ex1_pred_tgt_1)
    );

    assign ex1_rs1_0 = ex1_inst_0[19:15]; assign ex1_rs2_0 = ex1_inst_0[24:20];
    assign ex1_rs1_1 = ex1_inst_1[19:15]; assign ex1_rs2_1 = ex1_inst_1[24:20];

    // Forwarding for inst0 (from BR/MEM1/MEM2/WB — same as single-issue)
    logic [2:0] fwd_A_0, fwd_B_0;
    ForwardingUnit fw_0 (
        .id_rs1(ex1_rs1_0), .id_rs2(ex1_rs2_0),
        .ex_RegWen(br_valid_0 & br_RegWen_0), .ex_rd(br_rd_0),
        .mem1_RegWen(mem1_valid_0 & mem1_RegWen_0), .mem1_rd(mem1_rd_0),
        .mem2_RegWen(mem2_valid_0 & mem2_RegWen_0), .mem2_rd(mem2_rd_0),
        .wb_RegWen(wb_valid_0 & wb_RegWen_0), .wb_rd(wb_rd_0),
        .id_forward_A(fwd_A_0), .id_forward_B(fwd_B_0)
    );

    // Forwarding for inst0: cross-pipeline (sees inst1's pipeline)
    logic [2:0] fwd_A_0_cross, fwd_B_0_cross;
    ForwardingUnit fw_0_cross (
        .id_rs1(ex1_rs1_0), .id_rs2(ex1_rs2_0),
        .ex_RegWen(br_valid_1 & br_RegWen_1), .ex_rd(br_rd_1),
        .mem1_RegWen(mem1_valid_1 & mem1_RegWen_1), .mem1_rd(mem1_rd_1),
        .mem2_RegWen(mem2_valid_1 & mem2_RegWen_1), .mem2_rd(mem2_rd_1),
        .wb_RegWen(wb_valid_1_pipe & wb_RegWen_1_pipe), .wb_rd(wb_rd_1_pipe),
        .id_forward_A(fwd_A_0_cross), .id_forward_B(fwd_B_0_cross)
    );

    // Forwarding for inst1: cross-pipeline (sees inst0's pipeline)
    logic [2:0] fwd_A_1_cross, fwd_B_1_cross;
    ForwardingUnit fw_1_cross (
        .id_rs1(ex1_rs1_1), .id_rs2(ex1_rs2_1),
        .ex_RegWen(br_valid_0 & br_RegWen_0), .ex_rd(br_rd_0),
        .mem1_RegWen(mem1_valid_0 & mem1_RegWen_0), .mem1_rd(mem1_rd_0),
        .mem2_RegWen(mem2_valid_0 & mem2_RegWen_0), .mem2_rd(mem2_rd_0),
        .wb_RegWen(wb_valid_0 & wb_RegWen_0), .wb_rd(wb_rd_0),
        .id_forward_A(fwd_A_1_cross), .id_forward_B(fwd_B_1_cross)
    );

    // Forwarding for inst1: self-pipeline (sees inst1's pipeline)
    logic [2:0] fwd_A_1_self, fwd_B_1_self;
    ForwardingUnit fw_1_self (
        .id_rs1(ex1_rs1_1), .id_rs2(ex1_rs2_1),
        .ex_RegWen(br_valid_1 & br_RegWen_1), .ex_rd(br_rd_1),
        .mem1_RegWen(mem1_valid_1 & mem1_RegWen_1), .mem1_rd(mem1_rd_1),
        .mem2_RegWen(mem2_valid_1 & mem2_RegWen_1), .mem2_rd(mem2_rd_1),
        .wb_RegWen(wb_valid_1_pipe & wb_RegWen_1_pipe), .wb_rd(wb_rd_1_pipe),
        .id_forward_A(fwd_A_1_self), .id_forward_B(fwd_B_1_self)
    );

    // Inter-instruction forward: inst0 ALU result → inst1 operand (combinational)
    logic [31:0] ex1_alu_res_0, ex1_alu_res_1;
    wire inst0_to_inst1_A = ex1_valid_0 && ex1_RegWen_0 && (ex1_rd_0 != 5'd0) && (ex1_rd_0 == ex1_rs1_1);
    wire inst0_to_inst1_B = ex1_valid_0 && ex1_RegWen_0 && (ex1_rd_0 != 5'd0) && (ex1_rd_0 == ex1_rs2_1);
    // inst1→inst0 same-cycle: inst0 may read inst1's dest (RAW from inst1 to inst0)
    wire inst1_to_inst0_A = ex1_valid_1 && ex1_RegWen_1 && (ex1_rd_1 != 5'd0) && (ex1_rd_1 == ex1_rs1_0);
    wire inst1_to_inst0_B = ex1_valid_1 && ex1_RegWen_1 && (ex1_rd_1 != 5'd0) && (ex1_rd_1 == ex1_rs2_0);

    // inst1→inst0 forwarding: inst0 operands may depend on inst1 pipeline results
    wire f1A_d1 = inst1_wb_v_d1 && inst1_wb_rw_d1 && (inst1_wb_rd_d1 != 5'd0) && (inst1_wb_rd_d1 == ex1_rs1_0);
    wire f1A_d2 = inst1_wb_v_d2 && inst1_wb_rw_d2 && (inst1_wb_rd_d2 != 5'd0) && (inst1_wb_rd_d2 == ex1_rs1_0);
    wire f1A_d3 = inst1_wb_v_d3 && inst1_wb_rw_d3 && (inst1_wb_rd_d3 != 5'd0) && (inst1_wb_rd_d3 == ex1_rs1_0);
    wire f1A_wb = wb_valid_1  && wb_RegWen_1  && (wb_rd_1  != 5'd0) && (wb_rd_1  == ex1_rs1_0);
    wire f1B_d1 = inst1_wb_v_d1 && inst1_wb_rw_d1 && (inst1_wb_rd_d1 != 5'd0) && (inst1_wb_rd_d1 == ex1_rs2_0);
    wire f1B_d2 = inst1_wb_v_d2 && inst1_wb_rw_d2 && (inst1_wb_rd_d2 != 5'd0) && (inst1_wb_rd_d2 == ex1_rs2_0);
    wire f1B_d3 = inst1_wb_v_d3 && inst1_wb_rw_d3 && (inst1_wb_rd_d3 != 5'd0) && (inst1_wb_rd_d3 == ex1_rs2_0);
    wire f1B_wb = wb_valid_1  && wb_RegWen_1  && (wb_rd_1  != 5'd0) && (wb_rd_1  == ex1_rs2_0);

    // inst1→inst1 forwarding: inst1 operands may depend on older inst1 results
    wire f1A_self_d1 = inst1_wb_v_d1 && inst1_wb_rw_d1 && (inst1_wb_rd_d1 != 5'd0) && (inst1_wb_rd_d1 == ex1_rs1_1);
    wire f1A_self_d2 = inst1_wb_v_d2 && inst1_wb_rw_d2 && (inst1_wb_rd_d2 != 5'd0) && (inst1_wb_rd_d2 == ex1_rs1_1);
    wire f1A_self_d3 = inst1_wb_v_d3 && inst1_wb_rw_d3 && (inst1_wb_rd_d3 != 5'd0) && (inst1_wb_rd_d3 == ex1_rs1_1);
    wire f1A_self_wb = wb_valid_1  && wb_RegWen_1  && (wb_rd_1  != 5'd0) && (wb_rd_1  == ex1_rs1_1);
    wire f1B_self_d1 = inst1_wb_v_d1 && inst1_wb_rw_d1 && (inst1_wb_rd_d1 != 5'd0) && (inst1_wb_rd_d1 == ex1_rs2_1);
    wire f1B_self_d2 = inst1_wb_v_d2 && inst1_wb_rw_d2 && (inst1_wb_rd_d2 != 5'd0) && (inst1_wb_rd_d2 == ex1_rs2_1);
    wire f1B_self_d3 = inst1_wb_v_d3 && inst1_wb_rw_d3 && (inst1_wb_rd_d3 != 5'd0) && (inst1_wb_rd_d3 == ex1_rs2_1);
    wire f1B_self_wb = wb_valid_1  && wb_RegWen_1  && (wb_rd_1  != 5'd0) && (wb_rd_1  == ex1_rs2_1);

    logic [31:0] ex1_fwd_0_A, ex1_fwd_0_B, ex1_fwd_1_A, ex1_fwd_1_B;
    always_comb begin
        // inst0 A: inst1 d1 (newest) > inst0 pipe > inst1 older > regfile
        if      (f1A_d1)                 ex1_fwd_0_A = inst1_wb_d1;
        else if (fwd_A_0 == 3'b100)      ex1_fwd_0_A = br_fw_data_0;
        else if (fwd_A_0 == 3'b011)      ex1_fwd_0_A = mem1_fw_data_0;
        else if (fwd_A_0 == 3'b010)      ex1_fwd_0_A = mem2_fw_data_0;
        else if (fwd_A_0 == 3'b001)      ex1_fwd_0_A = wb_data_0;
        else if (f1A_d2)                 ex1_fwd_0_A = inst1_wb_d2;
        else if (f1A_d3)                 ex1_fwd_0_A = inst1_wb_d3;
        else if (f1A_wb)                 ex1_fwd_0_A = wb_data_1;
        else                             ex1_fwd_0_A = ex1_rs1_raw_0;

        // inst0 B: inst0 pipe > inst1 pipe > regfile
        // BUT: allow inst1 shift register d1 to override stale inst0 pipe forwarding
        if      (f1B_d1)                 ex1_fwd_0_B = inst1_wb_d1;
        else if (fwd_B_0 == 3'b100)      ex1_fwd_0_B = br_fw_data_0;
        else if (fwd_B_0 == 3'b011)      ex1_fwd_0_B = mem1_fw_data_0;
        else if (fwd_B_0 == 3'b010)      ex1_fwd_0_B = mem2_fw_data_0;
        else if (fwd_B_0 == 3'b001)      ex1_fwd_0_B = wb_data_0;
        else if (f1B_d2)                 ex1_fwd_0_B = inst1_wb_d2;
        else if (f1B_d3)                 ex1_fwd_0_B = inst1_wb_d3;
        else if (f1B_wb)                 ex1_fwd_0_B = wb_data_1;
        else                             ex1_fwd_0_B = ex1_rs2_raw_0;

        // inst1 A: inter-inst > inst1 self d1 > inst0 pipe > inst1 older > regfile
        if      (inst0_to_inst1_A)       ex1_fwd_1_A = ex1_alu_res_0;
        else if (f1A_self_d1)            ex1_fwd_1_A = inst1_wb_d1;
        else if (fwd_A_1_cross == 3'b100)      ex1_fwd_1_A = br_fw_data_0;
        else if (fwd_A_1_cross == 3'b011)      ex1_fwd_1_A = mem1_fw_data_0;
        else if (fwd_A_1_cross == 3'b010)      ex1_fwd_1_A = mem2_fw_data_0;
        else if (fwd_A_1_cross == 3'b001)      ex1_fwd_1_A = wb_data_0;
        else if (f1A_self_d2)            ex1_fwd_1_A = inst1_wb_d2;
        else if (f1A_self_d3)            ex1_fwd_1_A = inst1_wb_d3;
        else if (f1A_self_wb)            ex1_fwd_1_A = wb_data_1;
        else                             ex1_fwd_1_A = ex1_rs1_raw_1;

        // inst1 B: inter-inst > inst1 self d1 > inst0 pipe > inst1 older > regfile
        if      (inst0_to_inst1_B)       ex1_fwd_1_B = ex1_alu_res_0;
        else if (f1B_self_d1)            ex1_fwd_1_B = inst1_wb_d1;
        else if (fwd_B_1_cross == 3'b100)      ex1_fwd_1_B = br_fw_data_0;
        else if (fwd_B_1_cross == 3'b011)      ex1_fwd_1_B = mem1_fw_data_0;
        else if (fwd_B_1_cross == 3'b010)      ex1_fwd_1_B = mem2_fw_data_0;
        else if (fwd_B_1_cross == 3'b001)      ex1_fwd_1_B = wb_data_0;
        else if (f1B_self_d2)            ex1_fwd_1_B = inst1_wb_d2;
        else if (f1B_self_d3)            ex1_fwd_1_B = inst1_wb_d3;
        else if (f1B_self_wb)            ex1_fwd_1_B = wb_data_1;
        else                             ex1_fwd_1_B = ex1_rs2_raw_1;
    end
    wire [31:0] inst1_rs1_final = ex1_fwd_1_A;  // inst0→inst1 now handled inside always_comb
    wire [31:0] inst1_rs2_final = ex1_fwd_1_B;

    // Dual ALU
    wire [31:0] ex1_op1_0 = (ex1_AluSrcA_0 == 2'b10) ? 32'b0 : (ex1_AluSrcA_0 == 2'b01) ? ex1_pc_0 : ex1_fwd_0_A;
    wire [31:0] ex1_op2_0 = ex1_AluSrcB_0 ? ex1_imm_0 : ex1_fwd_0_B;
    ALU #(DATAWIDTH) alu_0 (.A(ex1_op1_0), .B(ex1_op2_0), .ALUControl(ex1_alu_ctrl_0), .Result(ex1_alu_res_0));

    wire [31:0] ex1_op1_1 = (ex1_AluSrcA_1 == 2'b10) ? 32'b0 : (ex1_AluSrcA_1 == 2'b01) ? ex1_pc_1 : inst1_rs1_final;
    wire [31:0] ex1_op2_1 = ex1_AluSrcB_1 ? ex1_imm_1 : inst1_rs2_final;
    logic mdu_start;
    ALU #(DATAWIDTH) alu_1 (.A(ex1_op1_1), .B(ex1_op2_1), .ALUControl(ex1_alu_ctrl_1), .Result(ex1_alu_res_1));

    // MDU (仅 inst0)
    logic [31:0] mdu_res; logic mdu_busy, mdu_done;
    always_comb mdu_start = ex1_valid_0 && ex1_is_M_0 && !mdu_busy && !mdu_done;
    always_comb stall_req_mdu = ex1_valid_0 && ex1_is_M_0 && !mdu_done;
    MDU mdu_inst (.clk(cpu_clk), .rst(cpu_rst), .start(mdu_start),
        .funct3(ex1_funct3_0), .a(ex1_fwd_0_A), .b(ex1_fwd_0_B),
        .result(mdu_res), .busy(mdu_busy), .done(mdu_done));
    wire [31:0] final_alu_0 = ex1_is_M_0 ? mdu_res : ex1_alu_res_0;
    wire [31:0] final_alu_1 = ex1_alu_res_1;  // inst1: no MDU, ALU result is final

    // AGU (dual)
    wire [31:0] ex1_agu_res_0, ex1_agu_res_1;
    AGU #(DATAWIDTH) agu_inst_0 (.base(ex1_fwd_0_A), .offset(ex1_imm_0), .addr(ex1_agu_res_0));
    AGU #(DATAWIDTH) agu_inst_1 (.base(ex1_fwd_1_A), .offset(ex1_imm_1), .addr(ex1_agu_res_1));

    // =========================================================================
    // Stage 8: BR 级 (仅 inst0, inst1 不是分支)
    // =========================================================================
    logic br_valid_0, br_MemWen_0, br_IsBranch_0;
    logic [31:0] br_inst_0, br_ret_pc_0, br_br_tgt_0, br_alu_res_0;
    logic [31:0] br_fw_rs1_0, br_fw_rs2_0, br_agu_res_0, br_csr_rdata_0, br_pred_tgt_0;
    logic [1:0] br_JmpType_0, br_WbSel_0; logic [2:0] br_funct3_0; logic br_pred_taken_0;
    logic [4:0] br_rd_0; logic br_RegWen_0;

    EX1_BR_Reg #(DATAWIDTH) ex1_br_0 (
        .clk(cpu_clk), .rst(cpu_rst), .stall(1'b0), .poison(poison_BR_0),
        .ex1_valid(ex1_valid_0), .ex1_pc(ex1_pc_0), .ex1_inst(ex1_inst_0),
        .ex1_ret_pc(ex1_ret_pc_0), .ex1_branch_target(ex1_br_tgt_0),
        .ex1_alu_res(final_alu_0), .ex1_fw_rs1_data(ex1_fwd_0_A),
        .ex1_fw_rs2_data(ex1_fwd_0_B), .ex1_agu_res(ex1_agu_res_0),
        .ex1_rd(ex1_rd_0), .ex1_RegWen(ex1_RegWen_0), .ex1_MemWen(ex1_MemWen_0),
        .ex1_IsBranch(ex1_IsBranch_0), .ex1_JmpType(ex1_JmpType_0),
        .ex1_WbSel(ex1_WbSel_0), .ex1_funct3(ex1_funct3_0),
        .ex1_pred_taken(ex1_pred_taken_0), .ex1_pred_target(ex1_pred_tgt_0),
        .br_valid(br_valid_0), .br_pc(br_pc), .br_inst(br_inst_0),
        .br_ret_pc(br_ret_pc_0), .br_branch_target(br_br_tgt_0),
        .br_alu_res(br_alu_res_0), .br_fw_rs1_data(br_fw_rs1_0),
        .br_fw_rs2_data(br_fw_rs2_0), .br_agu_res(br_agu_res_0),
        .br_rd(br_rd_0), .br_RegWen(br_RegWen_0), .br_MemWen(br_MemWen_0),
        .br_IsBranch(br_IsBranch_0), .br_JmpType(br_JmpType_0),
        .br_WbSel(br_WbSel_0), .br_funct3(br_funct3_0),
        .br_pred_taken(br_pred_taken_0), .br_pred_target(br_pred_tgt_0)
    );

    // === inst1 BR stage (new symmetric pipeline) ===
    logic br_valid_1, br_MemWen_1, br_IsBranch_1;
    logic [31:0] br_inst_1, br_ret_pc_1, br_br_tgt_1, br_alu_res_1;
    logic [31:0] br_fw_rs1_1, br_fw_rs2_1, br_agu_res_1, br_pred_tgt_1;
    logic [1:0] br_JmpType_1, br_WbSel_1; logic [2:0] br_funct3_1; logic br_pred_taken_1;
    logic [4:0] br_rd_1; logic br_RegWen_1;

    EX1_BR_Reg #(DATAWIDTH) ex1_br_1 (
        .clk(cpu_clk), .rst(cpu_rst), .stall(1'b0), .poison(poison_BR_1),
        .ex1_valid(ex1_valid_1), .ex1_pc(ex1_pc_1), .ex1_inst(ex1_inst_1),
        .ex1_ret_pc(ex1_ret_pc_1), .ex1_branch_target(ex1_br_tgt_1),
        .ex1_alu_res(final_alu_1), .ex1_fw_rs1_data(ex1_fwd_1_A),
        .ex1_fw_rs2_data(ex1_fwd_1_B), .ex1_agu_res(ex1_agu_res_1),
        .ex1_rd(ex1_rd_1), .ex1_RegWen(ex1_RegWen_1), .ex1_MemWen(ex1_MemWen_1),
        .ex1_IsBranch(ex1_IsBranch_1), .ex1_JmpType(ex1_JmpType_1),
        .ex1_WbSel(ex1_WbSel_1), .ex1_funct3(ex1_funct3_1),
        .ex1_pred_taken(ex1_pred_taken_1), .ex1_pred_target(ex1_pred_tgt_1),
        .br_valid(br_valid_1), .br_pc(br_pc_1), .br_inst(br_inst_1),
        .br_ret_pc(br_ret_pc_1), .br_branch_target(br_br_tgt_1),
        .br_alu_res(br_alu_res_1), .br_fw_rs1_data(br_fw_rs1_1),
        .br_fw_rs2_data(br_fw_rs2_1), .br_agu_res(br_agu_res_1),
        .br_rd(br_rd_1), .br_RegWen(br_RegWen_1), .br_MemWen(br_MemWen_1),
        .br_IsBranch(br_IsBranch_1), .br_JmpType(br_JmpType_1),
        .br_WbSel(br_WbSel_1), .br_funct3(br_funct3_1),
        .br_pred_taken(br_pred_taken_1), .br_pred_target(br_pred_tgt_1)
    );

    wire br_is_ctrl = br_IsBranch_0 || (br_JmpType_0 != 2'b00);
    assign br_valid_out  = br_valid_0;
    assign br_target_out = br_br_tgt_0;

    BranchUnit #(DATAWIDTH) bu_inst (.imm(32'b0),
        .rs1_data(br_fw_rs1_0), .rs2_data(br_fw_rs2_0),
        .precalc_branch_target(br_br_tgt_0), .precalc_pc_plus_4(br_ret_pc_0),
        .trap_pc(trap_pc), .Branch(br_IsBranch_0), .Jump(br_JmpType_0),
        .funct3(br_funct3_0), .next_pc(br_actual_target), .actual_taken(br_actual_taken));

    logic tgt_mismatch, br_misp, tgt_misp;
    always_comb begin
        if (br_JmpType_0 == 2'b10) tgt_mismatch = (br_actual_target != br_pred_tgt_0);
        else if (br_JmpType_0 == 2'b11) tgt_mismatch = (br_pred_tgt_0 != trap_pc);
        else tgt_mismatch = (br_pred_tgt_0 != br_br_tgt_0);
    end
    assign br_misp = br_actual_taken ^ br_pred_taken_0;
    assign tgt_misp = br_actual_taken & br_pred_taken_0 & tgt_mismatch;
    assign br_mispredict_0 = br_valid_0 & ((br_is_ctrl & (br_misp | tgt_misp)) | (~br_is_ctrl & br_pred_taken_0));

    // CSR (仅 inst0)
    wire br_IsEcall  = br_inst_0[6:0] == 7'b1110011 && br_inst_0[31:20] == 12'h000;
    wire br_IsEbreak = br_inst_0[6:0] == 7'b1110011 && br_inst_0[31:20] == 12'h001;
    wire br_IsMret   = br_inst_0[6:0] == 7'b1110011 && br_inst_0[31:20] == 12'h302;
    wire br_CsrWen   = br_inst_0[6:0] == 7'b1110011 && br_inst_0[14:12] != 3'b000;
    wire br_CsrImmSel= br_inst_0[14];
    wire [1:0] br_CsrOp = {br_inst_0[13:12] == 2'b11, br_inst_0[13:12] == 2'b10};
    wire [11:0] br_csr_idx = br_inst_0[31:20];
    wire [31:0] br_csr_wdata = br_CsrImmSel ? {27'b0, br_inst_0[19:15]} : br_fw_rs1_0;
    wire br_actual_csr_wen = br_valid_0 && br_CsrWen && !((br_CsrOp != 2'b00) && (br_inst_0[19:15] == 5'b0));
    assign br_take_trap = br_valid_0 & (br_IsEcall | br_IsEbreak | br_IsMret);

    CSR #(DATAWIDTH) csr_inst (.clk(cpu_clk), .rst(cpu_rst), .pc(br_pc),
        .csr_idx(br_csr_idx), .wdata(br_csr_wdata), .csr_op(br_CsrOp), .csr_wen(br_actual_csr_wen),
        .ecall(br_valid_0 & br_IsEcall), .ebreak(br_valid_0 & br_IsEbreak), .mret(br_valid_0 & br_IsMret),
        .rdata(br_csr_rdata_0), .trap_pc(trap_pc));
    wire [31:0] br_fw_data_0 = (br_WbSel_0 == 2'b01) ? br_ret_pc_0 : (br_WbSel_0 == 2'b11) ? br_csr_rdata_0 : br_alu_res_0;

    // === inst1 BranchUnit (Phase 4: symmetric branch support) ===
    wire br_is_ctrl_1 = br_IsBranch_1 || (br_JmpType_1 != 2'b00);
    wire [31:0] br_actual_target_1;
    wire br_actual_taken_1;
    BranchUnit #(DATAWIDTH) bu_inst_1 (
        .imm(32'b0),
        .rs1_data(br_fw_rs1_1), .rs2_data(br_fw_rs2_1),
        .precalc_branch_target(br_br_tgt_1), .precalc_pc_plus_4(br_ret_pc_1),
        .trap_pc(trap_pc), .Branch(br_IsBranch_1), .Jump(br_JmpType_1),
        .funct3(br_funct3_1), .next_pc(br_actual_target_1), .actual_taken(br_actual_taken_1)
    );

    // inst1 mispredict detection
    logic tgt_mismatch_1, br_misp_1, tgt_misp_1;
    always_comb begin
        if (br_JmpType_1 == 2'b10) tgt_mismatch_1 = (br_actual_target_1 != br_pred_tgt_1);
        else if (br_JmpType_1 == 2'b11) tgt_mismatch_1 = (br_pred_tgt_1 != trap_pc);
        else tgt_mismatch_1 = (br_pred_tgt_1 != br_br_tgt_1);
    end
    assign br_misp_1 = br_actual_taken_1 ^ br_pred_taken_1;
    assign tgt_misp_1 = br_actual_taken_1 & br_pred_taken_1 & tgt_mismatch_1;
    assign br_mispredict_1 = br_valid_1 & ((br_is_ctrl_1 & (br_misp_1 | tgt_misp_1)) | (~br_is_ctrl_1 & br_pred_taken_1));

    // =========================================================================
    // MEM1-MEM2-WB (双路: inst0 + inst1 memory MUX)
    // =========================================================================
    logic mem1_valid_0, mem1_MemWen_0;
    logic [31:0] mem1_pc_0, mem1_inst_0, mem1_ret_pc_0, mem1_alu_res_0;
    logic [31:0] mem1_fw_rs2_0, mem1_agu_res_0, mem1_csr_rdata_0;
    logic [1:0] mem1_WbSel_0; logic [2:0] mem1_funct3_0;
    logic [4:0] mem1_rd_0; logic mem1_RegWen_0;

    BR_MEM1_Reg #(DATAWIDTH) br_mem1_0 (
        .clk(cpu_clk), .rst(cpu_rst), .stall(1'b0), .poison(1'b0),
        .br_valid(br_valid_0), .br_pc(br_pc), .br_inst(br_inst_0),
        .br_ret_pc(br_ret_pc_0), .br_alu_res(br_alu_res_0),
        .br_fw_rs2_data(br_fw_rs2_0), .br_agu_res(br_agu_res_0),
        .br_csr_rdata(br_csr_rdata_0), .br_rd(br_rd_0),
        .br_RegWen(br_RegWen_0), .br_MemWen(br_MemWen_0), .br_WbSel(br_WbSel_0),
        .br_funct3(br_funct3_0),
        .mem1_valid(mem1_valid_0), .mem1_pc(mem1_pc_0), .mem1_inst(mem1_inst_0),
        .mem1_ret_pc(mem1_ret_pc_0), .mem1_alu_res(mem1_alu_res_0),
        .mem1_fw_rs2_data(mem1_fw_rs2_0), .mem1_agu_res(mem1_agu_res_0),
        .mem1_csr_rdata(mem1_csr_rdata_0), .mem1_rd(mem1_rd_0),
        .mem1_RegWen(mem1_RegWen_0), .mem1_MemWen(mem1_MemWen_0),
        .mem1_WbSel(mem1_WbSel_0), .mem1_funct3(mem1_funct3_0)
    );
    // Memory port MUX: inst0 priority, inst1 uses port when inst0 doesn't need it
    wire mem1_use_0 = mem1_valid_0 & (mem1_MemWen_0 | (mem1_WbSel_0 == 2'b10));
    wire mem1_use_1 = mem1_valid_1 & (mem1_MemWen_1 | (mem1_WbSel_1 == 2'b10)) & ~mem1_use_0;

    // inst0 StoreAlign
    wire [3:0] perip_mask_0; wire [31:0] perip_wdata_0;
    StoreAlign #(DATAWIDTH) sa_0 (.addr_offset(mem1_agu_res_0[1:0]), .wdata_in(mem1_fw_rs2_0),
        .size_mask(mem1_funct3_0[1:0]), .MemWrite(mem1_valid_0 & mem1_MemWen_0),
        .wmask_out(perip_mask_0), .wdata_out(perip_wdata_0));

    // inst1 StoreAlign
    wire [3:0] perip_mask_1; wire [31:0] perip_wdata_1;
    StoreAlign #(DATAWIDTH) sa_1 (.addr_offset(mem1_agu_res_1[1:0]), .wdata_in(mem1_fw_rs2_1),
        .size_mask(mem1_funct3_1[1:0]), .MemWrite(mem1_valid_1 & mem1_MemWen_1),
        .wmask_out(perip_mask_1), .wdata_out(perip_wdata_1));

    assign perip_addr  = mem1_use_0 ? mem1_agu_res_0 : mem1_agu_res_1;
    assign perip_wen   = mem1_use_0 ? (mem1_valid_0 & mem1_MemWen_0) : (mem1_valid_1 & mem1_MemWen_1);
    assign perip_mask  = mem1_use_0 ? perip_mask_0 : perip_mask_1;
    assign perip_wdata = mem1_use_0 ? perip_wdata_0 : perip_wdata_1;

    wire [31:0] mem1_fw_data_0 = (mem1_WbSel_0 == 2'b01) ? mem1_ret_pc_0 :
        (mem1_WbSel_0 == 2'b11) ? mem1_csr_rdata_0 : mem1_alu_res_0;

    // MEM2
    logic mem2_valid_0;
    logic [31:0] mem2_pc_0, mem2_inst_0, mem2_ret_pc_0, mem2_alu_res_0, mem2_agu_res_0, mem2_csr_rdata_0;
    logic [1:0] mem2_WbSel_0; logic [2:0] mem2_funct3_0;
    logic [4:0] mem2_rd_0; logic mem2_RegWen_0;

    MEM1_MEM2_Reg #(DATAWIDTH) mem1_mem2_0 (
        .clk(cpu_clk), .rst(cpu_rst), .stall(1'b0), .poison(1'b0),
        .mem1_valid(mem1_valid_0), .mem1_pc(mem1_pc_0), .mem1_inst(mem1_inst_0),
        .mem1_ret_pc(mem1_ret_pc_0), .mem1_alu_res(mem1_alu_res_0),
        .mem1_agu_res(mem1_agu_res_0), .mem1_csr_rdata(mem1_csr_rdata_0),
        .mem1_rd(mem1_rd_0), .mem1_RegWen(mem1_RegWen_0), .mem1_WbSel(mem1_WbSel_0),
        .mem1_funct3(mem1_funct3_0),
        .mem2_valid(mem2_valid_0), .mem2_pc(mem2_pc_0), .mem2_inst(mem2_inst_0),
        .mem2_ret_pc(mem2_ret_pc_0), .mem2_alu_res(mem2_alu_res_0),
        .mem2_agu_res(mem2_agu_res_0), .mem2_csr_rdata(mem2_csr_rdata_0),
        .mem2_rd(mem2_rd_0), .mem2_RegWen(mem2_RegWen_0), .mem2_WbSel(mem2_WbSel_0),
        .mem2_funct3(mem2_funct3_0)
    );
    wire [31:0] mem2_nd_0 = (mem2_WbSel_0 == 2'b01) ? mem2_ret_pc_0 :
        (mem2_WbSel_0 == 2'b11) ? mem2_csr_rdata_0 : mem2_alu_res_0;
    wire [31:0] mem2_fw_data_0 = (mem2_WbSel_0 == 2'b10) ? perip_rdata : mem2_nd_0;

    // WB inst0
    logic wb_valid_0; logic [31:0] wb_pc_0, wb_inst_0, wb_nd_0, wb_prdata_0;
    logic [1:0] wb_agu_lo_0, wb_WbSel_0; logic [2:0] wb_funct3_0;
    MEM2_WB_Reg #(DATAWIDTH) mem2_wb_0 (
        .clk(cpu_clk), .rst(cpu_rst), .stall(1'b0), .poison(1'b0),
        .mem2_valid(mem2_valid_0), .mem2_pc(mem2_pc_0), .mem2_inst(mem2_inst_0),
        .mem2_non_load_data(mem2_nd_0), .mem2_perip_rdata(perip_rdata),
        .mem2_agu_res_1_0(mem2_agu_res_0[1:0]), .mem2_funct3(mem2_funct3_0),
        .mem2_WbSel(mem2_WbSel_0), .mem2_rd(mem2_rd_0), .mem2_RegWen(mem2_RegWen_0),
        .wb_valid(wb_valid_0), .wb_pc(wb_pc_0), .wb_inst(wb_inst_0),
        .wb_non_load_data(wb_nd_0), .wb_perip_rdata(wb_prdata_0),
        .wb_agu_res_1_0(wb_agu_lo_0), .wb_funct3(wb_funct3_0),
        .wb_WbSel(wb_WbSel_0), .wb_rd(wb_rd_0), .wb_RegWen(wb_RegWen_0)
    );

    // === inst1 forwarding data at BR stage ===
    wire [31:0] br_fw_data_1 = br_alu_res_1;

    // === inst1 MEM1 stage (new symmetric pipeline) ===
    logic mem1_valid_1, mem1_MemWen_1;
    logic [31:0] mem1_pc_1, mem1_inst_1, mem1_ret_pc_1, mem1_alu_res_1;
    logic [31:0] mem1_fw_rs2_1, mem1_agu_res_1, mem1_csr_rdata_1;
    logic [1:0] mem1_WbSel_1; logic [2:0] mem1_funct3_1;
    logic [4:0] mem1_rd_1; logic mem1_RegWen_1;

    BR_MEM1_Reg #(DATAWIDTH) br_mem1_1 (
        .clk(cpu_clk), .rst(cpu_rst), .stall(1'b0), .poison(1'b0),
        .br_valid(br_valid_1), .br_pc(br_pc_1), .br_inst(br_inst_1),
        .br_ret_pc(br_ret_pc_1), .br_alu_res(br_alu_res_1),
        .br_fw_rs2_data(br_fw_rs2_1), .br_agu_res(br_agu_res_1),
        .br_csr_rdata(32'b0), .br_rd(br_rd_1),
        .br_RegWen(br_RegWen_1), .br_MemWen(br_MemWen_1), .br_WbSel(br_WbSel_1),
        .br_funct3(br_funct3_1),
        .mem1_valid(mem1_valid_1), .mem1_pc(mem1_pc_1), .mem1_inst(mem1_inst_1),
        .mem1_ret_pc(mem1_ret_pc_1), .mem1_alu_res(mem1_alu_res_1),
        .mem1_fw_rs2_data(mem1_fw_rs2_1), .mem1_agu_res(mem1_agu_res_1),
        .mem1_csr_rdata(mem1_csr_rdata_1), .mem1_rd(mem1_rd_1),
        .mem1_RegWen(mem1_RegWen_1), .mem1_MemWen(mem1_MemWen_1),
        .mem1_WbSel(mem1_WbSel_1), .mem1_funct3(mem1_funct3_1)
    );
    wire [31:0] mem1_fw_data_1 = (mem1_WbSel_1 == 2'b01) ? mem1_ret_pc_1 :
        (mem1_WbSel_1 == 2'b11) ? mem1_csr_rdata_1 : mem1_alu_res_1;

    // === inst1 MEM2 stage ===
    logic mem2_valid_1;
    logic [31:0] mem2_pc_1, mem2_inst_1, mem2_ret_pc_1, mem2_alu_res_1, mem2_agu_res_1, mem2_csr_rdata_1;
    logic [1:0] mem2_WbSel_1; logic [2:0] mem2_funct3_1;
    logic [4:0] mem2_rd_1; logic mem2_RegWen_1;

    MEM1_MEM2_Reg #(DATAWIDTH) mem1_mem2_1 (
        .clk(cpu_clk), .rst(cpu_rst), .stall(1'b0), .poison(1'b0),
        .mem1_valid(mem1_valid_1), .mem1_pc(mem1_pc_1), .mem1_inst(mem1_inst_1),
        .mem1_ret_pc(mem1_ret_pc_1), .mem1_alu_res(mem1_alu_res_1),
        .mem1_agu_res(mem1_agu_res_1), .mem1_csr_rdata(mem1_csr_rdata_1),
        .mem1_rd(mem1_rd_1), .mem1_RegWen(mem1_RegWen_1), .mem1_WbSel(mem1_WbSel_1),
        .mem1_funct3(mem1_funct3_1),
        .mem2_valid(mem2_valid_1), .mem2_pc(mem2_pc_1), .mem2_inst(mem2_inst_1),
        .mem2_ret_pc(mem2_ret_pc_1), .mem2_alu_res(mem2_alu_res_1),
        .mem2_agu_res(mem2_agu_res_1), .mem2_csr_rdata(mem2_csr_rdata_1),
        .mem2_rd(mem2_rd_1), .mem2_RegWen(mem2_RegWen_1), .mem2_WbSel(mem2_WbSel_1),
        .mem2_funct3(mem2_funct3_1)
    );
    wire [31:0] mem2_nd_1 = (mem2_WbSel_1 == 2'b01) ? mem2_ret_pc_1 :
        (mem2_WbSel_1 == 2'b11) ? mem2_csr_rdata_1 : mem2_alu_res_1;
    wire [31:0] mem2_fw_data_1 = (mem2_WbSel_1 == 2'b10) ? perip_rdata : mem2_nd_1;

    // === inst1 WB stage (unused for now, shift register still drives wb_*) ===
    logic wb_valid_1_pipe, wb_RegWen_1_pipe;
    logic [31:0] wb_pc_1_pipe, wb_inst_1_pipe, wb_nd_1_pipe, wb_prdata_1_pipe;
    logic [1:0] wb_agu_lo_1_pipe, wb_WbSel_1_pipe; logic [2:0] wb_funct3_1_pipe;
    logic [4:0] wb_rd_1_pipe;
    MEM2_WB_Reg #(DATAWIDTH) mem2_wb_1 (
        .clk(cpu_clk), .rst(cpu_rst), .stall(1'b0), .poison(1'b0),
        .mem2_valid(mem2_valid_1), .mem2_pc(mem2_pc_1), .mem2_inst(mem2_inst_1),
        .mem2_non_load_data(mem2_nd_1), .mem2_perip_rdata(perip_rdata),
        .mem2_agu_res_1_0(mem2_agu_res_1[1:0]), .mem2_funct3(mem2_funct3_1),
        .mem2_WbSel(mem2_WbSel_1), .mem2_rd(mem2_rd_1), .mem2_RegWen(mem2_RegWen_1),
        .wb_valid(wb_valid_1_pipe), .wb_pc(wb_pc_1_pipe), .wb_inst(wb_inst_1_pipe),
        .wb_non_load_data(wb_nd_1_pipe), .wb_perip_rdata(wb_prdata_1_pipe),
        .wb_agu_res_1_0(wb_agu_lo_1_pipe), .wb_funct3(wb_funct3_1_pipe),
        .wb_WbSel(wb_WbSel_1_pipe), .wb_rd(wb_rd_1_pipe), .wb_RegWen(wb_RegWen_1_pipe)
    );

    // WB inst1: 4-cycle shift register matching inst0 EX1→BR→MEM1→MEM2→WB
    // inst1_d1_en blocks new captures during br_flush (same as EX1_BR_Reg poison_BR)
    // d1→d2 gated by ~br_flush: kills inst1 paired with inst0 being flushed at BR
    logic [31:0] inst1_wb_d1, inst1_wb_d2, inst1_wb_d3, inst1_wb_data;
    logic [31:0] inst1_wb_pc_d1, inst1_wb_pc_d2, inst1_wb_pc_d3, wb_pc_1;
    logic [4:0]  inst1_wb_rd_d1, inst1_wb_rd_d2, inst1_wb_rd_d3, inst1_wb_rd;
    logic        inst1_wb_rw_d1, inst1_wb_rw_d2, inst1_wb_rw_d3, inst1_wb_RegWen;
    logic        inst1_wb_v_d1, inst1_wb_v_d2, inst1_wb_v_d3, wb_valid_1;
    wire         inst1_d1_en = ~stall_EX1 & ~br_flush;
    always_ff @(posedge cpu_clk) begin
        if (cpu_rst) begin
            inst1_wb_v_d1 <= 0; inst1_wb_v_d2 <= 0; inst1_wb_v_d3 <= 0; wb_valid_1 <= 0;
        end else begin
            inst1_wb_v_d1 <= ex1_valid_1 & ex1_RegWen_1 & inst1_d1_en;
            inst1_wb_v_d2 <= inst1_wb_v_d1 & ~br_flush;
            inst1_wb_v_d3 <= inst1_wb_v_d2;
            wb_valid_1    <= inst1_wb_v_d3;
            if (inst1_d1_en) begin
                inst1_wb_d1 <= ex1_alu_res_1;
                inst1_wb_pc_d1 <= ex1_pc_1;
                inst1_wb_rd_d1 <= ex1_rd_1;
                inst1_wb_rw_d1 <= ex1_RegWen_1;
            end
            inst1_wb_d2 <= inst1_wb_d1; inst1_wb_d3 <= inst1_wb_d2; inst1_wb_data <= inst1_wb_d3;
            inst1_wb_pc_d2 <= inst1_wb_pc_d1; inst1_wb_pc_d3 <= inst1_wb_pc_d2; wb_pc_1 <= inst1_wb_pc_d3;
            inst1_wb_rd_d2 <= inst1_wb_rd_d1; inst1_wb_rd_d3 <= inst1_wb_rd_d2; inst1_wb_rd <= inst1_wb_rd_d3;
            inst1_wb_rw_d2 <= inst1_wb_rw_d1; inst1_wb_rw_d3 <= inst1_wb_rw_d2; inst1_wb_RegWen <= inst1_wb_rw_d3;
        end
    end
    assign wb_data_1 = inst1_wb_data;
    assign wb_RegWen_1 = inst1_wb_RegWen;
    assign wb_rd_1   = inst1_wb_rd;

    // WB byte alignment (仅 inst0 loads)
    logic [7:0] wb_byte; logic [15:0] wb_half; logic [31:0] wb_ext;
    always_comb begin
        case(wb_agu_lo_0) 2'b00: wb_byte = wb_prdata_0[ 7: 0]; 2'b01: wb_byte = wb_prdata_0[15: 8];
            2'b10: wb_byte = wb_prdata_0[23:16]; 2'b11: wb_byte = wb_prdata_0[31:24]; endcase
        wb_half = wb_agu_lo_0[1] ? wb_prdata_0[31:16] : wb_prdata_0[15:0];
        case(wb_funct3_0) 3'b000: wb_ext = {{24{wb_byte[7]}}, wb_byte}; 3'b100: wb_ext = {24'b0, wb_byte};
            3'b001: wb_ext = {{16{wb_half[15]}}, wb_half}; 3'b101: wb_ext = {16'b0, wb_half}; default: wb_ext = wb_prdata_0; endcase
    end
    assign wb_data_0 = (wb_WbSel_0 == 2'b10) ? wb_ext : wb_nd_0;

    // =========================================================================
    // Hazard Detection (仅 inst0, 因为 inst1 仅在无依赖时发射)
    // =========================================================================
    HazardDetectionUnit hd_inst (
        .id_rs1(rf_rs1_0), .id_rs2(rf_rs2_0), .id_opcode(rf_inst_0[6:0]),
        .ex_RegWen(ex1_valid_0 & ex1_RegWen_0), .ex_WbSel(ex1_WbSel_0), .ex_rd(ex1_rd_0),
        .mem1_RegWen(br_valid_0 & br_RegWen_0), .mem1_WbSel(br_WbSel_0), .mem1_rd(br_rd_0),
        .ls_RegWen(mem1_valid_0 & mem1_RegWen_0), .ls_WbSel(mem1_WbSel_0), .ls_rd(mem1_rd_0),
        .stall_ID(hd_stall_RF), .flush_ID_EX(hd_flush_RF_EX1_0)
    );

    // =========================================================================
    // DiffTest + CSR Shadow (adapted for dual-issue, inst0 only)
    // =========================================================================
`ifdef NPC_TEST
    import "DPI-C" context function void set_csr_scope();
    logic [31:0] br_next_csr_val;
    always_comb begin
        case(br_CsrOp) 2'b00: br_next_csr_val = br_csr_wdata;
            2'b01: br_next_csr_val = br_csr_rdata_0 | br_csr_wdata;
            2'b10: br_next_csr_val = br_csr_rdata_0 & ~br_csr_wdata;
            default: br_next_csr_val = br_csr_wdata; endcase
    end
    logic mem1_csr_wen_d, mem2_csr_wen_d, wb_csr_wen_d;
    logic [11:0] mem1_csr_idx_d, mem2_csr_idx_d, wb_csr_idx_d;
    logic [31:0] mem1_csr_val_d, mem2_csr_val_d, wb_csr_val_d;
    logic mem1_ecall_d, mem2_ecall_d, wb_ecall_d;
    logic mem1_ebreak_d, mem2_ebreak_d, wb_ebreak_d;
    logic mem1_mret_d, mem2_mret_d, wb_mret_d;
    always_ff @(posedge cpu_clk) begin
        if (cpu_rst) begin
            mem1_csr_wen_d <= 0; mem2_csr_wen_d <= 0; wb_csr_wen_d <= 0;
            mem1_ecall_d <= 0; mem2_ecall_d <= 0; wb_ecall_d <= 0;
            mem1_ebreak_d <= 0; mem2_ebreak_d <= 0; wb_ebreak_d <= 0;
            mem1_mret_d <= 0; mem2_mret_d <= 0; wb_mret_d <= 0;
        end else begin
            mem1_csr_wen_d <= br_valid_0 & br_actual_csr_wen;
            mem1_ecall_d <= br_valid_0 & br_IsEcall; mem1_ebreak_d <= br_valid_0 & br_IsEbreak;
            mem1_mret_d <= br_valid_0 & br_IsMret;
            mem1_csr_idx_d <= br_csr_idx; mem1_csr_val_d <= br_next_csr_val;
            mem2_csr_wen_d <= mem1_csr_wen_d; mem2_csr_idx_d <= mem1_csr_idx_d;
            mem2_csr_val_d <= mem1_csr_val_d; mem2_ecall_d <= mem1_ecall_d;
            mem2_ebreak_d <= mem1_ebreak_d; mem2_mret_d <= mem1_mret_d;
            wb_csr_wen_d <= mem2_csr_wen_d; wb_csr_idx_d <= mem2_csr_idx_d;
            wb_csr_val_d <= mem2_csr_val_d; wb_ecall_d <= mem2_ecall_d;
            wb_ebreak_d <= mem2_ebreak_d; wb_mret_d <= mem2_mret_d;
        end
    end
    logic [31:0] dm_mstatus = 32'h1800, dm_mtvec = 0, dm_mscratch = 0, dm_mepc = 0, dm_mcause = 0;
    always_ff @(posedge cpu_clk) begin
        if (cpu_rst) begin dm_mstatus <= 32'h1800; dm_mtvec <= 0; dm_mscratch <= 0; dm_mepc <= 0; dm_mcause <= 0; end
        else if (wb_ecall_d) begin dm_mepc <= wb_pc_0; dm_mcause <= 32'hB;
            dm_mstatus <= {dm_mstatus[31:13], 2'b11, dm_mstatus[10:8], dm_mstatus[3], dm_mstatus[6:4], 1'b0, dm_mstatus[2:0]}; end
        else if (wb_ebreak_d) begin dm_mepc <= wb_pc_0; dm_mcause <= 32'h3;
            dm_mstatus <= {dm_mstatus[31:13], 2'b11, dm_mstatus[10:8], dm_mstatus[3], dm_mstatus[6:4], 1'b0, dm_mstatus[2:0]}; end
        else if (wb_mret_d) dm_mstatus <= {dm_mstatus[31:13], 2'b00, dm_mstatus[10:8], 1'b1, dm_mstatus[6:4], dm_mstatus[7], dm_mstatus[2:0]};
        else if (wb_csr_wen_d) begin
            case(wb_csr_idx_d) 12'h300: dm_mstatus <= wb_csr_val_d; 12'h305: dm_mtvec <= wb_csr_val_d;
                12'h340: dm_mscratch <= wb_csr_val_d; 12'h341: dm_mepc <= wb_csr_val_d;
                12'h342: dm_mcause <= wb_csr_val_d; default: ; endcase
        end
    end
    export "DPI-C" function get_csr;
    function int get_csr(input int idx);
        case(idx) 32'h300: return dm_mstatus; 32'h305: return dm_mtvec; 32'h340: return dm_mscratch;
            32'h341: return dm_mepc; 32'h342: return dm_mcause; default: return 0; endcase
    endfunction
    initial set_csr_scope();

    // =========================================================================
    // Performance counters (dual-issue aware)
    // =========================================================================
    logic [31:0] pf_commits, pf_branches, pf_mispredicts, pf_early, pf_micro, pf_br, pf_stall_f, pf_stall_b, pf_dual;
    wire f5_is_c0 = (f5_inst_0[6:0] == 7'b1100011) | (f5_inst_0[6:0] == 7'b1101111) | (f5_inst_0[6:0] == 7'b1100111);
    wire f5_is_c1 = (f5_inst_1[6:0] == 7'b1100011) | (f5_inst_1[6:0] == 7'b1101111) | (f5_inst_1[6:0] == 7'b1100111);
    always_ff @(posedge cpu_clk) begin
        if (cpu_rst) begin pf_commits<=0; pf_branches<=0; pf_mispredicts<=0; pf_early<=0; pf_micro<=0; pf_br<=0; pf_stall_f<=0; pf_stall_b<=0; pf_dual<=0; end
        else begin
            pf_commits <= pf_commits + (wb_valid_0 ? 1 : 0) + (wb_valid_1 ? 1 : 0);
            if (wb_valid_0 & wb_valid_1) pf_dual <= pf_dual + 1;
            if (f5_valid & (f5_is_c0 | f5_is_c1)) pf_branches <= pf_branches + 1;
            if (br_mispredict_0 | br_mispredict_1) pf_mispredicts <= pf_mispredicts + 1;
            if (early_flush) pf_early <= pf_early + 1;
            if (f5_micro_flush) pf_micro <= pf_micro + 1;
            if (br_flush) pf_br <= pf_br + 1;
            if (stall_frontend) pf_stall_f <= pf_stall_f + 1;
            if (stall_RF) pf_stall_b <= pf_stall_b + 1;
        end
    end
    export "DPI-C" function perf_get_counters;
    function void perf_get_counters(
        output int commits, output int branches, output int mispredicts,
        output int early_f, output int micro_f, output int br_f,
        output int stall_f, output int stall_b, output int dual_issues
    );
        commits=pf_commits; branches=pf_branches; mispredicts=pf_mispredicts;
        early_f=pf_early; micro_f=pf_micro; br_f=pf_br;
        stall_f=pf_stall_f; stall_b=pf_stall_b; dual_issues=pf_dual;
    endfunction
`endif

endmodule
