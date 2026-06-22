`timescale 1ns / 1ps

/**
 * NLP (Next-Line Predictor) — F1 级 0-cycle 快速预测器
 *
 * 物理实现：分布式 RAM (LUTRAM)，组合逻辑读
 * 条目格式：{valid, tag[7:0], target[31:0]}
 * 索引 PC[INDEX_BITS+1:2]，标签 PC[TAG_BITS+INDEX_BITS+1 : INDEX_BITS+2]
 */
module NLP #(
    parameter INDEX_BITS = 8,
    parameter TAG_BITS   = 8,
    parameter DATAWIDTH  = 32
)(
    input  logic                     clk,
    input  logic                     rst,

    // === F1 预测请求 (组合逻辑，0-cycle) ===
    input  logic [DATAWIDTH-1:0]     f1_pc,
    output logic [DATAWIDTH-1:0]     nlp_target,
    output logic                     nlp_hit,

    // === BR 级训练更新 (同步写) ===
    input  logic                     update_valid,
    input  logic [DATAWIDTH-1:0]     update_pc,
    input  logic [DATAWIDTH-1:0]     update_target
);
    localparam TABLE_SIZE  = 1 << INDEX_BITS;
    localparam ENTRY_WIDTH = 1 + TAG_BITS + DATAWIDTH;  // 1 + 8 + 32 = 41

    wire [INDEX_BITS-1:0] r_idx = f1_pc[INDEX_BITS+1 : 2];
    wire [TAG_BITS-1:0]   r_tag = f1_pc[TAG_BITS+INDEX_BITS+1 : INDEX_BITS+2];

    wire [INDEX_BITS-1:0] w_idx = update_pc[INDEX_BITS+1 : 2];
    wire [TAG_BITS-1:0]   w_tag = update_pc[TAG_BITS+INDEX_BITS+1 : INDEX_BITS+2];

    // LUTRAM — 0-cycle 组合读
    (* ram_style = "distributed" *)
    logic [ENTRY_WIDTH-1:0] nlp_entry [TABLE_SIZE-1:0];

    wire                stored_valid = nlp_entry[r_idx][ENTRY_WIDTH-1];
    wire [TAG_BITS-1:0] stored_tag   = nlp_entry[r_idx][ENTRY_WIDTH-2 : DATAWIDTH];
    wire [DATAWIDTH-1:0] stored_tgt  = nlp_entry[r_idx][DATAWIDTH-1 : 0];

    assign nlp_target = stored_tgt;
    assign nlp_hit    = stored_valid && (stored_tag == r_tag);

    always_ff @(posedge clk) begin
        if (update_valid) begin
            nlp_entry[w_idx] <= {1'b1, w_tag, update_target};
        end
    end

    initial begin
        for (int i = 0; i < TABLE_SIZE; i++) begin
            nlp_entry[i] = '0;
        end
    end
endmodule
