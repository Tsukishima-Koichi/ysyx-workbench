`timescale 1ns / 1ps

module BranchPredictor #(
    parameter PC_WIDTH = 32,
    parameter INDEX_BITS = 10, 
    parameter GHR_WIDTH = 10   // 🌟 方案1：扩展至 10位，完美对齐哈希折叠
)(
    input  logic                clk,
    input  logic                rst,          // 🌟 新增：复位信号
    
    // --- IF1/IF2 前端预测 ---
    input  logic [PC_WIDTH-1:0] if1_pc,
    input  logic [PC_WIDTH-1:0] if2_pc, 
    input  logic [31:0]         if2_inst,     // 🌟 方案2：嗅探指令，预解码 RAS
    input  logic                if2_valid,    // 🌟 方案3：指示前端指令是否有效
    input  logic                if2_stall,    // 🌟 方案3：流水线阻塞标志
    output logic                if2_pred_taken,
    output logic [PC_WIDTH-1:0] if2_pred_target,
    
    // --- EX 后端更新 ---
    input  logic                ex_is_cond,   // 🌟 方案1：仅条件分支 (Branch)
    input  logic                ex_is_jump,   // 🌟 方案1：无条件跳转 (JAL/JALR)
    input  logic [PC_WIDTH-1:0] ex_pc,
    input  logic                ex_actual_taken,
    input  logic [PC_WIDTH-1:0] ex_actual_target,
    input  logic                ex_mispredict // 🌟 方案3：分支预测失败回滚标志
);
    localparam TABLE_SIZE = 1 << INDEX_BITS;
    
    // ========================================
    // 🌟 1. 预译码与硬件 RAS (返回地址栈)
    // ========================================
    wire [6:0] opcode = if2_inst[6:0];
    wire [4:0] rd     = if2_inst[11:7];
    wire [4:0] rs1    = if2_inst[19:15];
    
    wire is_jal   = (opcode == 7'b1101111);
    wire is_jalr  = (opcode == 7'b1100111);
    wire is_jump  = is_jal || is_jalr;
    wire is_cond  = (opcode == 7'b1100011);
    
    // 遵守 RISC-V ABI：rd 为 x1/x5 时是 Call；rs1 为 x1/x5 且不等于 rd 时是 Ret
    wire is_call  = is_jump && (rd == 5'd1 || rd == 5'd5);
    wire is_ret   = is_jalr && (rs1 == 5'd1 || rs1 == 5'd5) && (rs1 != rd);

    logic [PC_WIDTH-1:0] ras [7:0]; // 8深度微型栈
    logic [2:0]          ras_ptr;
    // 栈顶指针取 ras_ptr - 1。利用 Verilog 溢出特性，0 减 1 会自动回绕到 7，形成天然环形队列
    wire  [PC_WIDTH-1:0] ras_top = ras[ras_ptr - 3'd1];

    // ========================================
    // 🌟 2. 提取 Index、Tag 与双历史寄存器
    // ========================================
    logic [GHR_WIDTH-1:0] spec_ghr; // 前端推测历史 (零延迟实时更新)
    logic [GHR_WIDTH-1:0] arch_ghr; // 后端架构历史 (防污染安全更新)

    wire [INDEX_BITS-1:0]          if1_idx = if1_pc[INDEX_BITS+1 : 2];
    wire [INDEX_BITS-1:0]          ex_idx  = ex_pc[INDEX_BITS+1 : 2];
    
    // ✅ 修复点：补回了之前被误删的 Tag 提取逻辑！
    wire [PC_WIDTH-INDEX_BITS-3:0] if2_tag = if2_pc[PC_WIDTH-1 : INDEX_BITS+2];
    wire [PC_WIDTH-INDEX_BITS-3:0] ex_tag  = ex_pc[PC_WIDTH-1 : INDEX_BITS+2];

    wire [INDEX_BITS-1:0] if1_pht_idx = if1_idx ^ spec_ghr; // 前端查表用推测历史
    wire [INDEX_BITS-1:0] ex_pht_idx  = ex_idx  ^ arch_ghr; // 后端写回用架构历史

    // ========================================
    // 3. 存储结构定义
    // ========================================
    logic [PC_WIDTH-INDEX_BITS-3:0] btb_tag     [TABLE_SIZE-1:0];
    logic [PC_WIDTH-1:0]            btb_target  [TABLE_SIZE-1:0];
    logic                           btb_valid   [TABLE_SIZE-1:0];
    logic                           btb_is_jump [TABLE_SIZE-1:0]; // 记录是否为必跳指令
    logic [1:0]                     pht         [TABLE_SIZE-1:0];

    logic [PC_WIDTH-INDEX_BITS-3:0] read_tag;
    logic [PC_WIDTH-1:0]            read_target;
    logic                           read_valid;
    logic                           read_is_jump;
    logic [1:0]                     read_pht;

    initial begin
        for (int i = 0; i < TABLE_SIZE; i++) begin
            btb_valid[i] = 1'b0; btb_is_jump[i] = 1'b0; pht[i] = 2'b01; 
        end
    end

    // BRAM 同步读取端
    always_ff @(posedge clk) begin
        read_tag     <= btb_tag[if1_idx];
        read_target  <= btb_target[if1_idx];
        read_valid   <= btb_valid[if1_idx];
        read_is_jump <= btb_is_jump[if1_idx];
        read_pht     <= pht[if1_pht_idx]; // 基于 spec_ghr 查表
    end

    // ========================================
    // 4. IF2 综合预测决断
    // ========================================
    wire tag_match = (read_valid === 1'b1) && (read_tag === if2_tag);
    
    // 🌟决断：若是 Ret 强判跳；如果是命中且(BTB标记为必跳 或 PHT建议跳)，则跳转
    assign if2_pred_taken  = is_ret || (tag_match && (read_is_jump || is_jump || read_pht[1] == 1'b1));
    // 🌟目标：若是 Ret，无视 BTB 数据，直接接管为 RAS 栈顶！
    assign if2_pred_target = is_ret ? ras_top : read_target;

    // ========================================
    // 5. 状态机更新与恢复逻辑
    // ========================================
    always_ff @(posedge clk) begin
        if (rst) begin
            spec_ghr <= '0; arch_ghr <= '0; ras_ptr  <= '0;
        end else begin
            // --- A. 预测失败时的无情回滚 ---
            if (ex_mispredict) begin
                // 🚨 利用 EX 阶段的真实历史 + 当前分支的真实走向，瞬间修复前端历史
                spec_ghr <= ex_is_cond ? {arch_ghr[GHR_WIDTH-2:0], ex_actual_taken} : arch_ghr;
            end 
            // --- B. 前端推测更新 (且必须不在冲刷或停顿状态) ---
            else if (if2_valid && !if2_stall) begin
                if (is_cond) begin
                    spec_ghr <= {spec_ghr[GHR_WIDTH-2:0], if2_pred_taken}; // 推测移位
                end
                
                // 处理 RAS 压栈与出栈
                if (is_call) begin
                    ras[ras_ptr] <= if2_pc + 32'd4;
                    ras_ptr <= ras_ptr + 3'd1;
                end else if (is_ret) begin
                    ras_ptr <= ras_ptr - 3'd1;
                end
            end

            // --- C. EX 阶段真实架构更新 ---
            if (ex_is_cond || ex_is_jump) begin
                // BTB 物理通道更新 (Branch和Jump都要去认门)
                btb_valid[ex_idx]   <= 1'b1;
                btb_tag[ex_idx]     <= ex_tag;   // ✅ 修复：此处用上重新声明的 ex_tag
                btb_target[ex_idx]  <= ex_actual_target;
                btb_is_jump[ex_idx] <= ex_is_jump;
                
                // ⚠️ 方案一发力：仅条件分支才去触碰 PHT 和架构历史！
                if (ex_is_cond) begin
                    arch_ghr <= {arch_ghr[GHR_WIDTH-2:0], ex_actual_taken};
                    
                    // 🌟 经典 2-bit 饱和计数器
                    case (pht[ex_pht_idx])
                        2'b00: pht[ex_pht_idx] <= ex_actual_taken ? 2'b01 : 2'b00;
                        2'b01: pht[ex_pht_idx] <= ex_actual_taken ? 2'b10 : 2'b00;
                        2'b10: pht[ex_pht_idx] <= ex_actual_taken ? 2'b11 : 2'b01;
                        2'b11: pht[ex_pht_idx] <= ex_actual_taken ? 2'b11 : 2'b10;
                    endcase
                end
            end
        end
    end
endmodule
