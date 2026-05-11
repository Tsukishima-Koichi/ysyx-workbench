`timescale 1ns / 1ps

module ICache #(
    parameter INDEX_BITS = 6, // 6 位 Index 寻址 64 行 (容量 1KB)
    parameter OFFSET_BITS = 4 // 4 位 Offset (每行 16 字节 = 4 条指令)
)(
    input  logic         clk,
    input  logic         rst,

    // --- CPU 流水线前端接口 ---
    input  logic [31:0]  if1_pc,       // IF1 阶段的 PC (用于闲时预取)
    input  logic [31:0]  if2_pc,       // IF2 阶段的 PC (当前真正需要的指令地址)
    input  logic         if2_valid,    // 只有 IF2 指令有效时，才允许触发 Miss
    input  logic         stall_in,     // 来自 CPU 其他模块的停顿 (如 Load-Use)
    output logic [31:0]  cpu_inst,     // 吐给 IF2_ID 寄存器的指令
    output logic         cache_stall,  // 🌟 未命中时，发出全流水线冻结信号！

    // --- 外部只读存储器侧 (复用原有的 32 位 BRAM 接口) ---
    output logic [31:0]  rom_addr,     // 发给外部 BRAM 的地址
    input  logic [31:0]  rom_data      // 外部 BRAM 延迟 1 拍返回的数据
);
    localparam LINE_COUNT = 1 << INDEX_BITS;
    localparam TAG_BITS = 32 - INDEX_BITS - OFFSET_BITS;

    // ========================================
    // 1. 物理地址切割 (Address Decoding)
    // ========================================
    wire [TAG_BITS-1:0]   req_tag  = if2_pc[31 : 32-TAG_BITS];
    wire [INDEX_BITS-1:0] req_idx  = if2_pc[OFFSET_BITS+INDEX_BITS-1 : OFFSET_BITS];
    wire [1:0]            req_word = if2_pc[3:2];

    // ========================================
    // 2. Cache 存储阵列 (FPGA 会自动推断为 LUTRAM/BRAM)
    // ========================================
    logic [127:0]         data_array  [LINE_COUNT-1:0];
    logic [TAG_BITS-1:0]  tag_array   [LINE_COUNT-1:0];
    logic                 valid_array [LINE_COUNT-1:0];

    initial begin
        for (int i = 0; i < LINE_COUNT; i++) valid_array[i] = 1'b0;
    end

    wire [TAG_BITS-1:0] read_tag   = tag_array[req_idx];
    wire                read_valid = valid_array[req_idx];
    wire [127:0]        read_line  = data_array[req_idx];

    // ========================================
    // 3. 命中判定 (Hit Logic)
    // ========================================
    wire hit = read_valid && (read_tag == req_tag);

    // ========================================
    // 4. 缺失重填状态机 (FSM)
    // ========================================
    // 专门针对 1 拍延迟的 BRAM 进行压榨，连续读 4 次凑齐 16 字节
    typedef enum logic [2:0] {
        IDLE,  REQ1,  REQ2,  REQ3,  WAIT1
    } state_t;
    
    state_t state, next_state;
    logic [127:0] buffer; 

    always_ff @(posedge clk) begin
        if (rst) state <= IDLE;
        else     state <= next_state;
    end

    wire [31:0] base_addr = {if2_pc[31:4], 4'b0000}; // 对齐到 16 字节首地址

    always_comb begin
        next_state = state;
        cache_stall = 1'b0;
        // 命中时，像以前一样正常向 BRAM 抛出下一条指令的地址
        rom_addr = stall_in ? if2_pc : if1_pc; 

        case (state)
            IDLE: begin
                // 发生 Miss，且确实是有效指令时触发流水线冻结
                if (!hit && !rst && if2_valid) begin
                    cache_stall = 1'b1;     // 🌟 死死按住 CPU
                    rom_addr  = base_addr;  // 抽取第 1 个字
                    next_state = REQ1;
                end
            end
            REQ1:  begin cache_stall = 1'b1; rom_addr = base_addr + 4;  next_state = REQ2;  end
            REQ2:  begin cache_stall = 1'b1; rom_addr = base_addr + 8;  next_state = REQ3;  end
            REQ3:  begin cache_stall = 1'b1; rom_addr = base_addr + 12; next_state = WAIT1; end
            WAIT1: begin cache_stall = 1'b1; rom_addr = stall_in ? if2_pc : if1_pc; next_state = IDLE;  end
            default: next_state = IDLE;
        endcase
    end

    // 接收 BRAM 延迟 1 拍送回的数据，拼装进 Cache Line
    always_ff @(posedge clk) begin
        if (state == REQ1)  buffer[31:0]   <= rom_data; // 收到字 0
        if (state == REQ2)  buffer[63:32]  <= rom_data; // 收到字 1
        if (state == REQ3)  buffer[95:64]  <= rom_data; // 收到字 2
        if (state == WAIT1) begin
            buffer[127:96] <= rom_data; // 收到字 3
            // 🌟 四字集齐，正式写入 Cache 物理阵列！
            valid_array[req_idx] <= 1'b1;
            tag_array[req_idx]   <= req_tag;
            data_array[req_idx]  <= {rom_data, buffer[95:0]};
        end
    end

    // ========================================
    // 5. 数据输出选择
    // ========================================
    always_comb begin
        if (hit) begin
            case (req_word)
                2'b00: cpu_inst = read_line[31:0];
                2'b01: cpu_inst = read_line[63:32];
                2'b10: cpu_inst = read_line[95:64];
                2'b11: cpu_inst = read_line[127:96];
            endcase
        end else begin
            cpu_inst = 32'h00000013; // Miss 时吐出 NOP (会被 Stall 拦截)
        end
    end
endmodule
