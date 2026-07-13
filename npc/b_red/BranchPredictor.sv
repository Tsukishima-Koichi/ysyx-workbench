`timescale 1ns / 1ps

module BranchPredictor #(
    parameter PC_WIDTH = 32,
    parameter INDEX_BITS = 10 // 升级到 1024 项表！BRAM 毫无压力
)(
    input  logic                clk,
    input  logic                stall,
    
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

    // Pipeline predictor training to remove the long EX -> BHT write-data path.
    logic                           update_valid;
    (* MAX_FANOUT = 64 *) logic [INDEX_BITS-1:0] update_idx;
    logic [PC_WIDTH-INDEX_BITS-3:0] update_tag;
    logic                           update_taken;
    logic [PC_WIDTH-1:0]            update_target;
    logic                           update_old_valid;
    logic [PC_WIDTH-INDEX_BITS-3:0] update_old_tag;
    logic [1:0]                     update_old_bht;
    logic [1:0]                     update_next_bht;

    wire                            update_same_idx = update_valid && (ex_idx == update_idx);
    wire                            sample_old_valid = update_same_idx ? 1'b1 : btb_valid[ex_idx];
    wire [PC_WIDTH-INDEX_BITS-3:0]  sample_old_tag = update_same_idx ? update_tag : btb_tag[ex_idx];
    wire [1:0]                      sample_old_bht = update_same_idx ? update_next_bht : bht_counter[ex_idx];

    always_comb begin
        if (!update_old_valid || (update_old_tag != update_tag)) begin
            update_next_bht = update_taken ? 2'b10 : 2'b01;
        end else begin
            case (update_old_bht)
                2'b00: update_next_bht = update_taken ? 2'b01 : 2'b00;
                2'b01: update_next_bht = update_taken ? 2'b10 : 2'b00;
                2'b10: update_next_bht = update_taken ? 2'b11 : 2'b01;
                2'b11: update_next_bht = update_taken ? 2'b11 : 2'b10;
                default: update_next_bht = update_taken ? 2'b10 : 2'b01;
            endcase
        end
    end

    // ----------------------------------------
    // 🌟 新增：利用 initial 块进行 BRAM 数组上电初始化
    // 这在 FPGA 综合和 Verilator 仿真中都是合法且推荐的
    // ----------------------------------------
    initial begin
        update_valid     = 1'b0;
        update_idx       = '0;
        update_tag       = '0;
        update_taken     = 1'b0;
        update_target    = '0;
        update_old_valid = 1'b0;
        update_old_tag   = '0;
        update_old_bht   = 2'b00;
        for (int i = 0; i < TABLE_SIZE; i++) begin
            btb_valid[i]   = 1'b0;
            bht_counter[i] = 2'b00;
        end
    end

    // ----------------------------------------
    // 1. 同步读取机制 (推断 BRAM 的关键)
    // ----------------------------------------
    always_ff @(posedge clk) begin
        // Keep the predictor response aligned with a held IF2 pipeline entry.
        if (!stall) begin
            read_tag    <= btb_tag[if1_idx];
            read_target <= btb_target[if1_idx];
            read_valid  <= btb_valid[if1_idx];
            read_bht    <= bht_counter[if1_idx];
        end
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
    always @(posedge clk) begin
        update_valid     <= ex_is_branch;
        update_idx       <= ex_idx;
        update_tag       <= ex_tag;
        update_taken     <= ex_actual_taken;
        update_target    <= ex_actual_target;
        update_old_valid <= sample_old_valid;
        update_old_tag   <= sample_old_tag;
        update_old_bht   <= sample_old_bht;

        if (update_valid) begin
            btb_valid[update_idx]   <= 1'b1;
            btb_tag[update_idx]     <= update_tag;
            btb_target[update_idx]  <= update_target;
            bht_counter[update_idx] <= update_next_bht;
        end
    end
endmodule
