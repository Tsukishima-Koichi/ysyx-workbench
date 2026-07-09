// Behavioral model for rob_debug_inst_mem (debug only, no function needed)
module rob_debug_inst_mem(
  input [4:0]  R0_addr,
  input        R0_en,
  input        R0_clk,
  input [4:0]  W0_addr,
  input        W0_en,
  input        W0_clk,
  input [31:0] W0_data
);
  // No read output port - this is write-only debug memory
  // Just implement writes for simulation completeness
  reg [31:0] mem [0:31];
  always @(posedge W0_clk) if (W0_en) mem[W0_addr] <= W0_data;
endmodule
