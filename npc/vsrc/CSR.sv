`timescale 1ns / 1ps

module CSR #(
    parameter DATAWIDTH = 32
)(
    input  logic                 clk,
    input  logic                 rst,
    input  logic [DATAWIDTH-1:0] pc,
    input  logic [11:0]          csr_idx, // 从指令 31:20 提取
    input  logic [DATAWIDTH-1:0] wdata,   // rs1 或 zimm 数据
    input  logic [1:0]           csr_op,  // 00: RW, 01: RS, 10: RC
    input  logic                 csr_wen,
    input  logic                 ecall,
    input  logic                 ebreak,
    input  logic                 mret,

    output logic [DATAWIDTH-1:0] rdata,   // 给通用寄存器写回的旧数据
    output logic [DATAWIDTH-1:0] trap_pc  // 给 BranchUnit 的跳转地址
);
    // RISC-V M-Mode 最核心的四个状态寄存器
    logic [31:0] mstatus, mtvec, mepc, mcause;

    // ==========================================
    // 1. 读出 CSR 的老数据 (异步纯组合逻辑)
    // ==========================================
    always_comb begin
        case(csr_idx)
            12'h300: rdata = mstatus;
            12'h305: rdata = mtvec;
            12'h341: rdata = mepc;
            12'h342: rdata = mcause;
            default: rdata = 32'b0;
        endcase
    end

    // 路由异常发生时的跳转目标地址
    assign trap_pc = (ecall || ebreak) ? mtvec : (mret ? mepc : 32'b0);

    // ==========================================
    // 2. 计算要写入 CSR 的新数据 (处理 RW / RS / RC)
    // ==========================================
    logic [31:0] next_csr_val;
    always_comb begin
        case(csr_op)
            2'b00: next_csr_val = wdata;          // RW: 直接覆盖
            2'b01: next_csr_val = rdata | wdata;  // RS: 置位(或操作)
            2'b10: next_csr_val = rdata & ~wdata; // RC: 清零(反与操作)
            default: next_csr_val = wdata;
        endcase
    end

    // ==========================================
    // 3. 写入 CSR (时序逻辑)
    // ==========================================
    always_ff @(posedge clk) begin
        if (rst) begin
            mstatus <= 32'h1800; // 默认 M 模式开启
            mtvec   <= 32'h0;
            mepc    <= 32'h0;
            mcause  <= 32'h0;
        end else begin
            // 优先级 1: ecall 触发异常陷阱
            if (ecall) begin
                mepc    <= pc;                  // 保护断点现场
                mcause  <= 32'h0000_000B;       // 异常原因：来自 M 模式的 ecall
                // 禁用中断，压栈特权级
                mstatus <= {mstatus[31:13], 2'b11, mstatus[10:8], mstatus[3], mstatus[6:4], 1'b0, mstatus[2:0]};
            end
            // 优先级 2: ebreak 触发断点
            else if (ebreak) begin
                mepc    <= pc;
                mcause  <= 32'h0000_0003;       // 异常原因：Breakpoint
                mstatus <= {mstatus[31:13], 2'b11, mstatus[10:8], mstatus[3], mstatus[6:4], 1'b0, mstatus[2:0]};
            end
            // 优先级 3: mret 退出异常处理
            else if (mret) begin
                // 恢复中断使能和特权级
                mstatus <= {mstatus[31:13], 2'b11, mstatus[10:8], 1'b1, mstatus[6:4], mstatus[7], mstatus[2:0]};
            end
            // 优先级 4: 普通的软件 CSR 读写指令
            else if (csr_wen) begin
                case(csr_idx)
                    12'h300: mstatus <= next_csr_val;
                    12'h305: mtvec   <= next_csr_val;
                    12'h341: mepc    <= next_csr_val;
                    12'h342: mcause  <= next_csr_val;
                    default: ; // <--- 加上这行，兜底所有未定义的情况
                endcase
            end
        end
    end
endmodule
