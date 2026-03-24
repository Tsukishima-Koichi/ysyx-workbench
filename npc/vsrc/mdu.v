module mdu(
    input  [31:0] a,
    input  [31:0] b,
    input  [2:0]  funct3, // M 扩展指令刚好用 funct3 就能完美区分
    output reg [31:0] res
);

    // ==========================================
    // 1. 乘法逻辑：先强行扩展到 64 位，防止溢出和符号错误
    // ==========================================
    wire signed [63:0] a_signed   = {{32{a[31]}}, a}; // 有符号扩展
    wire signed [63:0] b_signed   = {{32{b[31]}}, b}; // 有符号扩展
    wire signed [63:0] a_unsigned = {32'b0, a};       // 无符号扩展
    wire signed [63:0] b_unsigned = {32'b0, b};       // 无符号扩展

    // 提前算出三种乘法的 64 位完整结果
    wire [63:0] mul_ss = a_signed * b_signed;     // 有符号 * 有符号
    /* verilator lint_off UNUSEDSIGNAL */
    wire [63:0] mul_su = a_signed * b_unsigned;   // 有符号 * 无符号
    wire [63:0] mul_uu = a_unsigned * b_unsigned; // 无符号 * 无符号
    /* verilator lint_on UNUSEDSIGNAL */

    // ==========================================
    // 2. 除法防御逻辑：RISC-V 官方指定的“防爆”规则
    // ==========================================
    wire is_div_by_zero = (b == 32'b0);
    // 溢出仅发生在一处：-2^31 (0x8000_0000) 除以 -1 (0xFFFF_FFFF)
    wire is_overflow    = (a == 32'h80000000 && b == 32'hFFFFFFFF);

    // ==========================================
    // 3. 结果多路选择器
    // ==========================================
    always @(*) begin
        case (funct3)
            // --------- 乘法指令 ---------
            3'b000: res = mul_ss[31:0];  // mul:    只取低 32 位 (随便用哪个算结果都一样)
            3'b001: res = mul_ss[63:32]; // mulh:   有符号*有符号，取高 32 位
            3'b010: res = mul_su[63:32]; // mulhsu: 有符号*无符号，取高 32 位
            3'b011: res = mul_uu[63:32]; // mulhu:  无符号*无符号，取高 32 位
            
            // --------- 除法指令 ---------
            3'b100: begin // div: 有符号除法
                if (is_div_by_zero) res = 32'hFFFFFFFF;     // 规定: 除以0结果全是1 (-1)
                else if (is_overflow) res = 32'h80000000;   // 规定: 溢出结果是被除数本身
                else res = $signed(a) / $signed(b);
            end
            3'b101: begin // divu: 无符号除法
                if (is_div_by_zero) res = 32'hFFFFFFFF;     // 规定: 除以0结果是全1 (2^32-1)
                else res = a / b;
            end
            
            // --------- 取模指令 ---------
            3'b110: begin // rem: 有符号取模
                if (is_div_by_zero) res = a;                // 规定: 模0结果是被除数本身
                else if (is_overflow) res = 32'b0;          // 规定: 溢出取模结果是0
                else res = $signed(a) % $signed(b);
            end
            3'b111: begin // remu: 无符号取模
                if (is_div_by_zero) res = a;                // 规定: 模0结果是被除数本身
                else res = a % b;
            end
        endcase
    end

endmodule
