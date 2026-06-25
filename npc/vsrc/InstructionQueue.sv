`timescale 1ns / 1ps

/**
 * 双发射指令队列 — 2 写端口 + 2 读端口
 * 后端每周期可弹出 1 或 2 条指令 (pop_count 指示消耗量)
 */
module InstructionQueue #(
    parameter DEPTH = 8,
    parameter DATAWIDTH = 32
)(
    input  logic clk, rst, flush,

    // === 写入 (来自 F5) ===
    input  logic                 push_valid_0, push_valid_1,
    input  logic [DATAWIDTH-1:0] push_pc_0, push_pc_1,
    input  logic [DATAWIDTH-1:0] push_inst_0, push_inst_1,
    input  logic                 push_pred_taken_0, push_pred_taken_1,
    input  logic [DATAWIDTH-1:0] push_pred_target_0, push_pred_target_1,

    output logic                 almost_full,

    // === 读出 (去 ID) — 双端口, 每周期消耗 0/1/2 条 ===
    input  logic                 pop_ready,        // 后端未停顿
    input  logic [1:0]           pop_count,        // 0=none, 1=single, 2=dual

    output logic                 pop_valid_0, pop_valid_1,
    output logic [DATAWIDTH-1:0] pop_pc_0, pop_pc_1,
    output logic [DATAWIDTH-1:0] pop_inst_0, pop_inst_1,
    output logic                 pop_pred_taken_0, pop_pred_taken_1,
    output logic [DATAWIDTH-1:0] pop_pred_target_0, pop_pred_target_1
);
    localparam PTR_WIDTH = $clog2(DEPTH);

    logic [DATAWIDTH-1:0] queue_pc          [DEPTH-1:0];
    logic [DATAWIDTH-1:0] queue_inst        [DEPTH-1:0];
    logic                 queue_pred_taken  [DEPTH-1:0];
    logic [DATAWIDTH-1:0] queue_pred_target [DEPTH-1:0];

    logic [PTR_WIDTH:0] rptr, wptr;
    logic [PTR_WIDTH:0] count;

    assign count = wptr - rptr;
    // 反压阈值降低: 需要容纳前端 2 条 + 当前可能消费 2 条
    assign almost_full = (count >= (DEPTH - 3));

    assign pop_valid_0 = (count >= 1);
    assign pop_valid_1 = (count >= 2);

    wire [PTR_WIDTH-1:0] raddr0 = rptr[PTR_WIDTH-1:0];
    wire [PTR_WIDTH:0] rptr_plus_1 = rptr + 1;
    wire [PTR_WIDTH-1:0] raddr1 = rptr_plus_1[PTR_WIDTH-1:0];

    assign pop_pc_0           = queue_pc[raddr0];
    assign pop_inst_0         = queue_inst[raddr0];
    assign pop_pred_taken_0   = queue_pred_taken[raddr0];
    assign pop_pred_target_0  = queue_pred_target[raddr0];

    assign pop_pc_1           = queue_pc[raddr1];
    assign pop_inst_1         = queue_inst[raddr1];
    assign pop_pred_taken_1   = queue_pred_taken[raddr1];
    assign pop_pred_target_1  = queue_pred_target[raddr1];

    always_ff @(posedge clk) begin
        if (rst || flush) begin
            rptr <= 0;
            wptr <= 0;
        end else begin
            // 处理读出
            if (pop_ready) begin
                if (pop_count == 2'd2 && count >= 2)
                    rptr <= rptr + 2;
                else if (pop_count >= 2'd1 && count >= 1)
                    rptr <= rptr + 1;
            end

            // 处理写入
            if (!almost_full) begin
                if (push_valid_0 && push_valid_1) begin
                    queue_pc[wptr[PTR_WIDTH-1:0]]           <= push_pc_0;
                    queue_inst[wptr[PTR_WIDTH-1:0]]         <= push_inst_0;
                    queue_pred_taken[wptr[PTR_WIDTH-1:0]]   <= push_pred_taken_0;
                    queue_pred_target[wptr[PTR_WIDTH-1:0]]  <= push_pred_target_0;
                    queue_pc[(wptr+1) % DEPTH]              <= push_pc_1;
                    queue_inst[(wptr+1) % DEPTH]            <= push_inst_1;
                    queue_pred_taken[(wptr+1) % DEPTH]      <= push_pred_taken_1;
                    queue_pred_target[(wptr+1) % DEPTH]     <= push_pred_target_1;
                    wptr <= wptr + 2;
                end else if (push_valid_0) begin
                    queue_pc[wptr[PTR_WIDTH-1:0]]           <= push_pc_0;
                    queue_inst[wptr[PTR_WIDTH-1:0]]         <= push_inst_0;
                    queue_pred_taken[wptr[PTR_WIDTH-1:0]]   <= push_pred_taken_0;
                    queue_pred_target[wptr[PTR_WIDTH-1:0]]  <= push_pred_target_0;
                    wptr <= wptr + 1;
                end
            end
        end
    end
endmodule
