// vsrc/cpu.sv
`timescale 1ns / 1ps
`include "defines.sv"

import "DPI-C" context function int pmem_read(input int raddr);
import "DPI-C" context function void pmem_write(input int waddr, input int wdata, input byte wmask);

module cpu_dual(
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

    myCPU_Dual u_myCPU (
        .cpu_rst      (rst),
        .cpu_clk      (clk),
        .irom_addr    (irom_addr),
        .irom_data    (irom_data), // 接入 64-bit
        .perip_addr   (perip_addr),
        .perip_wen    (perip_wen),
        .perip_mask   (perip_mask),
        .perip_wdata  (perip_wdata),
        .perip_rdata  (perip_rdata),
        .br_valid_out (br_valid_out),
        .br_target_out(br_target_out)
    );
    logic br_valid_out;
    logic [31:0] br_target_out;

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
    
    // dead_loop: J-type self-loop at EX1.  Gate with BR stage to prevent
    // false positives when the paired instruction in the same 64-bit fetch
    // (e.g. jal at pc_0) is at BR and about to redirect the PC away.
    // If BR has a valid branch targeting a *different* address, the EX1
    // instruction will be flushed — suppress dead_loop.
    wire br_will_redirect_away = u_myCPU.br_valid_out &&
         (u_myCPU.br_target_out != u_myCPU.ex1_pc) &&
         (u_myCPU.br_target_out != 32'h0);  // BTB miss gives target=0
    assign dead_loop = u_myCPU.ex1_valid &&
                       (u_myCPU.ex1_JmpType == 2'b01) &&
                       (u_myCPU.ex1_branch_target == u_myCPU.ex1_pc) &&
                       ~br_will_redirect_away;
    assign halt_pc = u_myCPU.ex1_pc;

    assign commit_valid = u_myCPU.wb_valid;
    assign commit_pc    = u_myCPU.wb_pc;
endmodule
