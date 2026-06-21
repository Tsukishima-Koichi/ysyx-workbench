`timescale 1ns / 1ps

module MDU (
    input  logic        clk,
    input  logic        rst,
    input  logic        start,  // EX 阶段触发（现在乘法和除法都需要触发）
    input  logic [2:0]  funct3,
    input  logic [31:0] a,      // rs1
    input  logic [31:0] b,      // rs2
    output logic [31:0] result,
    output logic        busy,   // 给流水线发出的阻塞信号
    output logic        done    // 运算完成的单周期脉冲
);

    wire is_div = funct3[2]; // 0xx: MUL, 1xx: DIV/REM

    // ==========================================
    // 1. DSP 乘法器 (300MHz 终极优化：二级全流水线状态机)
    // ==========================================
    wire is_signed_a = (funct3 == 3'b001 || funct3 == 3'b010 || funct3 == 3'b000);
    wire is_signed_b = (funct3 == 3'b001 || funct3 == 3'b000);
    
    wire signed [32:0] mul_a = {is_signed_a & a[31], a};
    wire signed [32:0] mul_b = {is_signed_b & b[31], b};

    // 为 DSP 的输入和输出显式声明寄存器
    logic signed [32:0] mul_a_reg, mul_b_reg;
    logic [63:0]        mul_res_reg;
    
    // 采用状态机控制，防止 EX 阶段持续发出的 start 导致重复触发
    logic [1:0] mul_state; // 00: IDLE, 01: STAGE1, 10: DONE
    
    always_ff @(posedge clk) begin
        if (rst) begin
            mul_state   <= 2'b00;
            mul_a_reg   <= 0;
            mul_b_reg   <= 0;
            mul_res_reg <= 0;
        end else begin
            case (mul_state)
                2'b00: begin
                    if (start && !is_div) begin
                        mul_a_reg <= mul_a;
                        mul_b_reg <= mul_b;
                        mul_state <= 2'b01;
                    end
                end
                2'b01: begin
                    // 🌟 修复 1：显式截取低 64 位，告诉 Verilator 我们是故意截断的
                    mul_res_reg <= mul_res_64[63:0];
                    mul_state <= 2'b10;
                end
                2'b10: begin
                    mul_state <= 2'b00;
                end
                // 🌟 修复 2：增加 default 兜底未覆盖的 2'b11 状态
                default: begin
                    mul_state <= 2'b00;
                end
            endcase
        end
    end

    // 中间乘法逻辑，Vivado 会自动将前后寄存器吸纳入 DSP 硬核
    (* use_dsp = "yes" *) wire signed [65:0] mul_res_64 = mul_a_reg * mul_b_reg;

    wire [31:0] mul_res = (funct3 == 3'b000) ? mul_res_reg[31:0] : mul_res_reg[63:32];

    

    // ==========================================
    // 2. 多周期迭代除法器 (状态机保持不变)
    // ==========================================
    wire is_signed_div = ~funct3[0];
    wire sign_a = is_signed_div & a[31];
    wire sign_b = is_signed_div & b[31];
    
    wire [31:0] abs_a = sign_a ? -a : a;
    wire [31:0] abs_b = sign_b ? -b : b;

    logic [63:0] shift_reg;
    logic [31:0] div_b;
    logic [5:0]  count;
    logic div_sign_quo, div_sign_rem;
    
    logic div_busy, div_done;
    
    // 避免与系统关键字冲突，将 DONE 稍微改名
    typedef enum logic [1:0] {IDLE, SHIFT, DONE_ST} state_t;
    state_t state;

    wire [32:0] diff = shift_reg[63:31] - {1'b0, div_b};

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            div_busy <= 0;
            div_done <= 0;
        end else case (state)
            IDLE: begin
                div_done <= 0;
                if (start & is_div) begin
                    state <= SHIFT;
                    div_busy <= 1;
                    shift_reg <= {32'b0, abs_a};
                    div_b <= abs_b;
                    div_sign_quo <= sign_a ^ sign_b;
                    div_sign_rem <= sign_a;
                    
                    if (b == 0) begin
                        count <= 0;
                    end else begin
                        count <= 32;
                    end
                end
            end
            SHIFT: begin
                if (count == 0) begin
                    state <= DONE_ST;
                    div_busy <= 0;
                    div_done <= 1;
                end else begin
                    if (diff[32] == 1'b0) begin
                        shift_reg <= {diff[31:0], shift_reg[30:0], 1'b1};
                    end else begin
                        shift_reg <= {shift_reg[62:0], 1'b0};
                    end
                    count <= count - 1;
                end
            end
            DONE_ST: begin
                div_done <= 0;
                state <= IDLE;
            end
            default: begin
                state <= IDLE;
                div_busy <= 0;
                div_done <= 0;
            end
        endcase
    end
    
    wire [31:0] final_quo = (div_b == 0) ? 32'hFFFFFFFF : (div_sign_quo ? -shift_reg[31:0] : shift_reg[31:0]);
    wire [31:0] orig_a    = sign_a ? -shift_reg[31:0] : shift_reg[31:0]; 
    wire [31:0] final_rem = (div_b == 0) ? orig_a : (div_sign_rem ? -shift_reg[63:32] : shift_reg[63:32]);

    wire [31:0] div_res = (funct3[1]) ? final_rem : final_quo;
    
    // ==========================================
    // 3. 握手信号与结果路由 (修改最后这部分)
    // ==========================================
    assign result = is_div ? div_res : mul_res;
    
    // 彻底切断 busy 环路，仅依赖 done 信号来控制流水线放行！
    assign busy = is_div ? div_busy : 1'b0; 
    assign done = is_div ? div_done : (mul_state == 2'b10);

endmodule
