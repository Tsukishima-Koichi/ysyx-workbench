module csr(
    input         clk,
    input         rst,
    
    // 1. 软件读写端口 (未来给 csrrw 等指令用)
    input  [11:0] csr_raddr,
    output reg [31:0] csr_rdata,
    input  [11:0] csr_waddr,
    input  [31:0] csr_wdata,
    input         csr_wen,

    // 2. 硬件陷阱控制端口 (给 ecall / mret 用)
    input         is_ecall,
    input  [31:0] current_pc, // 当前发生 ecall 的 PC
    
    // 3. 吐出数据给 NPC 模块，用来改变 PC 走向
    output [31:0] mtvec_out,  // ecall 跳去哪
    output [31:0] mepc_out    // mret 返回哪
);

    // 定义 4 个核心 CSR 寄存器
    reg [31:0] mstatus;
    reg [31:0] mtvec;
    reg [31:0] mepc;
    reg [31:0] mcause;

    // 持续暴露给外部跳转使用
    assign mtvec_out = mtvec;
    assign mepc_out  = mepc;

    // 写逻辑：硬件异常触发的优先级 最高！
    always @(posedge clk) begin
        if (rst) begin
            mstatus <= 32'h1800; // 默认 M 模式
            mtvec   <= 32'b0;
            mepc    <= 32'b0;
            mcause  <= 32'b0;
        end 
        else if (is_ecall) begin
            // 发生 ecall 时，硬件自动保护现场！
            mepc   <= current_pc;  // 记录案发现场
            mcause <= 32'd11;      // Environment call from M-mode 的代号是 11
        end 
        else if (csr_wen) begin
            // 软件指令(比如 csrw)写 CSR
            case (csr_waddr)
                12'h300: mstatus <= csr_wdata;
                12'h305: mtvec   <= csr_wdata;
                12'h341: mepc    <= csr_wdata;
                12'h342: mcause  <= csr_wdata;
                default: ;
            endcase
        end
    end

    // 读逻辑：软件指令读 CSR
    always @(*) begin
        case (csr_raddr)
            12'h300: csr_rdata = mstatus;
            12'h305: csr_rdata = mtvec;
            12'h341: csr_rdata = mepc;
            12'h342: csr_rdata = mcause;
            default: csr_rdata = 32'b0;
        endcase
    end

endmodule
