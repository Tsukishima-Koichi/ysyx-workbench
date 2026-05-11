
`timescale 1ns / 1ps

module DCache #(
    parameter INDEX_BITS = 6, // 64 行 (1KB 容量)
    parameter OFFSET_BITS = 4 // 每行 16 字节
)(
    input  logic         clk,
    input  logic         rst,

    // --- CPU 流水线前端接口 (MEM1 阶段输入) ---
    input  logic         mem1_valid,
    input  logic         mem1_wen,     // 写使能
    input  logic         mem1_ren,     // 是 Load 指令吗？
    input  logic [31:0]  mem1_addr,
    input  logic [31:0]  mem1_wdata,   // 已经对齐铺满的数据
    input  logic [3:0]   mem1_wmask,   // 字节使能掩码

    // --- CPU 流水线后端接口 (MEM2 阶段读取) ---
    input  logic [31:0]  mem2_addr,
    output logic [31:0]  mem2_rdata,   // 吐给 WB 阶段的数据
    
    // --- 全局停顿防线 ---
    output logic         dcache_stall, // 🌟 冻结全流水线报警信号
    input  logic         global_stall, // 监听外界的冻结情况

    // --- 外部物理内存/总线接口 (替代 perip_ ) ---
    output logic [31:0]  mem_addr,
    output logic [31:0]  mem_wdata,
    output logic [3:0]   mem_wmask,
    output logic         mem_wen,
    input  logic [31:0]  mem_rdata     // 外部 BRAM 延迟 1 拍返回的数据
);
    localparam LINE_COUNT = 1 << INDEX_BITS;
    localparam TAG_BITS = 32 - INDEX_BITS - OFFSET_BITS;

    // 🌟 严格依据你的 SoC 内存映射规范定制：
    // 允许缓存：0x800X_XXXX (IROM) 和 0x801X_XXXX (DRAM)
    // 拒绝缓存：0x802X_XXXX (外设 MMIO 区不满足等式，自动退化为透明导线！)
    //wire is_cacheable = (mem1_addr[31:20] == 12'h800) || (mem1_addr[31:20] == 12'h801); 
    //wire mem2_is_cacheable = (mem2_addr[31:20] == 12'h800) || (mem2_addr[31:20] == 12'h801);
    // 🌟 时序极简优化：合并比较器，省下 1 级门电路延迟 (约 0.2ns)
    wire is_cacheable = (mem1_addr[31:21] == 11'h400); 
    wire mem2_is_cacheable = (mem2_addr[31:21] == 11'h400);
    // ========================================
    // 1. 存储阵列 (Vivado 会推断为 LUTRAM，支持异步读)
    // ========================================
    logic [127:0]         data_array  [LINE_COUNT-1:0];
    logic [TAG_BITS-1:0]  tag_array   [LINE_COUNT-1:0];
    logic                 valid_array [LINE_COUNT-1:0];

    initial begin
        for (int i = 0; i < LINE_COUNT; i++) valid_array[i] = 1'b0;
    end

    // ========================================
    // 2. 命中判定 (MEM1 阶段)
    // ========================================
    wire [TAG_BITS-1:0]   mem1_tag  = mem1_addr[31 : 32-TAG_BITS];
    wire [INDEX_BITS-1:0] mem1_idx  = mem1_addr[OFFSET_BITS+INDEX_BITS-1 : OFFSET_BITS];
    wire [1:0]            mem1_word = mem1_addr[3:2];

    wire [TAG_BITS-1:0]   read_tag   = tag_array[mem1_idx];
    wire                  read_valid = valid_array[mem1_idx];
    wire                  hit        = read_valid && (read_tag == mem1_tag) && is_cacheable;

    // ========================================
    // 3. 字节掩码展开 (用于 Write-Through 命中时精准更新)
    // ========================================
    wire [31:0] word_mask = {{8{mem1_wmask[3]}}, {8{mem1_wmask[2]}}, {8{mem1_wmask[1]}}, {8{mem1_wmask[0]}}};
    logic [127:0] write_mask;
    logic [127:0] expanded_wdata;
    
    always_comb begin
        write_mask = 128'b0;
        expanded_wdata = 128'b0;
        case(mem1_word)
            2'b00: begin write_mask[31:0]   = word_mask; expanded_wdata[31:0]   = mem1_wdata; end
            2'b01: begin write_mask[63:32]  = word_mask; expanded_wdata[63:32]  = mem1_wdata; end
            2'b10: begin write_mask[95:64]  = word_mask; expanded_wdata[95:64]  = mem1_wdata; end
            2'b11: begin write_mask[127:96] = word_mask; expanded_wdata[127:96] = mem1_wdata; end
        endcase
    end

    // ========================================
    // 4. 缺失重填状态机 (FSM) - 增加 REQ0 防火墙隔离！
    // ========================================
    // 🌟 新增 REQ0 状态
    typedef enum logic [2:0] { IDLE, REQ0, REQ1, REQ2, REQ3, WAIT1 } state_t;
    state_t state, next_state;
    logic [127:0] buffer;

    // 幽灵连写拦截器保持不变
    logic ghost_write_block;
    always_ff @(posedge clk) begin
        if (rst) begin
            ghost_write_block <= 1'b0;
        end else if (global_stall) begin
            if (mem1_wen) ghost_write_block <= 1'b1;
        end else begin
            ghost_write_block <= 1'b0;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) state <= IDLE;
        else     state <= next_state;
    end

    logic [3:0] addr_offset;

    always_comb begin
        next_state = state;
        dcache_stall = 1'b0;
        
        // 绝杀 1：写使能仅由 IDLE 状态和流水线决定，与 hit 彻底绝缘！
        mem_wen = (state == IDLE) ? (mem1_wen & ~ghost_write_block) : 1'b0;

        // 绝杀 2：默认地址无条件直通低 4 位，在当前周期绝对不附带 hit 信号！
        addr_offset = mem1_addr[3:0]; 

        case (state)
            IDLE: begin
                // 仅对 Cacheable 且未命中的【Load指令】触发冻结搬运
                if (mem1_ren && is_cacheable && !hit && !rst) begin
                    dcache_stall = 1'b1;
                    // 🌟 绝杀点：在这里绝对不修改 addr_offset！
                    // 彻底切断 hit 信号与外部物理地址线之间的组合逻辑牵连！
                    next_state   = REQ0; // 仅改变次态，跳入由 D 触发器隔离的缓冲状态！
                end
            end
            // 🌟 延迟 1 拍后，才开始修改物理地址。此时已受寄存器隔离，0 延迟纯净波形！
            REQ0:  begin dcache_stall = 1'b1; addr_offset = 4'b0000; next_state = REQ1;  end
            REQ1:  begin dcache_stall = 1'b1; addr_offset = 4'b0100; next_state = REQ2;  end
            REQ2:  begin dcache_stall = 1'b1; addr_offset = 4'b1000; next_state = REQ3;  end
            REQ3:  begin dcache_stall = 1'b1; addr_offset = 4'b1100; next_state = WAIT1; end
            WAIT1: begin dcache_stall = 1'b1; addr_offset = mem1_addr[3:0];  next_state = IDLE;  end
            default: next_state = IDLE;
        endcase

        // 拼接成最终发往物理总线的地址（IDLE 时完全不受 hit 拖累）
        mem_addr  = {mem1_addr[31:4], addr_offset};
        // mem_wdata 与 mem_wmask 不变，保持原状
        mem_wdata = mem1_wdata;
        mem_wmask = mem1_wmask;
    end

    // ========================================
    // 5. 存储阵列更新
    // ========================================
    always_ff @(posedge clk) begin
        // 接收从慢速内存搬回来的 4 个字
        if (state == REQ1)  buffer[31:0]  <= mem_rdata;
        if (state == REQ2)  buffer[63:32] <= mem_rdata;
        if (state == REQ3)  buffer[95:64] <= mem_rdata;
        if (state == WAIT1) begin
            buffer[127:96]       <= mem_rdata;
            valid_array[mem1_idx] <= 1'b1;
            tag_array[mem1_idx]   <= mem1_tag;
            data_array[mem1_idx]  <= {mem_rdata, buffer[95:0]}; // 封口拼装
        end 
       // 🌟 同样改用 ghost_write_block
        else if (state == IDLE && mem1_wen && hit && !ghost_write_block) begin
            // 🌟 Write-Update 绝技：命中时，精细到字节只替换脏数据，数据永不过期！
            data_array[mem1_idx] <= (data_array[mem1_idx] & ~write_mask) | (expanded_wdata & write_mask);
        end
    end

    // ========================================
    // 6. 影子保持寄存器 (防止 ICache 冻结导致数据丢失)
    // ========================================
    logic [31:0] uncache_data_reg;
    logic        uncache_data_valid;

    always_ff @(posedge clk) begin
        if (rst) begin
            uncache_data_valid <= 1'b0;
        end else if (global_stall) begin
            if (!uncache_data_valid) begin
                uncache_data_reg <= mem_rdata;
                uncache_data_valid <= 1'b1;
            end
        end else begin
            uncache_data_valid <= 1'b0;
        end
    end

    wire [31:0] safe_mem_rdata = uncache_data_valid ? uncache_data_reg : mem_rdata;

    // ========================================
    // 7. MEM2 阶段 0 拍数据查表直供
    // ========================================
    wire [INDEX_BITS-1:0] mem2_idx  = mem2_addr[OFFSET_BITS+INDEX_BITS-1 : OFFSET_BITS];
    wire [1:0]            mem2_word = mem2_addr[3:2];
    wire [127:0]          mem2_line = data_array[mem2_idx];

    logic [31:0] cache_rdata_comb;
    always_comb begin
        case (mem2_word)
            2'b00: cache_rdata_comb = mem2_line[31:0];
            2'b01: cache_rdata_comb = mem2_line[63:32];
            2'b10: cache_rdata_comb = mem2_line[95:64];
            2'b11: cache_rdata_comb = mem2_line[127:96];
        endcase
    end

    // 🌟 真正的幽灵读取防火墙 (FSM 精确控制版)
    logic [31:0] latched_cache_rdata;
    logic        use_latched_rdata;

    always_ff @(posedge clk) begin
        if (rst) begin
            use_latched_rdata <= 1'b0;
        end else if (state == IDLE && next_state != IDLE) begin
            // 绝杀点：在 D-Cache 确认缺失，即将离开 IDLE 去重填的那一瞬间（此时 SRAM 还没被污染），
            // 立刻把当前绝对正确的组合逻辑读数据死死锁住！
            latched_cache_rdata <= cache_rdata_comb;
            use_latched_rdata   <= 1'b1;
        end else if (state == IDLE) begin
            // 停顿结束，回到正常状态一拍后，解除锁存，恢复纯组合逻辑直通
            use_latched_rdata   <= 1'b0;
        end
    end

    // Stall 期间强行使用被保护好的锁存数据，防止异步读穿透
    wire [31:0] cache_rdata = use_latched_rdata ? latched_cache_rdata : cache_rdata_comb;

    assign mem2_rdata = mem2_is_cacheable ? cache_rdata : safe_mem_rdata;
endmodule
