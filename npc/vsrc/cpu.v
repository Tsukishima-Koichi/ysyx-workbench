module cpu(
    input         clk,
    input         rst,
    output [31:0] pc,
    output [31:0] inst
);

    // ==========================================
    // 1. PC 寄存器与跳转控制 (PC MUX)
    // ==========================================
    wire [31:0] pc_math_imm = 
        (is_jal)   ? imm_J :
        (is_jalr)  ? imm_I :
        (is_auipc) ? imm_U :  // auipc 也要用 NPC 里的加法器！
                     imm_B ;  // 分支指令的目标地址也是通过 NPC 计算 PC + imm_B 得到的

    reg  [31:0] pc_reg;
    wire [31:0] next_pc; 

    // 1. 整理你的控制信号
    wire branch_hit = (is_beq  &&  alu_zero)  ||   // 相等则跳
                      (is_bne  && !alu_zero)  ||   // 不等则跳
                      (is_blt  &&  alu_less)  ||   // 有符号小于则跳
                      (is_bge  && !alu_less)  ||   // 有符号大于等于(即不小于)则跳
                      (is_bltu &&  alu_lessu) ||   // 无符号小于则跳
                      (is_bgeu && !alu_lessu);     // 无符号大于等于则跳
    
    wire do_jump = is_jal || is_jalr || branch_hit;

    wire [31:0] out_pc_plus_4;
    wire [31:0] out_pc_plus_imm;

    npc u_npc (
        .pc             (pc),
        .rs1_data       (rs1_data),
        .imm            (pc_math_imm),
        .is_jalr        (is_jalr),
        .do_jump        (do_jump),       // auipc 不会触发 do_jump，所以 PC 还是会乖乖 +4
        .is_ecall       (is_ecall),
        .is_mret        (is_mret),
        .mtvec_val      (mtvec_val),
        .mepc_val       (mepc_val),
        .next_pc        (next_pc),
        .pc_plus_4_out  (out_pc_plus_4), // 接住算好的 PC+4
        .pc_plus_imm    (out_pc_plus_imm)// 接住算好的 PC+imm
    );
    
    always @(posedge clk) begin
        if (rst) pc_reg <= 32'h80000000;
        else     pc_reg <= next_pc;
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
    wire [11:0] funct12 = inst[31:20]; // funct12 来区分 ecall 和 ebreak

    // 立即数提取与扩展
    wire [31:0] imm_U = {inst[31:12], 12'b0};
    wire [31:0] imm_J = {{12{inst[31]}}, inst[19:12], inst[20], inst[30:21], 1'b0};
    wire [31:0] imm_B = {{19{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0};
    wire [31:0] imm_I = {{20{inst[31]}}, inst[31:20]}; 
    wire [31:0] imm_S = {{20{inst[31]}}, inst[31:25], inst[11:7]};
    

    // 指令识别 (真值表)
    // ================= U 型指令 (高位立即数) =================
    // auipc: PC 加高位立即数。PC + imm 写入 rd
    wire is_auipc  = (opcode == 7'b0010111);  
    // lui: 加载高位立即数。将 imm 写入 rd
    wire is_lui    = (opcode == 7'b0110111);

    // ================= J/I 型指令 (无条件跳转) =================
    // jal: 跳转并链接 (J型)。跳到 pc+imm，rd 存入返回地址 pc+4
    wire is_jal    = (opcode == 7'b1101111);
    // jalr: 寄存器跳转并链接 (I型)。跳到 rs1+imm (最低位清零)，rd 存入返回地址 pc+4
    wire is_jalr   = (opcode == 7'b1100111) && (funct3 == 3'b000);

    // ================= B 型指令 (条件分支) =================
    // beq: 相等则跳转
    wire is_beq    = (opcode == 7'b1100011) && (funct3 == 3'b000);
    // bne: 不等则跳转
    wire is_bne    = (opcode == 7'b1100011) && (funct3 == 3'b001);
    // blt: 有符号小于则跳转 (必须强转为 signed)
    wire is_blt    = (opcode == 7'b1100011) && (funct3 == 3'b100);
    // bge: 有符号大于等于则跳转
    wire is_bge    = (opcode == 7'b1100011) && (funct3 == 3'b101);
    // bltu: 无符号小于则跳转 (默认就是 unsigned，直接比)
    wire is_bltu   = (opcode == 7'b1100011) && (funct3 == 3'b110);
    // bgeu: 无符号大于等于则跳转
    wire is_bgeu   = (opcode == 7'b1100011) && (funct3 == 3'b111);

    // ================= Load 指令 (I 型 - 内存读取) =================
    wire is_load   = (opcode == 7'b0000011);
    // lb: 读 1 字节，并进行有符号扩展到 32 位
    wire is_lb     = (opcode == 7'b0000011) && (funct3 == 3'b000);
    // lh: 读 2 字节，并进行有符号扩展到 32 位
    wire is_lh     = (opcode == 7'b0000011) && (funct3 == 3'b001);
    // lw: 读 4 字节
    wire is_lw     = (opcode == 7'b0000011) && (funct3 == 3'b010);
    // lbu: 读 1 字节，无符号扩展 (高位补 0)
    wire is_lbu    = (opcode == 7'b0000011) && (funct3 == 3'b100);
    // lhu: 读 2 字节，无符号扩展 (高位补 0)
    wire is_lhu    = (opcode == 7'b0000011) && (funct3 == 3'b101);

    // ================= Store 指令 (S 型 - 内存写入) =================
    wire is_store  = (opcode == 7'b0100011); // sw, sb
    // sb: 存 1 字节 (最低 8 位)
    wire is_sb     = (opcode == 7'b0100011) && (funct3 == 3'b000);
    // sh: 存 2 字节 (最低 16 位)
    wire is_sh     = (opcode == 7'b0100011) && (funct3 == 3'b001);
    // sw: 存 4 字节 (32 位)
    wire is_sw     = (opcode == 7'b0100011) && (funct3 == 3'b010);

    // ================= ALU 立即数指令 (I 型 - 算术/逻辑) =================
    wire is_calc_itype = (opcode == 7'b0010011);
    // addi: 加立即数
    wire is_addi   = (opcode == 7'b0010011) && (funct3 == 3'b000);
    // slti: 有符号小于立即数置 1 (比较前强制转有符号)
    wire is_slti   = (opcode == 7'b0010011) && (funct3 == 3'b010);
    // sltiu: 无符号小于立即数置 1
    wire is_sltiu  = (opcode == 7'b0010011) && (funct3 == 3'b011);
    // xori: 异或立即数
    wire is_xori   = (opcode == 7'b0010011) && (funct3 == 3'b100);
    // ori: 或立即数
    wire is_ori    = (opcode == 7'b0010011) && (funct3 == 3'b110);
    // andi: 与立即数
    wire is_andi   = (opcode == 7'b0010011) && (funct3 == 3'b111);
    // slli: 逻辑左移 (位移量取 imm 的低 5 位)
    wire is_slli   = (opcode == 7'b0010011) && (funct3 == 3'b001) && (funct7 == 7'b0000000);
    // srli: 逻辑右移 (高位补 0)
    wire is_srli   = (opcode == 7'b0010011) && (funct3 == 3'b101) && (funct7 == 7'b0000000);
    // srai: 算术右移 (高位补符号位，必须强制转有符号再移位)
    wire is_srai   = (opcode == 7'b0010011) && (funct3 == 3'b101) && (funct7 == 7'b0100000);

    // ================= ALU 寄存器指令 (R 型 - 算术/逻辑) =================
    wire is_rtype  = (opcode == 7'b0110011);
    // add: 寄存器加法
    wire is_add    = (opcode == 7'b0110011) && (funct3 == 3'b000) && (funct7 == 7'b0000000);
    // sub: 寄存器减法
    wire is_sub    = (opcode == 7'b0110011) && (funct3 == 3'b000) && (funct7 == 7'b0100000);
    // sll: 逻辑左移 (位移量取 src2 的低 5 位)
    wire is_sll    = (opcode == 7'b0110011) && (funct3 == 3'b001) && (funct7 == 7'b0000000);
    // slt: 有符号小于置 1
    wire is_slt    = (opcode == 7'b0110011) && (funct3 == 3'b010) && (funct7 == 7'b0000000);
    // sltu: 无符号小于置 1
    wire is_sltu   = (opcode == 7'b0110011) && (funct3 == 3'b011) && (funct7 == 7'b0000000);
    // xor: 异或
    wire is_xor    = (opcode == 7'b0110011) && (funct3 == 3'b100) && (funct7 == 7'b0000000);
    // srl: 逻辑右移
    wire is_srl    = (opcode == 7'b0110011) && (funct3 == 3'b101) && (funct7 == 7'b0000000);
    // sra: 算术右移 (高位补符号位)
    wire is_sra    = (opcode == 7'b0110011) && (funct3 == 3'b101) && (funct7 == 7'b0100000);
    // or: 或
    wire is_or     = (opcode == 7'b0110011) && (funct3 == 3'b110) && (funct7 == 7'b0000000);
    // and: 与
    wire is_and    = (opcode == 7'b0110011) && (funct3 == 3'b111) && (funct7 == 7'b0000000);

    // ================= 系统同步指令 (处理系统交互) =================
    /* verilator lint_off UNUSEDSIGNAL */
    // fence: 内存屏障指令 (不涉及 NPC 计算，但也要识别出来)
    wire is_fence = (opcode == 7'b0001111) && 
                    (funct3 == 3'b000) && 
                    (rd == 5'b00000) && 
                    (rs1 == 5'b00000) && 
                    (inst[31:28] == 4'b0000); // 严格校验 fm 字段
    // fence.tso: 特殊内存屏障指令 (同样不涉及 NPC 计算)
    wire is_fence_tso = (opcode == 7'b0001111) && 
                        (funct3 == 3'b000) && 
                        (rd == 5'b00000) && 
                        (rs1 == 5'b00000) && 
                        (inst[31:28] == 4'b1000); // fm = 1000 代表 TSO
    // pause: 暂停指令 (模拟器专用，触发暂停机制，不涉及 NPC 计算)
    wire is_pause = (inst == 32'h0100000F);
    /* verilator lint_off UNUSEDSIGNAL */
    // ecall: 环境调用 (从用户态请求系统服务，触发 Trap 机制)
    wire is_ecall = (opcode == 7'b1110011) && 
                    (funct3 == 3'b000) && 
                    (rd == 5'b00000) && 
                    (rs1 == 5'b00000) && 
                    (funct12 == 12'b0000_0000_0000);
    // ebreak: 环境断点 (调试用，触发 Trap 机制)
    wire is_ebreak = (opcode == 7'b1110011) && 
                     (funct3 == 3'b000) && 
                     (rd == 5'b00000) && 
                     (rs1 == 5'b00000) && 
                     (funct12 == 12'b0000_0000_0001);

    // ================= CSR 读写指令 (Zicsr 扩展) =================
    // funct12 就是我们要读写的 CSR 寄存器地址
    wire [11:0] csr_addr = funct12;

    wire is_csrrw  = (opcode == 7'b1110011) && (funct3 == 3'b001); // 读后写
    wire is_csrrs  = (opcode == 7'b1110011) && (funct3 == 3'b010); // 读后置位 (或)
    wire is_csrrc  = (opcode == 7'b1110011) && (funct3 == 3'b011); // 读后清零 (与非)
    
    // i结尾的指令，把 rs1 字段(inst[19:15]) 当成一个 5位的无符号立即数 (zimm)
    wire is_csrrwi = (opcode == 7'b1110011) && (funct3 == 3'b101); 
    wire is_csrrsi = (opcode == 7'b1110011) && (funct3 == 3'b110);
    wire is_csrrci = (opcode == 7'b1110011) && (funct3 == 3'b111);

    // 统称所有的 CSR 指令
    wire is_csr_instr = is_csrrw | is_csrrs | is_csrrc | is_csrrwi | is_csrrsi | is_csrrci;
    

    // ================= M 扩展指令 (R 型 - 乘除法) =================
    // mul: 乘法 (保留低 32 位，无论有无符号底层位运算结果一样)
    wire is_mul    = (opcode == 7'b0110011) && (funct3 == 3'b000) && (funct7 == 7'b0000001);
    // mulh: 有符号乘法 (取高 32 位，必须强转 64 位 signed)
    wire is_mulh   = (opcode == 7'b0110011) && (funct3 == 3'b001) && (funct7 == 7'b0000001);
    // mulhsu: 有符号乘无符号 (取高 32 位)
    wire is_mulhsu = (opcode == 7'b0110011) && (funct3 == 3'b010) && (funct7 == 7'b0000001);
    // mulhu: 无符号乘法 (取高 32 位，必须强转 64 位 unsigned)
    wire is_mulhu  = (opcode == 7'b0110011) && (funct3 == 3'b011) && (funct7 == 7'b0000001);
    // div: 有符号除法 (包含除零和溢出防御)
    wire is_div    = (opcode == 7'b0110011) && (funct3 == 3'b100) && (funct7 == 7'b0000001);
    // divu: 无符号除法 (包含除零防御)
    wire is_divu   = (opcode == 7'b0110011) && (funct3 == 3'b101) && (funct7 == 7'b0000001);
    // rem: 有符号取模 (包含除零和溢出防御)
    wire is_rem    = (opcode == 7'b0110011) && (funct3 == 3'b110) && (funct7 == 7'b0000001);
    // remu: 无符号取模 (包含除零防御)
    wire is_remu   = (opcode == 7'b0110011) && (funct3 == 3'b111) && (funct7 == 7'b0000001);

    // ==========================================
    // 4. 寄存器堆 (RegFile)
    // ==========================================
    wire reg_wen = is_auipc | is_lui | is_jal | is_jalr | is_load |
                   is_rtype | is_calc_itype |
                   is_csr_instr; 
    wire [31:0] rs1_data, rs2_data, reg_wdata;
    
    regfile u_regfile(
        .clk(clk),
        .rs1(rs1), .rs2(rs2), .rd(rd),
        .wdata(reg_wdata), .wen(reg_wen),
        .rs1_data(rs1_data), .rs2_data(rs2_data)
    );

    // ==========================================
    // 5. ALU (EX 阶段)
    // ==========================================
    // -----------------------------------------
    // ALU 输入 A 侧的选择
    // -----------------------------------------
    wire [31:0] alu_srcA;
    assign alu_srcA = (is_lui) ? 32'b0 :    // lui:   rd = 0 + imm_U
                      rs1_data;             // 其他所有指令(add, addi, load, branch等) 统统用 rs1

    // -----------------------------------------
    // ALU 输入 B 侧的选择
    // -----------------------------------------
    wire [31:0] alu_srcB;
    assign alu_srcB = (is_lui)                  ? imm_U : // U型
                      (is_load || 
                       is_addi || is_slti || is_sltiu || is_xori || is_ori || is_andi || is_slli || is_srli || is_srai) 
                                                ? imm_I : // I型 (纯立即数运算)
                      (is_store)                ? imm_S : // S型
                      rs2_data;                           // R型 (包含 add, sub, branch等所有需要读 rs2 的指令)

    wire [31:0] alu_res;
    
    // 声明 ALU 控制信号
    reg [3:0] alu_ctrl;

    // 在译码阶段生成控制信号
    always @(*) begin
        if (is_lui || is_load || is_store || is_addi || is_add) begin
            alu_ctrl = 4'b0000; // 这些指令都做加法
        end 
        else if (is_sub || is_beq || is_bne) begin
            alu_ctrl = 4'b1000; // 减法
        end
        else if (is_slti || is_slt) begin
            alu_ctrl = 4'b0010; // 有符号比较
        end
        else if (is_sltiu || is_sltu) begin
            alu_ctrl = 4'b0011; // 无符号比较
        end
        else if (is_xori || is_xor) begin
            alu_ctrl = 4'b0100; // 异或
        end
        else if (is_ori || is_or) begin
            alu_ctrl = 4'b0110; // 或
        end
        else if (is_andi || is_and) begin
            alu_ctrl = 4'b0111; // 与
        end
        else if (is_slli || is_sll) begin
            alu_ctrl = 4'b0001; // 逻辑左移
        end
        else if (is_srli || is_srl) begin
            alu_ctrl = 4'b0101; // 逻辑右移
        end
        else if (is_srai || is_sra) begin
            alu_ctrl = 4'b1101; // 算术右移
        end
        else begin
            alu_ctrl = 4'b0000; // 默认
        end
    end

    // 例化 ALU
    wire alu_zero, alu_less, alu_lessu;
    alu u_alu (
        .a        (alu_srcA),
        .b        (alu_srcB),
        .alu_ctrl (alu_ctrl),
        .res      (alu_res),
        .zero     (alu_zero),
        .less     (alu_less),
        .lessu    (alu_lessu)
    );

    // ==========================================
    // 6. 乘除法单元 (MDU)
    // ==========================================
    wire is_m_ext = is_mul | is_mulh | is_mulhsu | is_mulhu | 
                    is_div | is_divu | is_rem    | is_remu;
    wire [31:0] mdu_res;
    mdu u_mdu (
        .a      (rs1_data),
        .b      (rs2_data),
        .funct3 (funct3),
        .res    (mdu_res)
    );

    // ==========================================
    // 7. 数据内存 (MEM 阶段)
    // ==========================================
    wire [3:0] mem_wmask;
    assign mem_wmask = 
        // 1. 如果不是 store 指令，全为 0，绝对不许写
        (!is_store) ? 4'b0000 : 
        // 2. sw: 存 32 位，4 个字节全开
        (is_sw) ? 4'b1111 :
        // 3. sh: 存 16 位 (2 个字节)，看 offset[1] 决定写高半字还是低半字
        (is_sh) ? (mem_offset[1] ? 4'b1100 : 4'b0011) :
        // 4. sb: 存 8 位 (1 个字节)，看 offset 精准打击 4 个字节中的某一个
        (is_sb) ? ( (mem_offset == 2'b00) ? 4'b0001 :
                    (mem_offset == 2'b01) ? 4'b0010 :
                    (mem_offset == 2'b10) ? 4'b0100 :
                                            4'b1000 ) :
        4'b0000; // 默认兜底
    // 将要写的数据广播铺满：
    // 如果是 sb，把 rs2 的最低 8 位复制 4 份
    // 如果是 sh，把 rs2 的最低 16 位复制 2 份
    // 如果是 sw，原样输出
    wire [31:0] mem_wdata_aligned = 
        (is_sb) ? {4{rs2_data[7:0]}}  : 
        (is_sh) ? {2{rs2_data[15:0]}} : 
        (is_sw) ? rs2_data :
                   32'b0; // 其他情况不写内存，数据无所谓，填0更干净

    wire [31:0] mem_rdata;
    dmem u_dmem(
        .clk    (clk),
        .wmask  (mem_wmask),          // 传进去 4 位的精准控制信号
        .addr   (alu_res),            // 访存地址 (注意：在dmem内部，通常会忽略最低2位，只看对齐的字地址)
        .wdata  (mem_wdata_aligned),  // 传进去我们“铺满”对齐好的数据
        .rdata  (mem_rdata)           // 读出来永远是 32 位，让外部去切
    );

    // 1. 提取地址的最低两位，作为偏移量
    wire [1:0] mem_offset = alu_res[1:0];

    // 2. 切割出我们想要的 8位 (Byte)
    wire [7:0] read_byte = 
        (mem_offset == 2'b00) ? mem_rdata[7:0]   :
        (mem_offset == 2'b01) ? mem_rdata[15:8]  :
        (mem_offset == 2'b10) ? mem_rdata[23:16] :
                                mem_rdata[31:24] ;

    // 3. 切割出我们想要的 16位 (Halfword)
    // 注意：半字访问的地址必须是偶数，所以 offset[0] 必定为 0，我们只看 offset[1]
    wire [15:0] read_half = 
        (mem_offset[1] == 1'b0) ? mem_rdata[15:0] :
                                  mem_rdata[31:16];

    // 4. 对切出来的数据进行扩展拼接
    
    // lb: 有符号扩展 8 位 -> 32 位
    wire [31:0] lb_data  = {{24{read_byte[7]}}, read_byte};
    
    // lbu: 无符号扩展 8 位 -> 32 位
    wire [31:0] lbu_data = {24'b0, read_byte};
    
    // lh: 有符号扩展 16 位 -> 32 位
    wire [31:0] lh_data  = {{16{read_half[15]}}, read_half};
    
    // lhu: 无符号扩展 16 位 -> 32 位
    wire [31:0] lhu_data = {16'b0, read_half};

    wire [31:0] final_mem_rdata = 
        (is_lb)  ? lb_data  :
        (is_lh)  ? lh_data  :
        (is_lbu) ? lbu_data :
        (is_lhu) ? lhu_data :
        (is_lw)  ? mem_rdata : // is_lw 的情况，直接原封不动把 32 位全拿走
                   32'b0; // 其他情况不读内存，数据无所谓，填0更干净

    // ==========================================
    // 8. 异常处理
    // ==========================================
    // mret: 从机器模式异常返回
    wire is_mret = (opcode == 7'b1110011) && 
                   (funct3 == 3'b000) && 
                   (funct12 == 12'b0011_0000_0010); // 严格比对 mret 的标志
    wire [31:0] mtvec_val;
    wire [31:0] mepc_val;
    wire [31:0] csr_rdata;

    // -----------------------------------------
    // CSR 写回数据计算逻辑
    // -----------------------------------------
    // 1. 确定操作数：是通用寄存器 rs1 的值，还是 5 位零扩展的立即数？
    wire [31:0] csr_zimm = {27'b0, rs1}; // 把 rs1 字段强行当成 5 位无符号常数
    wire [31:0] csr_op   = (is_csrrwi || is_csrrsi || is_csrrci) ? csr_zimm : rs1_data;

    // 2. 根据指令计算要写给 CSR 的新值 (csr_wdata_calc)
    // 注意：csr_rdata 是从 csr 模块读出的旧值
    wire [31:0] csr_wdata_calc = 
        (is_csrrw || is_csrrwi) ? csr_op                : // RW: 直接覆盖写入
        (is_csrrs || is_csrrsi) ? (csr_rdata | csr_op)  : // RS: 按位置 1 (OR)
        (is_csrrc || is_csrrci) ? (csr_rdata & ~csr_op) : // RC: 按位清 0 (AND NOT)
                                  32'b0;

    // 3. 极其硬核的 RISC-V 细节：什么时候允许写 CSR？
    // RISC-V 规定：如果 rs1=0 (即操作数为0)，且指令是 RS 或 RC（置位或清零），
    // 这种情况下**绝对不能对 CSR 产生写操作**（只读不写）！
    wire csr_wen = is_csr_instr && !( (is_csrrs | is_csrrc | is_csrrsi | is_csrrci) && (rs1 == 5'b0) );

    csr u_csr(
        .clk        (clk),
        .rst        (rst),
        // 软件读写端口全面接通！
        .csr_raddr  (csr_addr),       // 读哪个寄存器
        .csr_waddr  (csr_addr),       // 写哪个寄存器
        .csr_wdata  (csr_wdata_calc), // 刚才算好的新数据
        .csr_wen    (csr_wen),        // 精准控制的写使能
        .csr_rdata  (csr_rdata),      // 读出的旧数据
        
        // 硬件异常端口
        .is_ecall   (is_ecall),
        .current_pc (pc_reg),
        .mtvec_out  (mtvec_val),
        .mepc_out   (mepc_val)
    );

    // ==========================================
    // 9. 数据路由 (写回 WB 阶段)
    // ==========================================
    assign reg_wdata = 
        (is_auipc)            ? out_pc_plus_imm : // auipc 拿走 pc+imm
        (is_jal || is_jalr)   ? out_pc_plus_4   : // 跳转指令 拿走 pc+4
        (is_load)             ? final_mem_rdata : // load 拿走内存数据
        (is_csr_instr)        ? csr_rdata       : // CSR指令把读出的原值写回 rd
        (is_m_ext)            ? mdu_res         :
                                alu_res;          // 其他的一律拿 ALU 数据


    
endmodule
