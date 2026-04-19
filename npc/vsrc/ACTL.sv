`timescale 1ns / 1ps
`include "defines.sv"

module ACTL(
    input  logic [6:0] opcode,
    input  logic [2:0] funct3,
    input  logic [6:0] funct7,
    output logic [3:0] alu_ctrl
);
    // --------------------------------------------------------
    // 1. 提取基础标志位 (纯并行比较)
    // --------------------------------------------------------
    wire is_R = (opcode === `R_TYPE);
    wire is_I = (opcode === `I_TYPE);
    
    // 只有 R型 和 I型运算指令才需要解析 funct3 来决定 ALU 操作
    wire use_funct3 = is_R | is_I;

    // --------------------------------------------------------
    // 2. 提取特殊运算标志 (依赖 funct7[5] 进行区分)
    // --------------------------------------------------------
    // SUB (减法): 只有 R型指令，且 funct3=000，且 funct7[5]=1 时才触发
    wire is_sub = is_R & (funct3 === 3'b000) & (funct7[5] === 1'b1);
    
    // SRA/SRAI (算术右移): R型或I型，且 funct3=101，且 funct7[5]=1 时触发
    wire is_sra = use_funct3 & (funct3 === 3'b101) & (funct7[5] === 1'b1);

    // --------------------------------------------------------
    // 3. 并行输出各比特位 (布尔代数方程)
    // --------------------------------------------------------
    // Bit 3: 命中 OR(1000) 或 AND(1001) -> 对应 funct3 为 110, 111
    assign alu_ctrl[3] = use_funct3 & (funct3[2] & funct3[1]);

    // Bit 2: 命中 SLTU(0100), XOR(0101), SRL(0110), SRA(0111) -> 对应 funct3 为 011, 100, 101
    assign alu_ctrl[2] = use_funct3 & ( (funct3 === 3'b011) | (funct3[2] & ~funct3[1]) );

    // Bit 1: 命中 SLL(0010), SLT(0011), SRL(0110), SRA(0111) -> 对应 funct3 为 001, 010, 101
    assign alu_ctrl[1] = use_funct3 & ( (funct3 === 3'b001) | (funct3 === 3'b010) | (funct3 === 3'b101) );

    // Bit 0: 命中 SUB(0001), SLT(0011), XOR(0101), SRA(0111), AND(1001)
    assign alu_ctrl[0] = use_funct3 & ( is_sub | (funct3 === 3'b010) | (funct3 === 3'b100) | is_sra | (funct3 === 3'b111) );

endmodule



// `timescale 1ns / 1ps
// `include "defines.sv"

// module ACTL(
//     input  logic [6:0] opcode,
//     input  logic [2:0] funct3,
//     input  logic [6:0] funct7,
//     output logic [3:0] alu_ctrl
// );
//     // (RV32I)
//     localparam ALU_ADD  = 4'd0;
//     localparam ALU_SUB  = 4'd1;
//     localparam ALU_SLL  = 4'd2;
//     localparam ALU_SLT  = 4'd3;
//     localparam ALU_SLTU = 4'd4;
//     localparam ALU_XOR  = 4'd5;
//     localparam ALU_SRL  = 4'd6;
//     localparam ALU_SRA  = 4'd7;
//     localparam ALU_OR   = 4'd8;
//     localparam ALU_AND  = 4'd9;

//     always_comb begin
//         alu_ctrl = ALU_ADD;
        
//         case(opcode)
//             `R_TYPE: begin
//                 case(funct3)
//                     3'b000: alu_ctrl = (funct7[5]) ? ALU_SUB : ALU_ADD; // ADD / SUB
//                     3'b001: alu_ctrl = ALU_SLL;
//                     3'b010: alu_ctrl = ALU_SLT;
//                     3'b011: alu_ctrl = ALU_SLTU;
//                     3'b100: alu_ctrl = ALU_XOR;
//                     3'b101: alu_ctrl = (funct7[5]) ? ALU_SRA : ALU_SRL; // SRL / SRA
//                     3'b110: alu_ctrl = ALU_OR;
//                     3'b111: alu_ctrl = ALU_AND;
//                 endcase
//             end
//             `I_TYPE: begin
//                 case(funct3)
//                     3'b000: alu_ctrl = ALU_ADD; // ADDI
//                     3'b001: alu_ctrl = ALU_SLL; // SLLI
//                     3'b010: alu_ctrl = ALU_SLT; // SLTI
//                     3'b011: alu_ctrl = ALU_SLTU;// SLTIU
//                     3'b100: alu_ctrl = ALU_XOR; // XORI
//                     3'b101: alu_ctrl = (funct7[5]) ? ALU_SRA : ALU_SRL; // SRLI / SRAI
//                     3'b110: alu_ctrl = ALU_OR;  // ORI
//                     3'b111: alu_ctrl = ALU_AND; // ANDI
//                 endcase
//             end
//             `B_TYPE: alu_ctrl = ALU_ADD;   
//             `IL_TYPE, `S_TYPE, `IJ_TYPE: alu_ctrl = ALU_ADD;
//             `U_TYPE: alu_ctrl = ALU_ADD; 
//             `UA_TYPE: alu_ctrl = ALU_ADD;
//             `J_TYPE: alu_ctrl = ALU_ADD;
//             default: alu_ctrl = ALU_ADD;
//         endcase
//     end
// endmodule
