module npc(
    input  [31:0] pc,          
    input  [31:0] rs1_data,    
    input  [31:0] imm,         // 顶层传进来的立即数 (imm_J, imm_I, imm_B, 以及 auipc 的 imm_U)
    input         is_jalr,     
    input         do_jump,

    // 异常跳转接口
    input         is_ecall,
    input         is_mret,
    input  [31:0] mtvec_val,
    input  [31:0] mepc_val,
    
    output [31:0] next_pc,       // 供 PC 寄存器更新使用
    output [31:0] pc_plus_4_out, // 【新增】直接吐出 PC+4，供 jal/jalr 写回 rd 使用
    output [31:0] pc_plus_imm    // 【新增】直接吐出 PC+imm，供 auipc 写回 rd 使用
);

    // 1. 算 PC + 4
    wire [31:0] pc_plus_4 = pc + 32'd4;
    assign pc_plus_4_out = pc_plus_4; // 暴露给外部

    // 2. 算 目标地址/相对地址
    wire [31:0] base_addr = is_jalr ? rs1_data : pc;
    wire [31:0] target_raw = base_addr + imm;
    
    // 如果外部传进来的是 auipc 的 imm_U，那 target_raw 恰好就是 PC + imm_U！
    assign pc_plus_imm = target_raw; // 暴露给外部

    // 3. JALR 最低位清零保护
    wire [31:0] jump_target = is_jalr ? {target_raw[31:1], 1'b0} : target_raw;

    // 4. 终极裁决 MUX：注意优先级！异常跳转的优先级极高
    assign next_pc = 
        (is_ecall) ? mtvec_val   : // 呼叫系统，跳去 mtvec
        (is_mret)  ? mepc_val    : // 从系统返回，跳回 mepc
        (do_jump)  ? jump_target : // 普通的分支或跳转
                     pc_plus_4   ; // 乖乖顺着执行

endmodule
