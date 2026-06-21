`timescale 1ns / 1ps

module InstructionQueue #(
    parameter DEPTH = 8,
    parameter DATAWIDTH = 32
)(
    input  logic clk,
    input  logic rst,
    input  logic flush,             // 来自后端的分支预测失败/异常冲刷

    // --- F-Block 写入端口 (双字并行写入) ---
    input  logic                 push_valid_0,
    input  logic [DATAWIDTH-1:0] push_pc_0,
    input  logic [DATAWIDTH-1:0] push_inst_0,
    input  logic                 push_pred_taken_0,
    input  logic [DATAWIDTH-1:0] push_pred_target_0,

    input  logic                 push_valid_1,
    input  logic [DATAWIDTH-1:0] push_pc_1,
    input  logic [DATAWIDTH-1:0] push_inst_1,
    input  logic                 push_pred_taken_1,
    input  logic [DATAWIDTH-1:0] push_pred_target_1,

    output logic                 almost_full, // 剩余空间小于2时反压前端

    // --- D-Block 读出端口 (单字顺序读出) ---
    input  logic                 pop_ready,   // ID阶段未被Stall时为1
    output logic                 pop_valid,
    output logic [DATAWIDTH-1:0] pop_pc,
    output logic [DATAWIDTH-1:0] pop_inst,
    output logic                 pop_pred_taken,
    output logic [DATAWIDTH-1:0] pop_pred_target
);

    localparam PTR_WIDTH = $clog2(DEPTH);
    
    // 队列存储体
    logic [DATAWIDTH-1:0] queue_pc          [DEPTH-1:0];
    logic [DATAWIDTH-1:0] queue_inst        [DEPTH-1:0];
    logic                 queue_pred_taken  [DEPTH-1:0];
    logic [DATAWIDTH-1:0] queue_pred_target [DEPTH-1:0];

    logic [PTR_WIDTH:0] rptr, wptr;
    logic [PTR_WIDTH:0] count;

    assign count = wptr - rptr;
    assign almost_full = (count >= (DEPTH - 2)); 
    
    assign pop_valid = (count != 0);
    wire [PTR_WIDTH-1:0] raddr = rptr[PTR_WIDTH-1:0];
    
    assign pop_pc          = queue_pc[raddr];
    assign pop_inst        = queue_inst[raddr];
    assign pop_pred_taken  = queue_pred_taken[raddr];
    assign pop_pred_target = queue_pred_target[raddr];

    logic [1:0] push_count;
    assign push_count = {1'b0, push_valid_0} + {1'b0, push_valid_1};

    always_ff @(posedge clk) begin
        if (rst || flush) begin
            rptr <= 0;
            wptr <= 0;
        end else begin
            // 处理读出
            if (pop_valid && pop_ready) begin
                rptr <= rptr + 1;
            end
            
            // 处理写入 (空间充足时)
            if (!almost_full) begin
                if (push_valid_0 && push_valid_1) begin
                    queue_pc[wptr[PTR_WIDTH-1:0]]          <= push_pc_0;
                    queue_inst[wptr[PTR_WIDTH-1:0]]        <= push_inst_0;
                    queue_pred_taken[wptr[PTR_WIDTH-1:0]]  <= push_pred_taken_0;
                    queue_pred_target[wptr[PTR_WIDTH-1:0]] <= push_pred_target_0;

                    queue_pc[(wptr+1) % DEPTH]          <= push_pc_1;
                    queue_inst[(wptr+1) % DEPTH]        <= push_inst_1;
                    queue_pred_taken[(wptr+1) % DEPTH]  <= push_pred_taken_1;
                    queue_pred_target[(wptr+1) % DEPTH] <= push_pred_target_1;
                    
                    wptr <= wptr + 2;
                end else if (push_valid_0) begin
                    queue_pc[wptr[PTR_WIDTH-1:0]]          <= push_pc_0;
                    queue_inst[wptr[PTR_WIDTH-1:0]]        <= push_inst_0;
                    queue_pred_taken[wptr[PTR_WIDTH-1:0]]  <= push_pred_taken_0;
                    queue_pred_target[wptr[PTR_WIDTH-1:0]] <= push_pred_target_0;
                    wptr <= wptr + 1;
                end
            end
        end
    end
endmodule
