// Simple reset synchronizer for simulation
module AsyncResetReg(input d, input clk, input en, output q);
  reg q_reg;
  always @(posedge clk) q_reg <= d;
  assign q = q_reg;
endmodule
