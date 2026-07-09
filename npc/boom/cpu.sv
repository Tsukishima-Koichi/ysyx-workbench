// vsrc/cpu.sv — BOOM RV32IMAFC wrapper with DPI-C memory bridge
`timescale 1ns / 1ps

import "DPI-C" context function int pmem_read(input int raddr);
import "DPI-C" context function void pmem_write(input int waddr, input int wdata, input byte wmask);

module cpu(
    input  logic        clk,
    input  logic        rst,

    output logic [31:0] pc,
    output logic [31:0] inst,
    output logic        halt_req,
    output logic        dead_loop,
    output logic [31:0] halt_pc,

    output logic        commit_valid,
    output logic [31:0] commit_pc,
    output logic        commit_valid_1,
    output logic [31:0] commit_pc_1
);
    // =========================================================================
    // ChipTop clock/reset
    // =========================================================================
    logic chiptop_reset;
    assign chiptop_reset = rst;

    // =========================================================================
    // AXI4 Memory Bridge signals
    // =========================================================================
    logic        axi_aw_ready, axi_aw_valid;
    logic [3:0]  axi_aw_id;
    logic [31:0] axi_aw_addr;
    logic [7:0]  axi_aw_len;
    logic [2:0]  axi_aw_size;
    logic [1:0]  axi_aw_burst;
    logic        axi_aw_lock;
    logic [3:0]  axi_aw_cache;
    logic [2:0]  axi_aw_prot;
    logic [3:0]  axi_aw_qos;

    logic        axi_w_ready, axi_w_valid;
    logic [63:0] axi_w_data;
    logic [7:0]  axi_w_strb;
    logic        axi_w_last;

    logic        axi_b_ready, axi_b_valid;
    logic [3:0]  axi_b_id;
    logic [1:0]  axi_b_resp;

    logic        axi_ar_ready, axi_ar_valid;
    logic [3:0]  axi_ar_id;
    logic [31:0] axi_ar_addr;
    logic [7:0]  axi_ar_len;
    logic [2:0]  axi_ar_size;
    logic [1:0]  axi_ar_burst;
    logic        axi_ar_lock;
    logic [3:0]  axi_ar_cache;
    logic [2:0]  axi_ar_prot;
    logic [3:0]  axi_ar_qos;

    logic        axi_r_ready, axi_r_valid;
    logic [3:0]  axi_r_id;
    logic [63:0] axi_r_data;
    logic [1:0]  axi_r_resp;
    logic        axi_r_last;

    // =========================================================================
    // AXI4 → DPI-C Bridge (single-cycle, no burst)
    // =========================================================================
    // Read path: AR → pmem_read → R (1 cycle latency)
    logic [31:0] ar_addr_reg;
    logic        ar_pending;

    always_ff @(posedge clk) begin
        if (rst) begin
            ar_pending <= 1'b0;
            ar_addr_reg <= 32'b0;
        end else begin
            if (axi_ar_valid && axi_ar_ready) begin
                ar_pending <= 1'b1;
                ar_addr_reg <= axi_ar_addr;
            end else if (axi_r_valid && axi_r_ready) begin
                ar_pending <= 1'b0;
            end
        end
    end

    // Always ready to accept read requests
    assign axi_ar_ready = !ar_pending || (axi_r_valid && axi_r_ready);

    // Read response (1 cycle after AR)
    logic [63:0] pmem_rdata_lo, pmem_rdata_hi;
    assign pmem_rdata_lo = {32'b0, pmem_read({ar_addr_reg[31:3], 3'b000})};
    assign pmem_rdata_hi = {32'b0, pmem_read({ar_addr_reg[31:3], 3'b100})};

    assign axi_r_valid = ar_pending;
    assign axi_r_data  = (ar_addr_reg[2]) ? {pmem_rdata_hi[31:0], pmem_rdata_lo[31:0]} :
                                             {pmem_rdata_lo[31:0], pmem_rdata_hi[31:0]};
    assign axi_r_id    = 4'b0;
    assign axi_r_resp  = 2'b00;  // OKAY
    assign axi_r_last  = 1'b1;   // single beat

    // Write path: AW+W → pmem_write → B (same cycle)
    assign axi_aw_ready = 1'b1;
    assign axi_w_ready  = 1'b1;

    // Write response (same cycle)
    logic wr_pending;
    always_ff @(posedge clk) begin
        if (rst) wr_pending <= 1'b0;
        else if (axi_aw_valid && axi_aw_ready) wr_pending <= 1'b1;
        else if (axi_b_valid && axi_b_ready)   wr_pending <= 1'b0;
    end

    assign axi_b_valid = wr_pending;
    assign axi_b_id    = 4'b0;
    assign axi_b_resp  = 2'b00;
    assign axi_b_ready = 1'b1;

    // Actual write
    always_ff @(posedge clk) begin
        if (!rst && axi_w_valid && axi_w_ready) begin
            if (axi_w_strb[0]) pmem_write({axi_aw_addr[31:3], 3'b000}, axi_w_data[7:0],   8'h01);
            if (axi_w_strb[1]) pmem_write({axi_aw_addr[31:3], 3'b001}, axi_w_data[15:8],  8'h02);
            if (axi_w_strb[2]) pmem_write({axi_aw_addr[31:3], 3'b010}, axi_w_data[23:16], 8'h04);
            if (axi_w_strb[3]) pmem_write({axi_aw_addr[31:3], 3'b011}, axi_w_data[31:24], 8'h08);
            if (axi_w_strb[4]) pmem_write({axi_aw_addr[31:3], 3'b100}, axi_w_data[39:32], 8'h10);
            if (axi_w_strb[5]) pmem_write({axi_aw_addr[31:3], 3'b101}, axi_w_data[47:40], 8'h20);
            if (axi_w_strb[6]) pmem_write({axi_aw_addr[31:3], 3'b110}, axi_w_data[55:48], 8'h40);
            if (axi_w_strb[7]) pmem_write({axi_aw_addr[31:3], 3'b111}, axi_w_data[63:56], 8'h80);
        end
    end

    // =========================================================================
    // ChipTop Instantiation
    // =========================================================================
    logic        uart_txd, uart_rxd;
    logic        jtag_TCK, jtag_TMS, jtag_TDI, jtag_TDO;
    logic        serial_tl_in_ready, serial_tl_in_valid;
    logic [31:0] serial_tl_in_bits;
    logic        serial_tl_out_ready, serial_tl_out_valid;
    logic [31:0] serial_tl_out_bits;
    logic        clock_tap, axi_clock;

    assign uart_rxd = 1'b1;          // UART RX idle high
    assign jtag_TCK = 1'b0;
    assign jtag_TMS = 1'b0;
    assign jtag_TDI = 1'b0;
    assign serial_tl_in_valid = 1'b0;
    assign serial_tl_in_bits  = 32'b0;
    assign serial_tl_out_ready = 1'b1;

    ChipTop u_chiptop (
        .clock_uncore                   (clk),
        .reset_io                       (chiptop_reset),
        .jtag_reset                     (chiptop_reset),
        .custom_boot                    (1'b0),
        .clock_tap                      (clock_tap),
        .serial_tl_0_clock_in           (clk),
        .serial_tl_0_in_ready           (serial_tl_in_ready),
        .serial_tl_0_in_valid           (serial_tl_in_valid),
        .serial_tl_0_in_bits_phit       (serial_tl_in_bits),
        .serial_tl_0_out_ready          (serial_tl_out_ready),
        .serial_tl_0_out_valid          (serial_tl_out_valid),
        .serial_tl_0_out_bits_phit      (serial_tl_out_bits),
        .uart_0_txd                     (uart_txd),
        .uart_0_rxd                     (uart_rxd),
        .jtag_TCK                       (jtag_TCK),
        .jtag_TMS                       (jtag_TMS),
        .jtag_TDI                       (jtag_TDI),
        .jtag_TDO                       (jtag_TDO),
        // AXI4 Memory
        .axi4_mem_0_clock               (axi_clock),
        .axi4_mem_0_bits_aw_ready       (axi_aw_ready),
        .axi4_mem_0_bits_aw_valid       (axi_aw_valid),
        .axi4_mem_0_bits_aw_bits_id     (axi_aw_id),
        .axi4_mem_0_bits_aw_bits_addr   (axi_aw_addr),
        .axi4_mem_0_bits_aw_bits_len    (axi_aw_len),
        .axi4_mem_0_bits_aw_bits_size   (axi_aw_size),
        .axi4_mem_0_bits_aw_bits_burst  (axi_aw_burst),
        .axi4_mem_0_bits_aw_bits_lock   (axi_aw_lock),
        .axi4_mem_0_bits_aw_bits_cache  (axi_aw_cache),
        .axi4_mem_0_bits_aw_bits_prot   (axi_aw_prot),
        .axi4_mem_0_bits_aw_bits_qos    (axi_aw_qos),
        .axi4_mem_0_bits_w_ready        (axi_w_ready),
        .axi4_mem_0_bits_w_valid        (axi_w_valid),
        .axi4_mem_0_bits_w_bits_data    (axi_w_data),
        .axi4_mem_0_bits_w_bits_strb    (axi_w_strb),
        .axi4_mem_0_bits_w_bits_last    (axi_w_last),
        .axi4_mem_0_bits_b_ready        (axi_b_ready),
        .axi4_mem_0_bits_b_valid        (axi_b_valid),
        .axi4_mem_0_bits_b_bits_id      (axi_b_id),
        .axi4_mem_0_bits_b_bits_resp    (axi_b_resp),
        .axi4_mem_0_bits_ar_ready       (axi_ar_ready),
        .axi4_mem_0_bits_ar_valid       (axi_ar_valid),
        .axi4_mem_0_bits_ar_bits_id     (axi_ar_id),
        .axi4_mem_0_bits_ar_bits_addr   (axi_ar_addr),
        .axi4_mem_0_bits_ar_bits_len    (axi_ar_len),
        .axi4_mem_0_bits_ar_bits_size   (axi_ar_size),
        .axi4_mem_0_bits_ar_bits_burst  (axi_ar_burst),
        .axi4_mem_0_bits_ar_bits_lock   (axi_ar_lock),
        .axi4_mem_0_bits_ar_bits_cache  (axi_ar_cache),
        .axi4_mem_0_bits_ar_bits_prot   (axi_ar_prot),
        .axi4_mem_0_bits_ar_bits_qos    (axi_ar_qos),
        .axi4_mem_0_bits_r_ready        (axi_r_ready),
        .axi4_mem_0_bits_r_valid        (axi_r_valid),
        .axi4_mem_0_bits_r_bits_id      (axi_r_id),
        .axi4_mem_0_bits_r_bits_data    (axi_r_data),
        .axi4_mem_0_bits_r_bits_resp    (axi_r_resp),
        .axi4_mem_0_bits_r_bits_last    (axi_r_last)
    );

    // =========================================================================
    // Monitor signals (best-effort for now)
    // =========================================================================
    assign pc   = 32'h8000_0000;  // TODO: probe BoomFrontend PC
    assign inst = 32'h0000_0013;  // TODO: probe instruction
    assign halt_req  = 1'b0;      // TODO: detect ebreak via debug module
    assign dead_loop = 1'b0;      // TODO: detect infinite loop
    assign halt_pc   = 32'b0;

    assign commit_valid   = 1'b0;  // TODO: trace commits from ROB
    assign commit_pc      = 32'b0;
    assign commit_valid_1 = 1'b0;
    assign commit_pc_1    = 32'b0;

    // =========================================================================
    // Stub DPI exports (required by main.cpp / difftest.cpp linkage)
    // =========================================================================
    export "DPI-C" function perf_get_counters;
    function void perf_get_counters(
        output int commits, output int branches, output int mispredicts,
        output int early_f, output int micro_f, output int br_f,
        output int stall_f, output int stall_b, output int dual_issues
    );
        commits = 0; branches = 0; mispredicts = 0;
        early_f = 0; micro_f = 0; br_f = 0;
        stall_f = 0; stall_b = 0; dual_issues = 0;
    endfunction

    export "DPI-C" function get_gpr;
    function int get_gpr(input int idx);
        return 0;
    endfunction

    export "DPI-C" function get_csr;
    function int get_csr(input int idx);
        return 0;
    endfunction

    import "DPI-C" function void set_regfile_scope();
    import "DPI-C" function void set_csr_scope();
    initial begin
        set_regfile_scope();
        set_csr_scope();
    end

endmodule
