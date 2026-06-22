`timescale 1ns / 1ps

module BranchPredictor #(
    parameter PC_WIDTH = 32,
    parameter INDEX_BITS = 10 
)(
    input  logic                clk,
    
    input  logic [PC_WIDTH-1:0] if1_pc,
    input  logic [PC_WIDTH-1:0] if2_pc, 
    
    output logic                if2_pred_taken,
    output logic [PC_WIDTH-1:0] if2_pred_target,
    
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

    logic [PC_WIDTH-INDEX_BITS-3:0] btb_tag    [TABLE_SIZE-1:0];
    logic [PC_WIDTH-1:0]            btb_target [TABLE_SIZE-1:0];
    logic                           btb_valid  [TABLE_SIZE-1:0];
    logic [1:0]                     bht_counter [TABLE_SIZE-1:0];

    logic [PC_WIDTH-INDEX_BITS-3:0] read_tag;
    logic [PC_WIDTH-1:0]            read_target;
    logic                           read_valid;
    logic [1:0]                     read_bht;

    initial begin
        for (int i = 0; i < TABLE_SIZE; i++) begin
            btb_tag[i]     = '0;
            btb_target[i]  = '0;
            btb_valid[i]   = 1'b0;
            bht_counter[i] = 2'b00;
        end
    end

    // 同步读取，推断 BRAM 硬核
    always_ff @(posedge clk) begin
        read_tag    <= btb_tag[if1_idx];
        read_target <= btb_target[if1_idx];
        read_valid  <= btb_valid[if1_idx];
        read_bht    <= bht_counter[if1_idx];
    end

    wire tag_match = (read_valid === 1'b1) && (read_tag === if2_tag);
    assign if2_pred_taken  = tag_match && (read_bht[1] === 1'b1);
    assign if2_pred_target = tag_match ? read_target : '0;

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
