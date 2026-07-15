// ============================================================================
// perf_counters.sv — NPC 性能计数器 (独立模块，与 myCPU.sv 解耦)
//
// 用法：在 myCPU.sv 中实例化，连接内部信号即可。
// 替换 myCPU.sv 时保留此文件和实例化代码。
// ============================================================================

module perf_counters (
    input  logic        clk,
    input  logic        rst,

    // ---- WB 阶段 ----
    input  logic        wb_valid,
    input  logic [1:0]  wb_WbSel,
    input  logic [2:0]  wb_funct3,
    input  logic [4:0]  wb_rd,
    input  logic        wb_RegWen,
    input  logic [31:0] wb_data,

    // ---- EX 前递 ----
    input  logic [1:0]  ex_forward_A,
    input  logic [1:0]  ex_forward_B,

    // ---- 停顿/冲刷 ----
    input  logic        load_use_flush_id_ex,
    input  logic        stall_req_mdu,
    input  logic        ex_mispredict,
    input  logic        redirect_flush,

    // ---- 预测取指空泡 ----
    input  logic        valid_if2_pred_taken,
    input  logic        stall_IF2,

    // ---- 内存访问 ----
    input  logic        mem1_MemWen,
    input  logic [31:0] mem1_agu_res
);

    logic [31:0] perf_cycles;
    logic [31:0] perf_retired;
    logic [31:0] perf_load_stall;
    logic [31:0] perf_mdu_stall;
    logic [31:0] perf_mispredict;
    logic [31:0] perf_redirect_flush;
    logic [31:0] perf_lw_count;
    logic [31:0] perf_lb_lh_count;
    logic [31:0] perf_load_use_hazard;
    logic [31:0] perf_wb_fwd_hits;
    logic [31:0] perf_min_sp;
    logic [31:0] perf_max_dram_addr;
    logic [31:0] perf_pred_taken_bubble;

    // 辅助线缆
    wire wb_is_load   = wb_valid && (wb_WbSel == 2'b10);
    wire wb_is_lw     = wb_is_load && (wb_funct3 == 3'b010);
    wire wb_is_lb_lh  = wb_is_load && (wb_funct3 != 3'b010);
    wire ex_use_wb_fwd_A = (ex_forward_A == 2'b01);
    wire ex_use_wb_fwd_B = (ex_forward_B == 2'b01);
    wire pred_taken_bubble = valid_if2_pred_taken & ~stall_IF2;

    always_ff @(posedge clk) begin
        if (rst) begin
            perf_cycles           <= 32'd0;
            perf_retired          <= 32'd0;
            perf_load_stall       <= 32'd0;
            perf_mdu_stall        <= 32'd0;
            perf_mispredict       <= 32'd0;
            perf_redirect_flush   <= 32'd0;
            perf_lw_count         <= 32'd0;
            perf_lb_lh_count      <= 32'd0;
            perf_load_use_hazard  <= 32'd0;
            perf_wb_fwd_hits      <= 32'd0;
            perf_min_sp           <= 32'hFFFF_FFFF;
            perf_max_dram_addr    <= 32'h8000_0000;
            perf_pred_taken_bubble <= 32'd0;
        end else begin
            perf_cycles <= perf_cycles + 32'd1;
            if (wb_valid)             perf_retired <= perf_retired + 32'd1;
            if (load_use_flush_id_ex) perf_load_stall <= perf_load_stall + 32'd1;
            if (stall_req_mdu)        perf_mdu_stall <= perf_mdu_stall + 32'd1;
            if (ex_mispredict)        perf_mispredict <= perf_mispredict + 32'd1;
            if (redirect_flush)       perf_redirect_flush <= perf_redirect_flush + 32'd1;
            if (wb_is_lw)             perf_lw_count <= perf_lw_count + 32'd1;
            if (wb_is_lb_lh)          perf_lb_lh_count <= perf_lb_lh_count + 32'd1;
            if (load_use_flush_id_ex) perf_load_use_hazard <= perf_load_use_hazard + 32'd1;
            if (ex_use_wb_fwd_A | ex_use_wb_fwd_B) perf_wb_fwd_hits <= perf_wb_fwd_hits + 32'd1;
            if (wb_RegWen && (wb_rd == 5'd2) && wb_data < perf_min_sp)
                perf_min_sp <= wb_data;
            if ((mem1_MemWen || (wb_WbSel == 2'b10)) && mem1_agu_res > perf_max_dram_addr)
                perf_max_dram_addr <= mem1_agu_res;
            if (pred_taken_bubble)    perf_pred_taken_bubble <= perf_pred_taken_bubble + 32'd1;
        end
    end

    export "DPI-C" function get_perf_counter;
    function int get_perf_counter(input int idx);
        case (idx)
            0:  return perf_cycles;
            1:  return perf_retired;
            2:  return perf_load_stall;
            3:  return perf_mdu_stall;
            4:  return perf_mispredict;
            5:  return perf_lw_count;
            6:  return perf_lb_lh_count;
            7:  return perf_load_use_hazard;
            8:  return perf_wb_fwd_hits;
            9:  return perf_min_sp;
            10: return perf_max_dram_addr;
            11: return perf_pred_taken_bubble;
            12: return perf_redirect_flush;
            default: return 0;
        endcase
    endfunction

endmodule
