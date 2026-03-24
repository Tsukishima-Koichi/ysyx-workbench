module alu(
    input  [31:0] a,
    input  [31:0] b,
    input  [3:0]  alu_ctrl,
    output reg [31:0] res, // ALU 计算结果 (写回寄存器用)
    
    // 分支判断专用的 Flag 输出
    output        zero,    // a == b 吗？
    output        less,    // 有符号 a < b 吗？
    output        lessu    // 无符号 a < b 吗？
);

    // 1. 生成 Flag 标志位（专供 B 型分支指令使用）
    assign zero  = (res == 32'b0);               // 当减法结果为0时，说明相等
    assign less  = ($signed(a) < $signed(b));    // 有符号比较必须加 $signed
    assign lessu = (a < b);                      // 无符号比较

    // 2. 核心计算逻辑
    always @(*) begin
        case (alu_ctrl)
            4'b0000: res = a + b;                  // ADD  (加法: add, addi, load, store, lui)
            4'b1000: res = a - b;                  // SUB  (减法: sub, beq, bne)
            
            4'b0001: res = a << b[4:0];            // SLL  (逻辑左移)
            4'b0101: res = a >> b[4:0];            // SRL  (逻辑右移)
            4'b1101: res = $signed(a) >>> b[4:0];  // SRA  (算术右移，最高位补符号位)
            
            4'b0100: res = a ^ b;                  // XOR  (按位异或)
            4'b0110: res = a | b;                  // OR   (按位或)
            4'b0111: res = a & b;                  // AND  (按位与)
            
            4'b0010: res = {31'b0, less};          // SLT  (有符号小于置 1)
            4'b0011: res = {31'b0, lessu};         // SLTU (无符号小于置 1)
            
            default: res = 32'b0;
        endcase
    end

endmodule
