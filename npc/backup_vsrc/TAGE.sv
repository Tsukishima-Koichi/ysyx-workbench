`timescale 1ns / 1ps

/**
 * TAGE (TAgged GEometric history length) 方向预测器
 *
 * 4 表几何历史长度：T0(bimodal) / T1(hist=2) / T2(hist=8) / T3(hist=20)
 * 每表 256 条目，条目 = {tag[7:0], ctr[2:0], u[1:0]}
 *
 * 流水线：F2 哈希+读请求 → F3 BRAM 数据返回 → F4 标签匹配+提供者选择 → F5 输出
 * 训练更新：BR 级单周期 read-modify-write
 */
module TAGE #(
    parameter NUM_TABLES  = 4,
    parameter INDEX_BITS  = 8,
    parameter TAG_BITS    = 8,
    parameter GHR_WIDTH   = 32
)(
    input  logic        clk,
    input  logic        rst,

    // === F2: 哈希计算输入 ===
    input  logic [31:0] f2_pc,

    // === F5: 预测输出 (经内部流水线打拍) ===
    output logic        f5_pred_taken,
    output logic        f5_has_provider,
    output logic [1:0]  f5_provider_idx,

    // === BR 级训练更新 ===
    input  logic        update_valid,
    input  logic [31:0] update_pc,
    input  logic        update_taken,
    input  logic        update_is_branch,   // table training gate (all branches/jumps)
    input  logic        update_ghr,         // GHR update (conditional branches only)

    // === GHR 全局历史寄存器 (可观测) ===
    output logic [GHR_WIDTH-1:0] ghr
);
    localparam TABLE_SIZE = 1 << INDEX_BITS;
    // 几何历史长度序列
    localparam int HIST_LEN [NUM_TABLES-1:0] = '{0, 2, 8, 20};

    // =========================================================================
    // 全局历史寄存器 (GHR)
    // =========================================================================
    always_ff @(posedge clk) begin
        if (rst)
            ghr <= '0;
        else if (update_valid && update_ghr)
            ghr <= {ghr[GHR_WIDTH-2:0], update_taken};
    end

    // =========================================================================
    // 哈希函数：PC 索引 ^ 折叠 GHR
    // =========================================================================
    function automatic logic [INDEX_BITS-1:0] hash_idx(
        input [31:0] hash_pc,
        input [GHR_WIDTH-1:0] ghr_val,
        input [5:0] hist_len
    );
        logic [INDEX_BITS-1:0] pc_idx;
        logic [INDEX_BITS-1:0] folded;
        integer i;
        pc_idx = hash_pc[INDEX_BITS+1 : 2];
        folded = '0;
        for (i = 0; i < INDEX_BITS; i++) begin
            if (i < hist_len) folded[i] = ghr_val[i];
            // XOR-fold extra history bits into index
            for (int j = INDEX_BITS; j < hist_len; j += INDEX_BITS) begin
                if (i + j < hist_len) folded[i] = folded[i] ^ ghr_val[i + j];
            end
        end
        return pc_idx ^ folded;
    endfunction

    // =========================================================================
    // 存储阵列 (BRAM 推断)
    // =========================================================================
    // entry = {tag[7:0], ctr[2:0], u[1:0]}
    (* ram_style = "block" *)
    logic [TAG_BITS+4:0] table0_mem [TABLE_SIZE-1:0];
    (* ram_style = "block" *)
    logic [TAG_BITS+4:0] table1_mem [TABLE_SIZE-1:0];
    (* ram_style = "block" *)
    logic [TAG_BITS+4:0] table2_mem [TABLE_SIZE-1:0];
    (* ram_style = "block" *)
    logic [TAG_BITS+4:0] table3_mem [TABLE_SIZE-1:0];

    // =========================================================================
    // F2 → F3: 哈希计算 + BRAM 读请求
    // =========================================================================
    wire [INDEX_BITS-1:0] f2_idx [NUM_TABLES-1:0];
    wire [TAG_BITS-1:0]   f2_tag = f2_pc[INDEX_BITS+TAG_BITS+1 : INDEX_BITS+2];

    genvar g;
    generate
        for (g = 0; g < NUM_TABLES; g++) begin : gen_hash
            assign f2_idx[g] = hash_idx(f2_pc, ghr, 6'(HIST_LEN[g]));
        end
    endgenerate

    // 流水线寄存器: F2→F3, F3→F4
    logic [TAG_BITS+4:0] f3_entry [NUM_TABLES-1:0];
    logic [TAG_BITS-1:0] f3_pc_tag, f4_pc_tag;
    logic [INDEX_BITS-1:0] f3_idx [NUM_TABLES-1:0];

    // F2 → F3: BRAM 读结果锁存
    always_ff @(posedge clk) begin
        f3_entry[0] <= table0_mem[f2_idx[0]];
        f3_entry[1] <= table1_mem[f2_idx[1]];
        f3_entry[2] <= table2_mem[f2_idx[2]];
        f3_entry[3] <= table3_mem[f2_idx[3]];
        f3_pc_tag   <= f2_tag;
        for (int t = 0; t < NUM_TABLES; t++)
            f3_idx[t] <= f2_idx[t];
    end

    // =========================================================================
    // F3 → F4: 标签匹配 + 提供者选择 (组合逻辑，下一拍锁存)
    // =========================================================================
    logic [NUM_TABLES-1:0] f3_tag_match;
    logic [2:0]            f3_ctr [NUM_TABLES-1:0];

    always_comb begin
        for (int t = 0; t < NUM_TABLES; t++) begin
            f3_ctr[t] = f3_entry[t][4:2];
            if (t == 0)
                // T0 bimodal: no tag, always "matches"
                f3_tag_match[t] = 1'b1;
            else
                f3_tag_match[t] = (f3_entry[t][TAG_BITS+4:5] == f3_pc_tag);
        end
    end

    // 提供者选择: 最长历史匹配表
    logic [1:0] f3_provider;
    logic       f3_has_provider;
    always_comb begin
        f3_provider     = 2'b00;
        f3_has_provider  = 1'b0;
        for (int t = NUM_TABLES-1; t >= 0; t--) begin
            if (f3_tag_match[t]) begin
                f3_provider    = t[1:0];
                f3_has_provider = 1'b1;
                break;
            end
        end
    end

    // F3 → F4 锁存
    logic [1:0] f4_provider;
    logic       f4_has_provider;
    logic [2:0] f4_ctr_val;

    always_ff @(posedge clk) begin
        f4_provider     <= f3_provider;
        f4_has_provider  <= f3_has_provider;
        f4_ctr_val      <= f3_ctr[f3_provider];
        f4_pc_tag       <= f3_pc_tag;
    end

    // =========================================================================
    // F4 → F5: 预测输出锁存
    // =========================================================================
    // 3-bit 饱和计数器: MSB 决定方向 (1 = taken, 0 = not-taken)
    always_ff @(posedge clk) begin
        f5_pred_taken    <= f4_has_provider && f4_ctr_val[2];
        f5_has_provider  <= f4_has_provider;
        f5_provider_idx  <= f4_provider;
    end

    // =========================================================================
    // BR 级训练更新 (split combinational path across 2 cycles)
    //
    // Pipeline: S0 (capture+BRAM read) → S1 (provider+counter) → S2 (usefulness+
    //            allocation+decay+writeback). 3 cycles total, same latency as
    //            original, but each combinational cloud is smaller → higher fMAX.
    //
    // Q (upd_q_valid): 1-entry backup queue when pipeline is busy.
    // =========================================================================

    // --- S0: 锁存更新信息，发起 BRAM 读 ---
    logic                    upd_pending;
    logic [TAG_BITS-1:0]     s0_tag;
    logic                    s0_taken;
    logic [INDEX_BITS-1:0]   s0_idx [NUM_TABLES-1:0];

    // --- S1: BRAM 读结果 + 第一级计算 (provider, counter, pred_correct) ---
    logic                    upd_s1_valid;
    logic [TAG_BITS-1:0]     s1_tag;
    logic                    s1_taken;
    logic [INDEX_BITS-1:0]   s1_idx [NUM_TABLES-1:0];
    logic [TAG_BITS+4:0]     s1_read [NUM_TABLES-1:0];
    logic [1:0]              s1_provider;
    logic [2:0]              s1_new_ctr [NUM_TABLES-1:0];
    logic                    s1_pred_correct;

    // --- S2: 第二级计算 (usefulness, allocation, decay) + BRAM 写回 ---
    logic                    upd_s2_valid;
    logic [INDEX_BITS-1:0]   s2_idx [NUM_TABLES-1:0];
    logic [TAG_BITS+4:0]     s2_read [NUM_TABLES-1:0];
    logic [1:0]              s2_provider;
    logic [2:0]              s2_ctr   [NUM_TABLES-1:0];
    logic                    s2_pred_correct;
    logic [TAG_BITS-1:0]     s2_tag;
    logic                    s2_taken;

    // --- 备份队列 ---
    logic                    upd_q_valid;
    logic [TAG_BITS-1:0]     upd_q_tag;
    logic                    upd_q_taken;
    logic [INDEX_BITS-1:0]   upd_q_idx [NUM_TABLES-1:0];

    // 训练流水线状态机
    always_ff @(posedge clk) begin
        if (rst) begin
            upd_pending  <= 1'b0;
            upd_s1_valid <= 1'b0;
            upd_s2_valid <= 1'b0;
            upd_q_valid  <= 1'b0;
        end else begin
            // 流水线自动推进
            upd_s1_valid <= upd_pending;
            upd_s2_valid <= upd_s1_valid;

            // 处理新到达的更新
            if (update_valid && update_is_branch) begin
                if (!upd_pending) begin
                    upd_pending <= 1'b1;
                    s0_tag      <= update_pc[INDEX_BITS+TAG_BITS+1 : INDEX_BITS+2];
                    s0_taken    <= update_taken;
                    for (int t = 0; t < NUM_TABLES; t++)
                        s0_idx[t] <= hash_idx(update_pc, ghr, 6'(HIST_LEN[t]));
                end else if (!upd_q_valid) begin
                    upd_q_valid <= 1'b1;
                    upd_q_tag   <= update_pc[INDEX_BITS+TAG_BITS+1 : INDEX_BITS+2];
                    upd_q_taken <= update_taken;
                    for (int t = 0; t < NUM_TABLES; t++)
                        upd_q_idx[t] <= hash_idx(update_pc, ghr, 6'(HIST_LEN[t]));
                end
            end

            // S1 完成时释放 S0，若 Q 有数据则自动载入
            if (upd_s1_valid) begin
                upd_pending <= upd_q_valid;
                if (upd_q_valid) begin
                    s0_tag      <= upd_q_tag;
                    s0_taken    <= upd_q_taken;
                    for (int t = 0; t < NUM_TABLES; t++)
                        s0_idx[t] <= upd_q_idx[t];
                    upd_q_valid <= 1'b0;
                end
            end

            // S1→S2 数据转移
            if (upd_s1_valid) begin
                for (int t = 0; t < NUM_TABLES; t++) begin
                    s2_idx[t]  <= s1_idx[t];
                    s2_read[t] <= s1_read[t];
                end
                s2_provider     <= s1_provider;
                s2_ctr          <= s1_new_ctr;
                s2_pred_correct <= s1_pred_correct;
                s2_tag          <= s1_tag;
                s2_taken        <= s1_taken;
            end
        end
    end

    // S0 → S1: BRAM 读 + 索引/标记转移
    always_ff @(posedge clk) begin
        if (upd_pending) begin
            s1_read[0] <= table0_mem[s0_idx[0]];
            s1_read[1] <= table1_mem[s0_idx[1]];
            s1_read[2] <= table2_mem[s0_idx[2]];
            s1_read[3] <= table3_mem[s0_idx[3]];
            for (int t = 0; t < NUM_TABLES; t++)
                s1_idx[t] <= s0_idx[t];
            s1_tag   <= s0_tag;
            s1_taken <= s0_taken;
        end
    end

    // =========================================================================
    // S1 组合逻辑: provider 搜索 + 计数器更新 + 预测正确性
    // =========================================================================
    always_comb begin
        s1_provider     = 2'b00;
        s1_pred_correct = 1'b0;
        for (int t = 0; t < NUM_TABLES; t++)
            s1_new_ctr[t] = s1_read[t][4:2];

        if (upd_s1_valid) begin
            for (int t = NUM_TABLES-1; t >= 0; t--) begin
                if (t == 0 || (s1_read[t][TAG_BITS+4:5] == s1_tag)) begin
                    s1_provider = t[1:0];
                    break;
                end
            end

            if (s1_taken && s1_new_ctr[s1_provider] < 3'b111)
                s1_new_ctr[s1_provider] = s1_new_ctr[s1_provider] + 1;
            else if (!s1_taken && s1_new_ctr[s1_provider] > 3'b000)
                s1_new_ctr[s1_provider] = s1_new_ctr[s1_provider] - 1;

            s1_pred_correct = (s1_read[s1_provider][4] == s1_taken);
        end
    end

    // =========================================================================
    // S2 组合逻辑: usefulness + allocation + decay
    // =========================================================================
    logic [TAG_BITS-1:0] s2_new_tag [NUM_TABLES-1:0];
    logic [2:0]          s2_new_ctr [NUM_TABLES-1:0];
    logic [1:0]          s2_new_u   [NUM_TABLES-1:0];

    always_comb begin
        for (int t = 0; t < NUM_TABLES; t++) begin
            s2_new_tag[t] = s2_read[t][TAG_BITS+4:5];
            s2_new_ctr[t] = s2_ctr[t];
            s2_new_u[t]   = s2_read[t][1:0];
        end

        if (upd_s2_valid) begin
            if (s2_pred_correct) begin
                if (s2_new_u[s2_provider] < 2'b11)
                    s2_new_u[s2_provider] = s2_new_u[s2_provider] + 1;
            end else begin
                for (int t = 0; t < NUM_TABLES; t++) begin
                    if (t > s2_provider && (t != 0 && s2_read[t][TAG_BITS+4:5] != s2_tag) && s2_read[t][1:0] == 2'b00) begin
                        s2_new_tag[t] = s2_tag;
                        s2_new_ctr[t] = s2_taken ? 3'b100 : 3'b011;
                        s2_new_u[t]   = 2'b00;
                        break;
                    end
                end
                for (int t = 0; t < NUM_TABLES; t++) begin
                    if (t != int'(s2_provider) && s2_new_u[t] > 2'b00)
                        s2_new_u[t] = s2_new_u[t] - 1;
                end
            end
        end
    end

    // =========================================================================
    // S2: BRAM 写回
    // =========================================================================
    always_ff @(posedge clk) begin
        if (upd_s2_valid) begin
            table0_mem[s2_idx[0]] <= {s2_new_tag[0], s2_new_ctr[0], s2_new_u[0]};
            table1_mem[s2_idx[1]] <= {s2_new_tag[1], s2_new_ctr[1], s2_new_u[1]};
            table2_mem[s2_idx[2]] <= {s2_new_tag[2], s2_new_ctr[2], s2_new_u[2]};
            table3_mem[s2_idx[3]] <= {s2_new_tag[3], s2_new_ctr[3], s2_new_u[3]};
        end
    end

    // =========================================================================
    // 上电初始化
    // =========================================================================
    initial begin
        for (int i = 0; i < TABLE_SIZE; i++) begin
            table0_mem[i] = '0;
            table0_mem[i][4:2] = 3'b011;  // T0 bimodal: weakly-taken bias
            table1_mem[i] = '0;
            table2_mem[i] = '0;
            table3_mem[i] = '0;
        end
    end
endmodule
