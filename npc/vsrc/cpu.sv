// vsrc/cpu.sv
`timescale 1ns / 1ps
`include "defines.sv"

import "DPI-C" context function int pmem_read(input int raddr);
import "DPI-C" context function void pmem_write(input int waddr, input int wdata, input byte wmask);

module cpu(
    input logic clk,
    input logic rst,

    output logic [31:0] pc,
    output logic [31:0] inst,
    output logic        halt_req,
    output logic        dead_loop,
    output logic [31:0] halt_pc,     

    output logic        commit_valid, 
    output logic [31:0] commit_pc
);
    logic [31:0] irom_addr;
    logic [63:0] irom_data; // 升级为 64-bit 双字数据总线
    
    logic [31:0] perip_addr;
    logic        perip_wen;
    logic [ 3:0] perip_mask;
    logic [31:0] perip_wdata;
    logic [31:0] perip_rdata;

    myCPU u_myCPU (
        .cpu_rst      (rst),
        .cpu_clk      (clk),
        .irom_addr    (irom_addr),
        .irom_data    (irom_data), // 接入 64-bit
        .perip_addr   (perip_addr),
        .perip_wen    (perip_wen),
        .perip_mask   (perip_mask),
        .perip_wdata  (perip_wdata),
        .perip_rdata  (perip_rdata)
    );

    logic [31:0] irom_addr_reg;
    logic [31:0] perip_addr_reg;

    always_ff @(posedge clk) begin
        if (rst) begin
            irom_addr_reg  <= 32'h8000_0000;
            perip_addr_reg <= 32'h0000_0000;
        end else begin
            irom_addr_reg  <= irom_addr;
            perip_addr_reg <= perip_addr;
        end
    end

    always_comb begin
        // 单周期调用两次 DPI-C 接口，模拟 64-bit 取指带宽以喂饱 F-Block
        irom_data = {pmem_read(irom_addr + 4), pmem_read(irom_addr)};
        perip_rdata = pmem_read(perip_addr_reg);
    end

    always_ff @(posedge clk) begin
        if (!rst && perip_wen)
            pmem_write(perip_addr, perip_wdata, {4'b0, perip_mask});
    end
    
    assign pc       = u_myCPU.ex1_pc;
    assign inst     = u_myCPU.id_inst;     
    assign halt_req = u_myCPU.ex1_IsEbreak;
    
    // Require dead_loop_raw to persist 2 cycles. This prevents false positives
    // when a JAL in the same 64-bit fetch pair is at BR while the paired
    // dead-loop instruction (j .) briefly appears at EX1 before being flushed.
    logic dead_loop_raw;
    logic dead_loop_r;
    assign dead_loop_raw = u_myCPU.ex1_valid &&
                           (u_myCPU.ex1_JmpType == 2'b01) &&
                           (u_myCPU.ex1_branch_target == u_myCPU.ex1_pc);
    logic [31:0] halt_pc_r;
    always_ff @(posedge clk) begin
        if (rst) begin
            dead_loop_r <= 1'b0;
            halt_pc_r   <= 32'b0;
        end else begin
            dead_loop_r <= dead_loop_raw;
            halt_pc_r   <= u_myCPU.ex1_pc;
        end
    end
    // Fire only when raw signal persists for TWO cycles (after flush would have settled)
    assign dead_loop = dead_loop_raw && dead_loop_r;
    assign halt_pc   = halt_pc_r;

    assign commit_valid = u_myCPU.wb_valid;
    assign commit_pc    = u_myCPU.wb_pc;
endmodule
