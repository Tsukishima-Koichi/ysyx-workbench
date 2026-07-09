`timescale 1ns / 1ps

/**
 * NLP (Next-Line Predictor) — F1 级 0-cycle LUTRAM 循环预测器
 *
 * 条目格式: {valid, conf[1:0], tag[7:0], target[31:0]}
 *   索引 PC[INDEX_BITS+1:2], 标签 PC[TAG_BITS+INDEX_BITS+1 : INDEX_BITS+2]
 *
 * 训练策略 (借鉴 AMD Zen Loop Predictor):
 *   - 仅训练后向分支 (target < pc, 即循环回边)
 *   - 同 tag 重复 taken → 置信度递增 (饱和 3)
 *   - 新 tag 或别名 → 弱预测起步 (conf=1)
 *   - F5 微冲刷可反馈降级 (decrement_* 端口，默认未连接)
 * 预测门控: valid && tag_match && conf >= 1 (至少见过一次)
 */
module NLP #(
    parameter INDEX_BITS = 8,
    parameter TAG_BITS   = 8,
    parameter DATAWIDTH  = 32
)(
    input  logic                     clk,
    input  logic                     rst,

    // === F1 预测请求 (组合逻辑, 0-cycle) ===
    input  logic [DATAWIDTH-1:0]     f1_pc,
    output logic [DATAWIDTH-1:0]     nlp_target,
    output logic                     nlp_hit,

    // === BR 级训练更新 (同步写) ===
    input  logic                     update_valid,
    input  logic [DATAWIDTH-1:0]     update_pc,
    input  logic [DATAWIDTH-1:0]     update_target,

    // === F5 微冲刷反馈 (可选连接, 默认为不活跃) ===
    input  logic                     decrement_valid = 1'b0,
    input  logic [DATAWIDTH-1:0]     decrement_pc    = '0
);
    localparam TABLE_SIZE  = 1 << INDEX_BITS;
    localparam CONF_BITS   = 2;
    localparam ENTRY_WIDTH = 1 + CONF_BITS + TAG_BITS + DATAWIDTH;  // 1+2+8+32 = 43

    // 条目位域: {valid[42], conf[41:40], tag[39:32], target[31:0]}
    localparam VALID_BIT = ENTRY_WIDTH - 1;               // 42
    localparam CONF_HI   = VALID_BIT - 1;                 // 41
    localparam CONF_LO   = VALID_BIT - CONF_BITS;         // 40
    localparam TAG_HI    = CONF_LO - 1;                   // 39
    localparam TAG_LO    = TAG_HI - TAG_BITS + 1;         // 32
    localparam TGT_HI    = TAG_LO - 1;                    // 31
    localparam TGT_LO    = 0;                             // 0

    // === 读端口 (组合逻辑) ===
    wire [INDEX_BITS-1:0] r_idx = f1_pc[INDEX_BITS+1 : 2];
    wire [TAG_BITS-1:0]   r_tag = f1_pc[TAG_BITS+INDEX_BITS+1 : INDEX_BITS+2];

    // === 写端口 (训练) ===
    wire [INDEX_BITS-1:0] w_idx = update_pc[INDEX_BITS+1 : 2];
    wire [TAG_BITS-1:0]   w_tag = update_pc[TAG_BITS+INDEX_BITS+1 : INDEX_BITS+2];

    // === 降级端口 ===
    wire [INDEX_BITS-1:0] dec_idx = decrement_pc[INDEX_BITS+1 : 2];

    // LUTRAM — 0-cycle 组合读
    (* ram_style = "distributed" *)
    logic [ENTRY_WIDTH-1:0] nlp_entry [TABLE_SIZE-1:0];

    wire                 stored_valid = nlp_entry[r_idx][VALID_BIT];
    wire [CONF_BITS-1:0] stored_conf  = nlp_entry[r_idx][CONF_HI:CONF_LO];
    wire [TAG_BITS-1:0]  stored_tag   = nlp_entry[r_idx][TAG_HI:TAG_LO];
    wire [DATAWIDTH-1:0] stored_tgt   = nlp_entry[r_idx][TGT_HI:TGT_LO];

    // 仅当已见过 (conf >= 1) 且标签匹配时才预测
    assign nlp_target = stored_tgt;
    assign nlp_hit    = stored_valid && (stored_tag == r_tag) && (stored_conf >= 2'b01);

    // === 训练逻辑 ===
    // 仅训练后向跳转 (循环回边), 过滤 if-else 前向分支
    wire is_backward = (update_target < update_pc);
    wire w_same_tag  = (nlp_entry[w_idx][TAG_HI:TAG_LO] == w_tag) && nlp_entry[w_idx][VALID_BIT];

    always_ff @(posedge clk) begin
        if (update_valid && is_backward) begin
            if (w_same_tag) begin
                // 同一分支再次 taken → 置信度递增 (饱和 3)
                if (nlp_entry[w_idx][CONF_HI:CONF_LO] < 2'b11)
                    nlp_entry[w_idx] <= {1'b1, nlp_entry[w_idx][CONF_HI:CONF_LO] + 2'b01, w_tag, update_target};
                else
                    nlp_entry[w_idx] <= {1'b1, 2'b11, w_tag, update_target};
            end else begin
                // 新分支或别名冲突 → 弱预测起步
                nlp_entry[w_idx] <= {1'b1, 2'b01, w_tag, update_target};
            end
        end else if (decrement_valid && !update_valid) begin
            // NLP 过度预测 (BTB+TAGE 否决) → 降级置信度
            if (nlp_entry[dec_idx][CONF_HI:CONF_LO] > 2'b00)
                nlp_entry[dec_idx][VALID_BIT:CONF_LO] <= {1'b1, nlp_entry[dec_idx][CONF_HI:CONF_LO] - 2'b01};
        end
    end

    // === 上电初始化 ===
    initial begin
        for (int i = 0; i < TABLE_SIZE; i++) begin
            nlp_entry[i] = '0;
        end
    end
endmodule
