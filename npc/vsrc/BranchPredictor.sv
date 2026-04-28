`timescale 1ns / 1ps

module BranchPredictor #(
    parameter PC_WIDTH = 32,
    parameter INDEX_BITS = 10 // 升级到 1024 项表！BRAM 毫无压力
)(
    input  logic                clk,
    
    // --- IF1 阶段发送查询地址 ---
    input  logic [PC_WIDTH-1:0] if1_pc,
    
    // --- IF2 阶段接收预测结果 ---
    input  logic [PC_WIDTH-1:0] if2_pc, // IF2_PC 用于校验 Tag
    output logic                if2_pred_taken,
    output logic [PC_WIDTH-1:0] if2_pred_target,
    
    // --- EX 阶段更新端口 ---
    input  logic                ex_is_branch,
    input  logic [PC_WIDTH-1:0] ex_pc,
    input  logic                ex_actual_taken,
    input  logic [PC_WIDTH-1:0] ex_actual_target
);
    localparam TABLE_SIZE = 1 << INDEX_BITS;
    wire [INDEX_BITS-1:0]         if1_idx = if1_pc[INDEX_BITS+1 : 2];
    wire [PC_WIDTH-INDEX_BITS-3:0] if2_tag = if2_pc[PC_WIDTH-1 : INDEX_BITS+2];
    
    wire [INDEX_BITS-1:0]         ex_idx = ex_pc[INDEX_BITS+1 : 2];
    wire [PC_WIDTH-INDEX_BITS-3:0] ex_tag = ex_pc[PC_WIDTH-1 : INDEX_BITS+2];

    // BRAM 数组
    logic [PC_WIDTH-INDEX_BITS-3:0] btb_tag    [TABLE_SIZE-1:0];
    logic [PC_WIDTH-1:0]            btb_target [TABLE_SIZE-1:0];
    logic                           btb_valid  [TABLE_SIZE-1:0];
    logic [1:0]                     bht_counter [TABLE_SIZE-1:0];

    // 同步读取的寄存器 (BRAM 输出锁存)
    logic [PC_WIDTH-INDEX_BITS-3:0] read_tag;
    logic [PC_WIDTH-1:0]            read_target;
    logic                           read_valid;
    logic [1:0]                     read_bht;

    // ----------------------------------------
    // 🌟 新增：利用 initial 块进行 BRAM 数组上电初始化
    // 这在 FPGA 综合和 Verilator 仿真中都是合法且推荐的
    // ----------------------------------------
    initial begin
        for (int i = 0; i < TABLE_SIZE; i++) begin
            btb_valid[i]   = 1'b0;
            bht_counter[i] = 2'b00;
        end
    end

    // ----------------------------------------
    // 1. 同步读取机制 (推断 BRAM 的关键)
    // ----------------------------------------
    always_ff @(posedge clk) begin
        // 注意：这里绝对不能加 if(rst) 清零，否则 BRAM 推断失败！
        read_tag    <= btb_tag[if1_idx];
        read_target <= btb_target[if1_idx];
        read_valid  <= btb_valid[if1_idx];
        read_bht    <= bht_counter[if1_idx];
    end

    // ----------------------------------------
    // 2. IF2 阶段组合逻辑比对
    // ----------------------------------------
    // 使用 === 1'b1 阻断仿真初期从 BRAM 读出的 X 态！
    wire tag_match = (read_valid === 1'b1) && (read_tag === if2_tag);
    assign if2_pred_taken  = tag_match && (read_bht[1] === 1'b1);
    assign if2_pred_target = read_target;

    // ----------------------------------------
    // 3. EX 阶段更新逻辑
    // ----------------------------------------
    always_ff @(posedge clk) begin
        if (ex_is_branch) begin
            btb_valid[ex_idx]  <= 1'b1;
            btb_tag[ex_idx]    <= ex_tag;
            btb_target[ex_idx] <= ex_actual_target;
            
            if (!btb_valid[ex_idx] || btb_tag[ex_idx] != ex_tag) begin
                bht_counter[ex_idx] <= ex_actual_taken ? 2'b10 : 2'b01;
            end else begin
                case (bht_counter[ex_idx])
                    2'b00: bht_counter[ex_idx] <= ex_actual_taken ? 2'b01 : 2'b00;
                    2'b01: bht_counter[ex_idx] <= ex_actual_taken ? 2'b10 : 2'b00;
                    2'b10: bht_counter[ex_idx] <= ex_actual_taken ? 2'b11 : 2'b01;
                    2'b11: bht_counter[ex_idx] <= ex_actual_taken ? 2'b11 : 2'b10;
                endcase
            end
        end
    end
endmodule
