`timescale 1ns / 1ps

module CSR #(
    parameter DATAWIDTH = 32
)(
    input  logic                 clk,
    input  logic                 rst,
    input  logic [DATAWIDTH-1:0] pc,
    input  logic [11:0]          csr_idx, 
    input  logic [DATAWIDTH-1:0] wdata,   
    input  logic [1:0]           csr_op,  
    input  logic                 csr_wen,
    input  logic                 ecall,
    input  logic                 ebreak,
    input  logic                 mret,

    output logic [DATAWIDTH-1:0] rdata,   
    output logic [DATAWIDTH-1:0] trap_pc  
);
    logic [31:0] mstatus = 32'h1800;
    logic [31:0] mtvec   = 32'h0;
    logic [31:0] mepc    = 32'h0;
    logic [31:0] mcause  = 32'h0;
    logic [31:0] mscratch= 32'h0;

    always_comb begin
        case(csr_idx)
            12'h300: rdata = mstatus;
            12'h305: rdata = mtvec;
            12'h340: rdata = mscratch; 
            12'h341: rdata = mepc;
            12'h342: rdata = mcause;
            default: rdata = 32'b0;
        endcase
    end

    assign trap_pc = (ecall || ebreak) ? mtvec : (mret ? mepc : 32'b0);

    logic [31:0] next_csr_val;
    always_comb begin
        case(csr_op)
            2'b00: next_csr_val = wdata;                 // RW
            2'b01: next_csr_val = rdata | wdata;         // RS
            2'b10: next_csr_val = rdata & ~wdata;        // RC
            default: next_csr_val = wdata;
        endcase
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            mstatus <= 32'h1800;
        end else begin
            if (ecall) begin
                mepc    <= pc;
                mcause  <= 32'h0000_000B;
                mstatus <= {mstatus[31:13], 2'b11, mstatus[10:8], mstatus[3], mstatus[6:4], 1'b0, mstatus[2:0]};
            end
            else if (ebreak) begin
                mepc    <= pc;
                mcause  <= 32'h0000_0003;      
                mstatus <= {mstatus[31:13], 2'b11, mstatus[10:8], mstatus[3], mstatus[6:4], 1'b0, mstatus[2:0]};
            end
            else if (mret) begin
                mstatus <= {mstatus[31:13], 2'b00, mstatus[10:8], 1'b1, mstatus[6:4], mstatus[7], mstatus[2:0]};
            end
            else if (csr_wen) begin
                case(csr_idx)
                    12'h300: mstatus <= next_csr_val;
                    12'h305: mtvec   <= next_csr_val;
                    12'h340: mscratch <= next_csr_val;
                    12'h341: mepc    <= next_csr_val;
                    12'h342: mcause  <= next_csr_val;
                    default: ;
                endcase
            end
        end
    end
endmodule
