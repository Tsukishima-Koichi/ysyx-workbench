`timescale 1ns / 1ps

module MDU (
    input  logic        clk,
    input  logic        rst,
    input  logic        start,
    input  logic [2:0]  funct3,
    input  logic [31:0] a,
    input  logic [31:0] b,
    output logic [31:0] result,
    output logic        busy,
    output logic        done
);
    wire is_div = funct3[2];
    logic [2:0] op_funct3;

    always_ff @(posedge clk) begin
        if (rst)
            op_funct3 <= 3'b000;
        else if (start)
            op_funct3 <= funct3;
    end

    // Stage 1 registers a 32x32 unsigned product. Stage 2 applies only the
    // signed high-word correction, avoiding the former 33x33 sign path.
    typedef enum logic [1:0] {MUL_IDLE, MUL_PRODUCT, MUL_FINAL} mul_state_t;
    mul_state_t mul_state;

    logic [31:0] mul_a_reg, mul_b_reg;
    logic        mul_sub_b_reg, mul_sub_a_reg;
    logic [63:0] unsigned_product_reg;
    logic [31:0] mul_correction_reg;

    (* use_dsp = "yes" *) wire [63:0] unsigned_product = mul_a_reg * mul_b_reg;
    wire [31:0] mul_correction =
        (mul_sub_b_reg ? mul_b_reg : 32'd0) +
        (mul_sub_a_reg ? mul_a_reg : 32'd0);
    wire [31:0] corrected_high = unsigned_product_reg[63:32] - mul_correction_reg;
    wire [31:0] mul_final = (op_funct3 == 3'b000) ?
                            unsigned_product_reg[31:0] : corrected_high;
    wire fast_mul_done = (mul_state == MUL_PRODUCT) &&
                         (op_funct3 == 3'b000);

    always_ff @(posedge clk) begin
        if (rst) begin
            mul_state     <= MUL_IDLE;
            mul_a_reg     <= 32'd0;
            mul_b_reg     <= 32'd0;
            mul_sub_b_reg <= 1'b0;
            mul_sub_a_reg <= 1'b0;
            unsigned_product_reg <= 64'd0;
            mul_correction_reg   <= 32'd0;
        end else begin
            case (mul_state)
                MUL_IDLE: begin
                    if (start && !is_div) begin
                        mul_a_reg     <= a;
                        mul_b_reg     <= b;
                        mul_sub_b_reg <= a[31] &&
                                         ((funct3 == 3'b001) || (funct3 == 3'b010));
                        mul_sub_a_reg <= b[31] && (funct3 == 3'b001);
                        mul_state     <= MUL_PRODUCT;
                    end
                end
                MUL_PRODUCT: begin
                    if (op_funct3 == 3'b000) begin
                        // The low word needs no signed correction. The DSP
                        // output is ready for the EX/MEM1 capture this cycle.
                        mul_state <= MUL_IDLE;
                    end else begin
                        unsigned_product_reg <= unsigned_product;
                        mul_correction_reg   <= mul_correction;
                        mul_state            <= MUL_FINAL;
                    end
                end
                MUL_FINAL: mul_state <= MUL_IDLE;
                default:   mul_state <= MUL_IDLE;
            endcase
        end
    end

    // Iterative divider.
    wire is_signed_div = ~funct3[0];
    wire sign_a = is_signed_div & a[31];
    wire sign_b = is_signed_div & b[31];
    wire [31:0] abs_a = sign_a ? -a : a;
    wire [31:0] abs_b = sign_b ? -b : b;

    logic [63:0] shift_reg;
    logic [31:0] div_b;
    logic [31:0] div_orig_a;
    logic [5:0]  count;
    logic        div_sign_quo, div_sign_rem;
    logic        div_busy, div_done;

    typedef enum logic [1:0] {DIV_IDLE, DIV_SHIFT, DIV_DONE} div_state_t;
    div_state_t div_state;

    wire [32:0] diff = shift_reg[63:31] - {1'b0, div_b};
    wire [31:0] final_quo = (div_b == 0) ? 32'hffff_ffff :
                              (div_sign_quo ? -shift_reg[31:0] : shift_reg[31:0]);
    wire [31:0] final_rem = (div_b == 0) ? div_orig_a :
                              (div_sign_rem ? -shift_reg[63:32] : shift_reg[63:32]);
    wire [31:0] div_result = op_funct3[1] ? final_rem : final_quo;

    // Selection is completed before this register. Neither funct3 nor the
    // operation family remains in the forwarding/redirect result path.
    logic [31:0] mdu_result_reg;
    always_ff @(posedge clk) begin
        if (rst)
            mdu_result_reg <= 32'd0;
        else if (fast_mul_done)
            mdu_result_reg <= unsigned_product[31:0];
        else if (mul_state == MUL_FINAL)
            mdu_result_reg <= mul_final;
        else if ((div_state == DIV_SHIFT) && (count == 0))
            mdu_result_reg <= div_result;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            div_state    <= DIV_IDLE;
            div_busy     <= 1'b0;
            div_done     <= 1'b0;
            shift_reg    <= 64'd0;
            div_b        <= 32'd0;
            div_orig_a   <= 32'd0;
            count        <= 6'd0;
            div_sign_quo <= 1'b0;
            div_sign_rem <= 1'b0;
        end else begin
            case (div_state)
                DIV_IDLE: begin
                    div_done <= 1'b0;
                    if (start && is_div) begin
                        div_state    <= DIV_SHIFT;
                        div_busy     <= 1'b1;
                        shift_reg    <= {32'b0, abs_a};
                        div_b        <= abs_b;
                        div_orig_a   <= a;
                        div_sign_quo <= sign_a ^ sign_b;
                        div_sign_rem <= sign_a;
                        count        <= (b == 0) ? 6'd0 : 6'd32;
                    end
                end
                DIV_SHIFT: begin
                    if (count == 0) begin
                        div_state <= DIV_DONE;
                        div_busy  <= 1'b0;
                        div_done  <= 1'b1;
                    end else begin
                        if (!diff[32])
                            shift_reg <= {diff[31:0], shift_reg[30:0], 1'b1};
                        else
                            shift_reg <= {shift_reg[62:0], 1'b0};
                        count <= count - 1'b1;
                    end
                end
                DIV_DONE: begin
                    div_done  <= 1'b0;
                    div_state <= DIV_IDLE;
                end
                default: begin
                    div_state <= DIV_IDLE;
                    div_busy  <= 1'b0;
                    div_done  <= 1'b0;
                end
            endcase
        end
    end

    // During a completion cycle, expose the value before the active edge so
    // EX/MEM1 can capture it without a live MDU mux in the MEM1 stage.
    assign result = fast_mul_done          ? unsigned_product[31:0] :
                    (mul_state == MUL_FINAL) ? mul_final : mdu_result_reg;
    assign busy   = div_busy | (mul_state != MUL_IDLE);
    assign done   = div_done | (mul_state == MUL_FINAL) | fast_mul_done;
endmodule
