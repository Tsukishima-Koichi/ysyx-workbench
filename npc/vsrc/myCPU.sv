`timescale 1ns / 1ps
`include "defines.sv"

module myCPU (
    input  logic         cpu_rst,
    input  logic         cpu_clk,

    output logic [31:0]  irom_addr,
    input  logic [31:0]  irom_data,
    
    output logic [31:0]  perip_addr,
    output logic         perip_wen,
    output logic [ 3:0]  perip_mask,
    output logic [31:0]  perip_wdata,
    input  logic [31:0]  perip_rdata
);
    parameter DATAWIDTH = 32;
    parameter RESET_VAL = 32'h8000_0000;

    // ==========================================
    // 全局控制信号 (Global Control Signals)
    // ==========================================
    logic stall_IF, flush_IF_ID;
    logic stall_ID, flush_ID_EX;
    logic stall_EX, flush_EX_MEM;
    logic stall_MEM, flush_MEM_WB;
    
    // 后面的阶段永远不需要停顿
    assign stall_EX  = 1'b0;
    assign stall_MEM = 1'b0;
    assign flush_EX_MEM = 1'b0;
    assign flush_MEM_WB = 1'b0;

    // 1. 实例化冒险检测单元 (Hazard Detection Unit)
    logic hd_flush_ID_EX;
    HazardDetectionUnit hd_inst (
        .id_rs1      (id_inst[19:15]),
        .id_rs2      (id_inst[24:20]),
        .id_opcode   (id_inst[6:0]),   // 增加对 opcode 的连线
        .ex_WbSel    (ex_WbSel),
        .ex_rd       (ex_rd),
        .stall_IF    (stall_IF),
        .stall_ID    (stall_ID),
        .flush_ID_EX (hd_flush_ID_EX)
    );

    // 2. 紧急控制流信号 (在 EX 阶段产生)
    logic ex_take_branch; 
    logic ex_take_trap; // 新增：来自 CSR 模块的 Trap 信号
    
    // 3. 综合控制信号
    // IF/ID 冲刷：如果发生了普通跳转 OR 发生了异常陷阱，前一条指令作废
    assign flush_IF_ID = ex_take_branch | ex_take_trap; 
    
    // ID/EX 冲刷：跳转 OR 异常 OR Load-Use 冒险
    assign flush_ID_EX = ex_take_branch | ex_take_trap | hd_flush_ID_EX;

    // ==========================================
    // Stage 1: IF (Instruction Fetch)
    // ==========================================
    logic [31:0] if_pc, next_pc, actual_next_pc, if_inst;
    
    assign irom_addr = if_pc;
    assign if_inst   = irom_data;

    // 🌟 拦截 PC 的更新：如果 stall_IF 为 1，让 PC 保持原来的值 (if_pc)
    assign actual_next_pc = stall_IF ? if_pc : next_pc;

    PC #(DATAWIDTH, RESET_VAL) pc_inst (
        .clk(cpu_clk), .rst(cpu_rst),
        .npc(actual_next_pc), .pc_out(if_pc)
    );

    // ================= IF/ID Reg =================
    logic [31:0] id_pc, id_inst;
    IF_ID_Reg #(DATAWIDTH) if_id_reg (
        .clk(cpu_clk), .rst(cpu_rst), .flush(flush_IF_ID), .stall(stall_ID),
        .if_pc(if_pc), .if_inst(if_inst),
        .id_pc(id_pc), .id_inst(id_inst)
    );

    // ==========================================
    // Stage 2: ID (Instruction Decode)
    // ==========================================
    logic [31:0] id_imm, id_rs1_data, id_rs2_data;
    logic id_IsBranch, id_RegWen, id_MemWen, id_AluSrcB;
    logic [1:0] id_JmpType, id_WbSel, id_AluSrcA;
    logic [3:0] id_alu_ctrl;

    logic id_CsrWen, id_CsrImmSel, id_IsEcall, id_IsEbreak, id_IsMret;
    logic [1:0] id_CsrOp;

    // 译码器
    Control control_inst (
        .inst      (id_inst), 
        .IsBranch  (id_IsBranch), .JmpType (id_JmpType),
        .RegWen    (id_RegWen),   .MemWen  (id_MemWen),
        .WbSel     (id_WbSel),    .AluSrcA (id_AluSrcA), .AluSrcB (id_AluSrcB),
        .CsrWen(id_CsrWen), .CsrOp(id_CsrOp), .CsrImmSel(id_CsrImmSel), 
        .IsEcall(id_IsEcall), .IsEbreak(id_IsEbreak), .IsMret(id_IsMret)
    );

    IMMGEN #(DATAWIDTH) immgen_inst (.instr(id_inst), .imm(id_imm));

    ACTL actl_inst (
        .opcode   (id_inst[6:0]), .funct3 (id_inst[14:12]), .funct7 (id_inst[31:25]),
        .alu_ctrl (id_alu_ctrl)
    );

    // --- 注意这里：RF 写回数据来自 WB 阶段的信号 ---
    logic [4:0]  wb_rd;
    logic [31:0] wb_data;
    logic        wb_RegWen;

    RF #(5, DATAWIDTH) rf_inst (
        .clk(cpu_clk), .rst(cpu_rst), 
        .wen(wb_RegWen),                  // 来自 WB 阶段
        .waddr(wb_rd), .wdata(wb_data),   // 来自 WB 阶段
        .rR1(id_inst[19:15]), .rR2(id_inst[24:20]), 
        .rR1_data(id_rs1_data), .rR2_data(id_rs2_data)
    );

    // ================= ID/EX Reg =================
    logic [31:0] ex_pc, ex_rs1_data, ex_rs2_data, ex_imm;
    logic [4:0]  ex_rd, ex_rs1, ex_rs2;
    logic        ex_RegWen, ex_MemWen, ex_IsBranch, ex_AluSrcB;
    logic [1:0]  ex_JmpType, ex_WbSel, ex_AluSrcA;
    logic [3:0]  ex_alu_ctrl;
    logic [2:0]  ex_funct3;

    logic [11:0] ex_csr_idx;
    logic        ex_CsrWen, ex_CsrImmSel, ex_IsEcall, ex_IsEbreak, ex_IsMret;
    logic [1:0]  ex_CsrOp;

    ID_EX_Reg #(DATAWIDTH) id_ex_reg (
        .clk(cpu_clk), .rst(cpu_rst), .flush(flush_ID_EX), .stall(stall_EX),
        .id_pc(id_pc), .id_rs1_data(id_rs1_data), .id_rs2_data(id_rs2_data), .id_imm(id_imm),
        .id_rd(id_inst[11:7]), .id_rs1(id_inst[19:15]), .id_rs2(id_inst[24:20]),
        .id_RegWen(id_RegWen), .id_MemWen(id_MemWen), .id_IsBranch(id_IsBranch), .id_AluSrcB(id_AluSrcB),
        .id_JmpType(id_JmpType), .id_WbSel(id_WbSel), .id_AluSrcA(id_AluSrcA),
        .id_alu_ctrl(id_alu_ctrl), .id_funct3(id_inst[14:12]),
        .id_csr_idx   (id_inst[31:20]), 
        .id_CsrWen    (id_CsrWen), 
        .id_CsrImmSel (id_CsrImmSel), 
        .id_IsEcall   (id_IsEcall), 
        .id_IsEbreak  (id_IsEbreak), 
        .id_IsMret    (id_IsMret),
        .id_CsrOp     (id_CsrOp),
        // Outputs
        .ex_pc(ex_pc), .ex_rs1_data(ex_rs1_data), .ex_rs2_data(ex_rs2_data), .ex_imm(ex_imm),
        .ex_rd(ex_rd), .ex_rs1(ex_rs1), .ex_rs2(ex_rs2),
        .ex_RegWen(ex_RegWen), .ex_MemWen(ex_MemWen), .ex_IsBranch(ex_IsBranch), .ex_AluSrcB(ex_AluSrcB),
        .ex_JmpType(ex_JmpType), .ex_WbSel(ex_WbSel), .ex_AluSrcA(ex_AluSrcA),
        .ex_alu_ctrl(ex_alu_ctrl), .ex_funct3(ex_funct3),
        .ex_csr_idx   (ex_csr_idx),
        .ex_CsrWen    (ex_CsrWen),
        .ex_CsrImmSel (ex_CsrImmSel),
        .ex_IsEcall   (ex_IsEcall),
        .ex_IsEbreak  (ex_IsEbreak),
        .ex_IsMret    (ex_IsMret),
        .ex_CsrOp     (ex_CsrOp)
    );

    // ==========================================
    // Stage 3: EX (Execute)
    // ==========================================
    logic [1:0] forward_A, forward_B;
    logic [31:0] forwarded_rs1, forwarded_rs2;
    logic [31:0] ex_alu_op1, ex_alu_op2, ex_alu_res, ex_ret_pc;

    // 1. 例化转发单元
    ForwardingUnit fw_inst (
        .ex_rs1     (ex_rs1),
        .ex_rs2     (ex_rs2),
        .mem_RegWen (mem_RegWen),
        .mem_rd     (mem_rd),
        .wb_RegWen  (wb_RegWen),
        .wb_rd      (wb_rd),
        .forward_A  (forward_A),
        .forward_B  (forward_B)
    );

    // 修复 Bug: 动态选择 MEM 阶段真实的写回数据
    logic [31:0] mem_fw_data;
    logic [31:0] mem_csr_rdata;
    logic [31:0] wb_csr_rdata;
    // WbSel == 2'b01 写回 ret_pc ; WbSel == 2'b11 写回 CSR 数据 ; 否则默认为 ALU 结果
    assign mem_fw_data = (mem_WbSel == 2'b01) ? mem_ret_pc : 
                         (mem_WbSel == 2'b11) ? mem_csr_rdata : mem_alu_res;

    // 2. 截胡（旁路）多路选择器
    always_comb begin
        case (forward_A)
            2'b10:   forwarded_rs1 = mem_fw_data; // 已修正为 mem_fw_data
            2'b01:   forwarded_rs1 = wb_data;     // wb_data 已经在 WB 阶段选好，无需修改
            default: forwarded_rs1 = ex_rs1_data; 
        endcase
    end

    always_comb begin
        case (forward_B)
            2'b10:   forwarded_rs2 = mem_fw_data; // 已修正为 mem_fw_data
            2'b01:   forwarded_rs2 = wb_data;     
            default: forwarded_rs2 = ex_rs2_data; 
        endcase
    end

    // 3. 将旁路后的干净数据喂给 ALU (注意这里换成了 forwarded_rs1 / 2)
    assign ex_alu_op1 = (ex_AluSrcA == 2'b10) ? 32'b0 :
                        (ex_AluSrcA == 2'b01) ? ex_pc : forwarded_rs1;
    assign ex_alu_op2 =  ex_AluSrcB           ? ex_imm: forwarded_rs2;

    ALU #(DATAWIDTH) alu_inst (
        .A(ex_alu_op1), .B(ex_alu_op2), .ALUControl(ex_alu_ctrl), .Result(ex_alu_res)
    );

    // 4. 将旁路后的干净数据喂给跳转判断单元
    logic [31:0] jump_branch_pc; 
    BranchUnit #(DATAWIDTH) bu_inst (
        .pc(ex_pc), .imm(ex_imm),
        .rs1_data(forwarded_rs1), .rs2_data(forwarded_rs2), // 必须使用 forward 后的数据！
        .trap_pc(32'b0), // 暂忽略异常
        .Branch(ex_IsBranch), .Jump(ex_JmpType), .funct3(ex_funct3),
        .next_pc(jump_branch_pc), .pc_plus_4(ex_ret_pc)
    );

    // ==========================================
    // EX 阶段: CSR 与 异常处理
    // ==========================================
    logic [31:0] ex_csr_wdata, ex_csr_rdata, trap_pc;
    logic ex_actual_csr_wen;

    // 巧妙利用：当 CsrImmSel 为 1 时，指令的 19:15 是 zimm 立即数。
    // 而我们在 ID 阶段已经提取了 id_rs1 = inst[19:15]。所以 ex_rs1 天然就是 zimm！
    assign ex_csr_wdata = ex_CsrImmSel ? {27'b0, ex_rs1} : forwarded_rs1;

    // 防止读 x0 寄存器产生的假写入
    assign ex_actual_csr_wen = ex_CsrWen && !((ex_CsrOp == 2'b10 || ex_CsrOp == 2'b11) && (ex_rs1 == 5'b0));

    CSR #(DATAWIDTH) csr_inst (
        .clk        (cpu_clk),
        .rst        (cpu_rst),
        .pc         (ex_pc),          // 发生异常的 PC
        .csr_idx    (ex_csr_idx),
        .wdata      (ex_csr_wdata),   // 必须使用前递(旁路)后的最新数据
        .csr_op     (ex_CsrOp),
        .csr_wen    (ex_actual_csr_wen),
        .ecall      (ex_IsEcall),
        .ebreak     (ex_IsEbreak),
        .mret       (ex_IsMret),
        .rdata      (ex_csr_rdata),
        .trap_pc    (trap_pc)
    );

    // 判定是否发生异常跳转 (Trap)
    assign ex_take_trap = ex_IsEcall | ex_IsEbreak | ex_IsMret;

    // 🌟 终极 PC 路由逻辑：异常优先级最高，其次是普通分支，最后是 PC+4
    assign ex_take_branch = (jump_branch_pc != ex_ret_pc);
    
    assign next_pc = ex_take_trap   ? trap_pc :
                     ex_take_branch ? jump_branch_pc : if_pc + 4;

    // ================= EX/MEM Reg =================
    logic [31:0] mem_alu_res, mem_rs2_data, mem_ret_pc;
    logic [4:0]  mem_rd;
    logic        mem_RegWen, mem_MemWen;
    logic [1:0]  mem_WbSel;
    logic [2:0]  mem_funct3;

    EX_MEM_Reg #(DATAWIDTH) ex_mem_reg (
        .clk(cpu_clk), .rst(cpu_rst), .flush(flush_EX_MEM), .stall(stall_MEM),
        .ex_alu_res(ex_alu_res), 
        .ex_rs2_data(forwarded_rs2), // 极其关键！如果是 Store 指令，存入内存的数据也必须是最新的旁路数据！
        .ex_ret_pc(ex_ret_pc),
        .ex_rd(ex_rd), .ex_RegWen(ex_RegWen), .ex_MemWen(ex_MemWen), .ex_WbSel(ex_WbSel), .ex_funct3(ex_funct3),
        .ex_csr_rdata(ex_csr_rdata),
    
        // Outputs
        .mem_alu_res(mem_alu_res), .mem_rs2_data(mem_rs2_data), .mem_ret_pc(mem_ret_pc),
        .mem_rd(mem_rd), .mem_RegWen(mem_RegWen), .mem_MemWen(mem_MemWen), .mem_WbSel(mem_WbSel), .mem_funct3(mem_funct3),
        .mem_csr_rdata(mem_csr_rdata)
    );

    // ==========================================
    // Stage 4: MEM (Memory Access)
    // ==========================================
    assign perip_addr = mem_alu_res;
    assign perip_wen  = mem_MemWen;    

    StoreAlign #(DATAWIDTH) store_align_inst (
        .addr_offset (mem_alu_res[1:0]),
        .wdata_in    (mem_rs2_data),
        .size_mask   (mem_funct3[1:0]), 
        .MemWrite    (mem_MemWen),
        .wmask_out   (perip_mask),   
        .wdata_out   (perip_wdata)   
    );

    logic [31:0] mem_rdata_align, mem_rdata_ext;
    always_comb begin
        case (mem_funct3) 
            3'b000, 3'b100: mem_rdata_align = perip_rdata >> (8 * mem_alu_res[1:0]);
            3'b001, 3'b101: mem_rdata_align = perip_rdata >> (16 * mem_alu_res[1]);  
            default:        mem_rdata_align = perip_rdata;
        endcase
    end
    
    Mask #(DATAWIDTH) mask_inst (
        .mask   (mem_funct3), 
        .dout   (mem_rdata_align), 
        .mdata  (mem_rdata_ext)
    );

    // ================= MEM/WB Reg =================
    logic [31:0] wb_alu_res, wb_rdata_ext, wb_ret_pc;
    logic [1:0]  wb_WbSel;

    MEM_WB_Reg #(DATAWIDTH) mem_wb_reg (
        .clk(cpu_clk), .rst(cpu_rst), .flush(flush_MEM_WB), .stall(1'b0),
        .mem_alu_res(mem_alu_res), .mem_rdata_ext(mem_rdata_ext), .mem_ret_pc(mem_ret_pc),
        .mem_rd(mem_rd), .mem_RegWen(mem_RegWen), .mem_WbSel(mem_WbSel),
        .mem_csr_rdata(mem_csr_rdata),
        // Outputs
        .wb_alu_res(wb_alu_res), .wb_rdata_ext(wb_rdata_ext), .wb_ret_pc(wb_ret_pc),
        .wb_rd(wb_rd), .wb_RegWen(wb_RegWen), .wb_WbSel(wb_WbSel),
        .wb_csr_rdata(wb_csr_rdata)
    );

    // ==========================================
    // Stage 5: WB (Write Back)
    // ==========================================
    always_comb begin
        case (wb_WbSel) 
            2'b01:   wb_data = wb_ret_pc;     // JAL/JALR
            2'b10:   wb_data = wb_rdata_ext;  // Memory read
            2'b11:   wb_data = wb_csr_rdata;  // CSR
            default: wb_data = wb_alu_res;    // ALU
        endcase
    end

endmodule
