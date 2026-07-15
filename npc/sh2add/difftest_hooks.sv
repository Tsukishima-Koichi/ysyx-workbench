// ============================================================================
// difftest_hooks.sv — NPC DiffTest 基础设施 (独立模块，与 myCPU.sv 解耦)
//
// 功能:
//   1. 追踪流水线提交 (EX→MEM1→MEM2→WB)
//   2. 追踪 CSR 写操作 (精确到 WB 阶段)
//   3. 维护 DiffTest 影子 CSR 寄存器
//   4. 导出 DPI-C 函数给 C++ difftest 使用
//
// 用法：在 myCPU.sv 中实例化，连接内部信号即可。
// 替换 myCPU.sv 时保留此文件和实例化代码。
// ============================================================================

module difftest_hooks (
    input  logic        clk,
    input  logic        rst,

    // ---- EX 阶段控制信号 ----
    input  logic        ex_valid,
    input  logic [31:0] ex_pc,
    input  logic        ex_IsEcall,
    input  logic        ex_IsEbreak,
    input  logic        ex_IsMret,
    input  logic        ex_actual_csr_wen,
    input  logic [11:0] ex_csr_idx,
    input  logic [31:0] ex_next_csr_val,
    input  logic        flush_EX_MEM1,

    // ---- WB 提交探针 (输出给 cpu.sv 和 difftest) ----
    output logic        wb_valid,
    output logic [31:0] wb_pc
);

    // ---- 流水线有效位和 PC 追踪 ----
    logic mem1_valid, mem2_valid;
    logic [31:0] mem1_pc, mem2_pc;

    // ---- CSR 写旁路流水线 ----
    logic        mem1_csr_wen_diff, mem2_csr_wen_diff, wb_csr_wen_diff;
    logic [11:0] mem1_csr_idx_diff, mem2_csr_idx_diff, wb_csr_idx_diff;
    logic [31:0] mem1_csr_val_diff, mem2_csr_val_diff, wb_csr_val_diff;
    // ---- 异常信号旁路 ----
    logic        mem1_ecall_diff,  mem2_ecall_diff,  wb_ecall_diff;
    logic        mem1_ebreak_diff, mem2_ebreak_diff, wb_ebreak_diff;
    logic        mem1_mret_diff,   mem2_mret_diff,   wb_mret_diff;

    always_ff @(posedge clk) begin
        if (rst) begin
            mem1_valid <= 0; mem2_valid <= 0; wb_valid <= 0;
            mem1_pc <= 0; mem2_pc <= 0; wb_pc <= 0;

            mem1_csr_wen_diff <= 0; mem2_csr_wen_diff <= 0; wb_csr_wen_diff <= 0;
            mem1_ecall_diff   <= 0; mem2_ecall_diff   <= 0; wb_ecall_diff   <= 0;
            mem1_ebreak_diff  <= 0; mem2_ebreak_diff  <= 0; wb_ebreak_diff  <= 0;
            mem1_mret_diff    <= 0; mem2_mret_diff    <= 0; wb_mret_diff    <= 0;
        end else begin
            // EX → MEM1
            if (flush_EX_MEM1) begin
                mem1_valid        <= 1'b0;
                mem1_csr_wen_diff <= 0;
                mem1_ecall_diff   <= 0;
                mem1_ebreak_diff  <= 0;
                mem1_mret_diff    <= 0;
            end else begin
                mem1_valid        <= ex_valid;
                mem1_csr_wen_diff <= ex_valid & ex_actual_csr_wen;
                mem1_ecall_diff   <= ex_valid & ex_IsEcall;
                mem1_ebreak_diff  <= ex_valid & ex_IsEbreak;
                mem1_mret_diff    <= ex_valid & ex_IsMret;
                mem1_csr_idx_diff <= ex_csr_idx;
                mem1_csr_val_diff <= ex_next_csr_val;
            end
            mem1_pc <= ex_pc;

            // MEM1 → MEM2
            mem2_valid        <= mem1_valid;
            mem2_pc           <= mem1_pc;
            mem2_csr_wen_diff <= mem1_csr_wen_diff;
            mem2_csr_idx_diff <= mem1_csr_idx_diff;
            mem2_csr_val_diff <= mem1_csr_val_diff;
            mem2_ecall_diff   <= mem1_ecall_diff;
            mem2_ebreak_diff  <= mem1_ebreak_diff;
            mem2_mret_diff    <= mem1_mret_diff;

            // MEM2 → WB
            wb_valid          <= mem2_valid;
            wb_pc             <= mem2_pc;
            wb_csr_wen_diff   <= mem2_csr_wen_diff;
            wb_csr_idx_diff   <= mem2_csr_idx_diff;
            wb_csr_val_diff   <= mem2_csr_val_diff;
            wb_ecall_diff     <= mem2_ecall_diff;
            wb_ebreak_diff    <= mem2_ebreak_diff;
            wb_mret_diff      <= mem2_mret_diff;
        end
    end

    // ---- DiffTest 影子 CSR 寄存器 ----
    logic [31:0] diff_mstatus  = 32'h1800;
    logic [31:0] diff_mtvec    = 32'h0;
    logic [31:0] diff_mscratch = 32'h0;
    logic [31:0] diff_mepc     = 32'h0;
    logic [31:0] diff_mcause   = 32'h0;

    always_ff @(posedge clk) begin
        if (rst) begin
            diff_mstatus  <= 32'h1800;
            diff_mtvec    <= 32'h0;
            diff_mscratch <= 32'h0;
            diff_mepc     <= 32'h0;
            diff_mcause   <= 32'h0;
        end else begin
            if (wb_ecall_diff) begin
                diff_mepc    <= wb_pc;
                diff_mcause  <= 32'h0000_000B;
                diff_mstatus <= {diff_mstatus[31:13], 2'b11, diff_mstatus[10:8],
                                 diff_mstatus[3], diff_mstatus[6:4], 1'b0, diff_mstatus[2:0]};
            end else if (wb_ebreak_diff) begin
                diff_mepc    <= wb_pc;
                diff_mcause  <= 32'h0000_0003;
                diff_mstatus <= {diff_mstatus[31:13], 2'b11, diff_mstatus[10:8],
                                 diff_mstatus[3], diff_mstatus[6:4], 1'b0, diff_mstatus[2:0]};
            end else if (wb_mret_diff) begin
                diff_mstatus <= {diff_mstatus[31:13], 2'b00, diff_mstatus[10:8],
                                 1'b1, diff_mstatus[6:4], diff_mstatus[7], diff_mstatus[2:0]};
            end else if (wb_csr_wen_diff) begin
                case (wb_csr_idx_diff)
                    12'h300: diff_mstatus  <= wb_csr_val_diff;
                    12'h305: diff_mtvec    <= wb_csr_val_diff;
                    12'h340: diff_mscratch <= wb_csr_val_diff;
                    12'h341: diff_mepc     <= wb_csr_val_diff;
                    12'h342: diff_mcause   <= wb_csr_val_diff;
                    default: ;
                endcase
            end
        end
    end

    // ---- DPI-C 导出 ----
    export "DPI-C" function get_csr;
    function int get_csr(input int idx);
        case (idx)
            32'h300: return diff_mstatus;
            32'h305: return diff_mtvec;
            32'h340: return diff_mscratch;
            32'h341: return diff_mepc;
            32'h342: return diff_mcause;
            default: return 0;
        endcase
    endfunction

    // ---- 注册 DPI 作用域 (给 C++ difftest 使用) ----
    import "DPI-C" context function void set_csr_scope();
    initial begin
        set_csr_scope();
    end

endmodule
