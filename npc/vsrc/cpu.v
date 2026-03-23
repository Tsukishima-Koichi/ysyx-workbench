module cpu(
    input         clk,
    input         rst,
    output [31:0] pc,
    output [31:0] inst
);

    // ==========================================
    // 1. PC 寄存器与跳转控制 (PC MUX)
    // ==========================================
    reg  [31:0] pc_reg;
    wire [31:0] pc_next; 
    
    always @(posedge clk) begin
        if (rst) pc_reg <= 32'h80000000;
        else     pc_reg <= pc_next;
    end
    assign pc = pc_reg;

    // ==========================================
    // 2. 指令内存 (IF 阶段) - 彻底告别硬连线！
    // ==========================================
    // 实例化刚刚写的 imem，把 PC 传给它，它就会把指令吐出来
    imem u_imem(
        .addr(pc_reg),
        .inst(inst)
    );

    // ==========================================
    // 3. 译码器 (ID 阶段)
    // ==========================================
    wire [6:0]  opcode = inst[6:0];
    wire [4:0]  rd     = inst[11:7];
    wire [2:0]  funct3 = inst[14:12];
    wire [4:0]  rs1    = inst[19:15];
    wire [4:0]  rs2    = inst[24:20];
    wire [6:0]  funct7 = inst[31:25];

    // 立即数提取与扩展
    wire [11:0] immI     = inst[31:20];
    wire [31:0] immI_ext = {{20{immI[11]}}, immI}; 
    wire [31:0] immU_ext = {inst[31:12], 12'b0};
    wire [31:0] immS_ext = {{20{inst[31]}}, inst[31:25], inst[11:7]};

    // 指令识别 (真值表)
    wire is_addi = (opcode == 7'b0010011) && (funct3 == 3'b000);
    wire is_add  = (opcode == 7'b0110011) && (funct3 == 3'b000) && (funct7 == 7'b0000000);
    wire is_lui  = (opcode == 7'b0110111);
    wire is_jalr = (opcode == 7'b1100111) && (funct3 == 3'b000);
    wire is_load = (opcode == 7'b0000011); // lw, lbu
    wire is_store= (opcode == 7'b0100011); // sw, sb

    // ==========================================
    // 4. 寄存器堆 (RegFile)
    // ==========================================
    wire reg_wen = is_addi | is_add | is_lui | is_jalr | is_load; 
    wire [31:0] rdata1, rdata2, final_wdata;
    
    regfile u_regfile(
        .clk(clk),
        .rs1(rs1), .rs2(rs2), .rd(rd),
        .wdata(final_wdata), .wen(reg_wen),
        .rdata1(rdata1), .rdata2(rdata2)
    );

    // ==========================================
    // 5. ALU (EX 阶段)
    // ==========================================
    // 操作数 B 选择 MUX：加法用 rs2，访存用 S型/I型 立即数
    wire [31:0] alu_b = is_add ? rdata2 : (is_store ? immS_ext : immI_ext);
    wire [31:0] alu_res;
    
    alu u_alu(
        .a(rdata1),
        .b(alu_b),
        .res(alu_res)
    );

    // ==========================================
    // 6. 数据内存 (MEM 阶段)
    // ==========================================
    wire [31:0] mem_rdata;
    dmem u_dmem(
        .clk(clk),
        .wen(is_store),                // 是 Store 指令才允许写内存
        .is_byte(funct3 == 3'b000),    // funct3=000 表示字节操作 (sb/lbu)
        .addr(alu_res),                // 访存地址来自 ALU (基址 + 偏移)
        .wdata(rdata2),                // 要存的数据来自 rs2
        .rdata(mem_rdata)
    );

    // ==========================================
    // 7. 核心数据路由 (写回 WB 阶段 & PC 更新)
    // ==========================================
    // 路由 1：下一条 PC 是什么？
    assign pc_next = is_jalr ? ((rdata1 + immI_ext) & 32'hfffffffe) : (pc_reg + 4);

    // 路由 2：写进寄存器的是什么？
    assign final_wdata = 
        is_lui  ? immU_ext :       // lui：U型立即数
        is_jalr ? (pc_reg + 4) :   // jalr：返回地址 PC+4
        is_load ? mem_rdata :      // load：内存读出的数据
                  alu_res;         // 默认 (add/addi)：ALU 计算结果

endmodule
