`timescale 1ns / 1ps
`include "defines.sv"

module Control(
    input  logic [31:0] inst        , // 规范：instr -> inst (指令)
    
    // 控制流 (Control Flow)
    output logic        IsBranch    , // 规范：Branch -> IsBranch
    output logic [1:0]  JmpType     , // 规范：Jump -> JmpType (00:None, 01:JAL, 10:JALR, 11:Trap)
    
    // 寄存器与访存使能 (Enables)
    output logic        RegWen      , // 规范：RegWrite -> RegWen
    output logic        MemWen      , // 规范：MemWrite -> MemWen
    
    // 写回选择器 (Write-Back Select)
    output logic [1:0]  WbSel       , // 规范：MemToReg -> WbSel (00:ALU, 01:PC+4, 10:Mem, 11:CSR)
    
    // ALU 数据源选择器 (ALU Source Select)
    output logic [1:0]  AluSrcA     , 
    output logic        AluSrcB     ,

    // CSR 与 异常特权控制 (CSR & Trap)
    output logic        CsrWen      , // 规范：CSR_Wen -> CsrWen
    output logic [1:0]  CsrOp       , // 规范：CSR_Op -> CsrOp
    output logic        CsrImmSel   , // 规范：CSR_Imm -> CsrImmSel
    output logic        IsEcall     ,
    output logic        IsEbreak    ,
    output logic        IsMret
);
    logic [6:0]  opcode;
    logic [2:0]  funct3;
    logic [11:0] funct12;

    assign opcode  = inst[6:0];
    assign funct3  = inst[14:12];
    assign funct12 = inst[31:20];

    always_comb begin
        // 🌟 强迫症级别的安全默认值
        IsBranch = 0; JmpType = 2'b00; RegWen = 0; MemWen = 0;
        WbSel = 2'b00; AluSrcA = 2'b00; AluSrcB = 0;
        CsrWen = 0; CsrOp = 2'b00; CsrImmSel = 0;
        IsEcall = 0; IsEbreak = 0; IsMret = 0;
        
        case(opcode)
            `U_TYPE:   begin RegWen = 1; AluSrcA = 2'b10; AluSrcB = 1; end
            `UA_TYPE:  begin RegWen = 1; AluSrcA = 2'b01; AluSrcB = 1; end
            `J_TYPE:   begin JmpType = 2'b01; RegWen = 1; WbSel = 2'b01; end
            `IJ_TYPE:  begin JmpType = 2'b10; RegWen = 1; WbSel = 2'b01; end
            `B_TYPE:   begin IsBranch = 1; end
            `IL_TYPE:  begin RegWen = 1; WbSel = 2'b10; AluSrcB = 1; end
            `S_TYPE:   begin MemWen = 1; AluSrcB = 1; end
            `R_TYPE:   begin RegWen = 1; AluSrcA = 2'b00; AluSrcB = 0; end
            `I_TYPE:   begin RegWen = 1; AluSrcA = 2'b00; AluSrcB = 1; end
            
            `MISC_MEM: begin /* FENCE 等指令视作 NOP */ end

            `CSR_TYPE: begin 
                if (funct3 == 3'b000) begin
                    if      (funct12 == 12'h000) begin IsEcall  = 1; JmpType = 2'b11; end
                    else if (funct12 == 12'h001) begin IsEbreak = 1; JmpType = 2'b11; end
                    else if (funct12 == 12'h302) begin IsMret   = 1; JmpType = 2'b11; end
                end else begin
                    RegWen = 1;
                    WbSel  = 2'b11; // 11 代表写回数据来自 CSR
                    CsrWen = 1;
                    CsrImmSel = funct3[2]; 
                    CsrOp  = (funct3[1:0] == 2'b01) ? 2'b00 :
                             (funct3[1:0] == 2'b10) ? 2'b01 : 2'b10;
                end
            end
            default: ;
        endcase
    end
endmodule
