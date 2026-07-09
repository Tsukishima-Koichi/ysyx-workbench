// Simple pass-through for simulation (no pad-level modeling)
module GenericDigitalInIOCell(input pad, input ie, output i);
  assign i = pad;
endmodule
