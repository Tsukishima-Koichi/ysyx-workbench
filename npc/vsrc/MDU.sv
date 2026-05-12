`timescale 1ns / 1ps

module MDU (
    input  logic        clk,
    input  logic        rst,
    input  logic        start,  // EX 阶段触发除法
    input  logic [2:0]  funct3,
    input  logic [31:0] a,      // rs1
    input  logic [31:0] b,      // rs2
    output logic [31:0] result,
    output logic        busy,   // 给流水线发出的阻塞信号
    output logic        done    // 除法完成的单周期脉冲
);
    wire is_div = funct3[2]; // 0xx: MUL, 1xx: DIV/REM

    // ==========================================
    // 1. DSP 单周期乘法器 (直接映射到 FPGA DSP Slice)
    // ==========================================
    // RISC-V 语义:
    // 000: MUL (取低32位, 符号无关)
    // 001: MULH (有符号 * 有符号, 取高32位)
    // 010: MULHSU (有符号 * 无符号)
    // 011: MULHU (无符号 * 无符号)
    wire is_signed_a = (funct3 == 3'b001 || funct3 == 3'b010 || funct3 == 3'b000);
    wire is_signed_b = (funct3 == 3'b001 || funct3 == 3'b000);
    
    wire signed [32:0] mul_a = {is_signed_a & a[31], a};
    wire signed [32:0] mul_b = {is_signed_b & b[31], b};
    wire signed [65:0] mul_res_64 = mul_a * mul_b;
    
    wire [31:0] mul_res = (funct3 == 3'b000) ? mul_res_64[31:0] : mul_res_64[63:32];

    // ==========================================
    // 2. 多周期迭代除法器 (状态机版，不炸时序)
    // ==========================================
    // 100: DIV, 101: DIVU, 110: REM, 111: REMU
    wire is_signed_div = ~funct3[0];
    wire sign_a = is_signed_div & a[31];
    wire sign_b = is_signed_div & b[31];
    
    wire [31:0] abs_a = sign_a ? -a : a;
    wire [31:0] abs_b = sign_b ? -b : b;

    logic [63:0] shift_reg;
    logic [31:0] div_b;
    logic [5:0]  count;
    logic div_sign_quo, div_sign_rem;
    
    typedef enum logic [1:0] {IDLE, SHIFT, DONE} state_t;
    state_t state;

    wire [32:0] diff = shift_reg[63:31] - {1'b0, div_b};

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            busy <= 0;
            done <= 0;
        end else case (state)
            IDLE: begin
                done <= 0;
                if (start & is_div) begin
                    state <= SHIFT;
                    busy <= 1;
                    count <= 32;
                    shift_reg <= {32'b0, abs_a};
                    div_b <= abs_b;
                    div_sign_quo <= sign_a ^ sign_b;
                    div_sign_rem <= sign_a;
                    
                    // RISC-V 异常处理：除以零
                    // RISC-V 异常处理：除以零
                    if (b == 0) begin
                        // 🌟 修复死锁：不要直接跳 DONE，让它正常进 SHIFT 状态，
                        // 因为 count=0，下一拍 SHIFT 就会完美触发 busy=0 和 done=1 的释放逻辑！
                        count <= 0; 
                    end else begin
                        count <= 32; // 正常的除法要移位 32 次
                    end
                end
            end
            SHIFT: begin
                if (count == 0) begin
                    state <= DONE;
                    busy <= 0;
                    done <= 1;
                end else begin
                    // 恢复型除法算法 (Restoring Division)
                    if (diff[32] == 1'b0) begin // 够减
                        shift_reg <= {diff[31:0], shift_reg[30:0], 1'b1};
                    end else begin // 不够减，左移并补0
                        shift_reg <= {shift_reg[62:0], 1'b0};
                    end
                    count <= count - 1;
                end
            end
            DONE: begin
                done <= 0;
                state <= IDLE;
            end
            default: begin
                state <= IDLE;
                busy <= 0;
                done <= 0;
            end
        endcase
    end
    
    // RISC-V 规范对除以 0 的最终值要求：除法为 -1，取模为被除数
    // 🌟 修复：必须使用内部锁存的 div_b，因为外部流水线阻塞时前递的数据 a 和 b 早就失效了！
    wire [31:0] final_quo = (div_b == 0) ? 32'hFFFFFFFF : (div_sign_quo ? -shift_reg[31:0] : shift_reg[31:0]);
    
    // 🌟 对于余数同理，如果是除以 0，需要返回原来的被除数，由于 a 也会随前递丢失，
    // 原来的被除数 a 的绝对值已经被锁存到了 shift_reg 的低 32 位（因为 b=0 时移位根本不改变值）
    // 或者通过符号恢复。为确保稳定，我们直接使用内部已有的逻辑：
    wire [31:0] orig_a    = sign_a ? -shift_reg[31:0] : shift_reg[31:0]; 
    wire [31:0] final_rem = (div_b == 0) ? orig_a : (div_sign_rem ? -shift_reg[63:32] : shift_reg[63:32]);

    wire [31:0] div_res = (funct3[1]) ? final_rem : final_quo; // bit[1]区分 DIV(0) 和 REM(1)
    
    assign result = is_div ? div_res : mul_res;
endmodule
