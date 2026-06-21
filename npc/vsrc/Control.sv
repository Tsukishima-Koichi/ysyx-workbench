`timescale 1ns / 1ps
`include "defines.sv"

module Control(
    input  logic [31:0] inst,
    output logic        IsBranch,
    output logic [1:0]  JmpType,
    output logic        RegWen,
    output logic        MemWen,
    output logic [1:0]  WbSel,
    output logic [1:0]  AluSrcA, 
    output logic        AluSrcB,
    output logic        CsrWen,
    output logic [1:0]  CsrOp,
    output logic        CsrImmSel,
    output logic        IsEcall,
    output logic        IsEbreak,
    output logic        IsMret
);
    logic [6:0] opcode;
    logic [2:0] funct3;
    logic [11:0] funct12;

    assign opcode  = inst[6:0];
    assign funct3  = inst[14:12];
    assign funct12 = inst[31:20];

    wire is_R    = (opcode === `R_TYPE);
    wire is_I    = (opcode === `I_TYPE);
    wire is_L    = (opcode === `IL_TYPE);
    wire is_S    = (opcode === `S_TYPE);
    wire is_B    = (opcode === `B_TYPE);
    wire is_U    = (opcode === `U_TYPE);
    wire is_UA   = (opcode === `UA_TYPE);
    wire is_J    = (opcode === `J_TYPE);
    wire is_IJ   = (opcode === `IJ_TYPE);
    wire is_CSR  = (opcode === `CSR_TYPE);

    wire is_sys_call   = is_CSR & (funct3 === 3'b000) & (funct12 === 12'h000);
    wire is_sys_break  = is_CSR & (funct3 === 3'b000) & (funct12 === 12'h001);
    wire is_sys_mret   = is_CSR & (funct3 === 3'b000) & (funct12 === 12'h302);
    wire is_csr_rw     = is_CSR & (funct3 !== 3'b000);

    assign IsBranch = is_B;
    assign MemWen   = is_S;
    assign RegWen   = is_R | is_I | is_L | is_U | is_UA | is_J | is_IJ | is_csr_rw;
    
    assign JmpType[1] = is_IJ | is_sys_call | is_sys_break | is_sys_mret;
    assign JmpType[0] = is_J  | is_sys_call | is_sys_break | is_sys_mret;

    assign WbSel[1] = is_L | is_csr_rw;
    assign WbSel[0] = is_J | is_IJ | is_csr_rw;

    assign AluSrcA[1] = is_U;
    assign AluSrcA[0] = is_UA;

    assign AluSrcB = is_I | is_L | is_S | is_U | is_UA;

    assign CsrWen    = is_csr_rw;
    assign CsrImmSel = funct3[2];
    assign CsrOp[1]  = (funct3[1:0] == 2'b11);
    assign CsrOp[0]  = (funct3[1:0] == 2'b10); 
    
    assign IsEcall   = is_sys_call;
    assign IsEbreak  = is_sys_break;
    assign IsMret    = is_sys_mret;

endmodule
