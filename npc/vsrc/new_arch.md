# 15 级非对称解耦流水线架构 (15-Stage Asymmetric Decoupled Pipeline)

## 架构总览

本 CPU 实现了一套面向高频 FPGA 综合的 15 级非对称解耦流水线。前端以 64-bit 双字带宽超前取指，通过指令队列 (IQ) 吸收前后端吞吐差；后端单发射执行，配合 TAGE + NLP 混合分支预测、分布式毒药冲刷网络、全域前递旁路，在所有 37 项 cpu-tests 上功能正确。

```
        前端 F-Block (5 级)                  中端 D-Block            后端 E-Block (8 级)

  ┌──────────────────────────────────┐    ┌─────┐    ┌──────────────────────────────────────────┐
  │ F1      F2       F3     F4   F5 │    │ IQ  │    │ ID  RF  EX1  BR  MEM1 MEM2  MEM3/WB    │
  │ NLP  TAGE-H  BRAM-R  TAGE-M Ovr │───→│2W1R │───→│Dec Fwd ALU  Res  Req  Data Align/ WB  │
  │ 0cy   Hash   Latch   Match  Arb │    │FIFO │    │         MDU            Byte  Commit    │
  └──────────────────────────────────┘    └─────┘    └──────────────────────────────────────────┘
       ↑                                   ↑                    ↑
       │  micro_flush (F5→F1-F4)           │  flush (hard reset) │  br_flush (global poison)
       │  仅冲刷前端 4 级                   │  指针归零            │  全流水线注毒
```

**流水线深度**: 15 级寄存器边界 (F1/F2/F3/F4/F5/IQ/ID/RF/EX1/BR/MEM1/MEM2/WB)，其中 MEM3 为 WB 级内部的纯组合字节对齐逻辑，不打拍。

---

## 一、前端 F-Block (5 级)

### F1 — 取指 + NLP 快径预测

- **取指带宽**: 64-bit 双字并行，单周期抓取 2 条指令 (`pc` 和 `pc+4`)
- **PC 选择器**: 7 路优先级仲裁

| 优先级 | 条件 | 下一 PC |
|--------|------|---------|
| 1 (最高) | `br_take_trap` | `trap_pc` (CSR mtvec) |
| 2 | `br_mispredict` | `br_actual_target` (分支解析结果) |
| 3 | `f5_micro_flush` | `f5_micro_target` (TAGE 仲裁后目标) |
| 4 | `stall_frontend` | `f1_pc_0` (保持) |
| 5 | `nlp_hit` | `nlp_target` (NLP 快径) |
| 6 (最低) | 默认 | `f1_pc_0 + 8` (顺序双字) |

- **NLP (Next-Line Predictor)**: F1 级 0-cycle 组合逻辑读，基于 LUTRAM (`(* ram_style = "distributed" *)`)

| 属性 | 值 |
|------|-----|
| 容量 | 256 条目 (INDEX_BITS=8, PC[9:2] 索引) |
| 条目格式 | `{valid, conf[1:0], tag[7:0], target[31:0]}` (43-bit) |
| 标签 | PC[17:10], 消除同索引不同 PC 的碰撞 |
| 预测门控 | `valid && tag_match && conf >= 1` (至少见过一次) |
| 训练策略 | 仅后向分支 (`target < pc`, 循环回边) |
| 置信度 | 同 tag 重复 taken → +1 (饱和 3); 新/别名 → 1; 微冲刷反馈 → -1 |
| 训练端口 | BR 级: `br_valid & is_control & br_actual_taken` (排除 trap) |

### F2 — BTB 查表 + TAGE 哈希

- **BTB (Branch Target Buffer)**: 同步 BRAM 读 (`(* ram_style = "block" *)`), 1 拍延迟

| 属性 | 值 |
|------|-----|
| 容量 | 1024 条目 (INDEX_BITS=10) |
| 条目 | `{tag[19:0], target[31:0], valid, bht[1:0]}` |
| 预测 | `tag_match && valid && bht[1]` (2-bit 饱和计数器 MSB) |
| 更新 | BR 级: valid+tag+target 写, BHT 2-bit 饱和更新 |

- **预译码**: F2 指令低 7 位 opcode 提取, `f2_is_ctrl_0/1` 门控——非控制流指令强制 `pred_taken=0` 防止 BTB 别名误判
- **无条件跳转检测**: JAL/JALR 阻断同拍第二条指令推入 IQ

- **TAGE 方向预测器**: 后台 4 级流水线 (F2→F3→F4→F5)

| 属性 | 值 |
|------|-----|
| 表数量 | 4 (T0 bimodal, T1-T3 tagged) |
| 每表容量 | 1024 条目 (INDEX_BITS=10, 实例化覆盖默认 8) |
| 条目格式 | `{tag[7:0], ctr[2:0], u[1:0]}` |
| 历史长度 | T0=0 (bimodal), T1=2, T2=8, T3=20 |
| GHR 宽度 | 32-bit, 仅条件分支更新 (`update_ghr = br_IsBranch`) |
| 哈希 | PC 索引 XOR GHR 折叠 (`pc_idx ^ folded_ghr`) |
| 提供者选择 | 最长历史匹配表 (T3 优先 → T0 兜底), T0 无 tag 永匹配 |
| 计数器 | 3-bit 饱和, MSB 决定方向 |
| T0 冷启动 | ctr=3'b011 (弱 taken), 降低早期否决惩罚 |
| **训练流水线** | **S0→S1→S2 三级 (Vivado 时序拆分)** |
| S0 | 锁存更新信息 + 发起 BRAM 读 |
| S1 | Provider 搜索 + 计数器更新 + 预测正确性判定 |
| S2 | Usefulness 更新 + 条目分配 + u 值衰减 + BRAM 写回 |
| 备份队列 | 1-entry (`upd_q_*`), 当 S0 忙碌时吸纳新更新 |

- **TAGE add-gate**: TAGE 仅在 BTB 有有效目标 (`f5_pred_tgt_0 != 0`) 时才允许"新增"taken 预测，防止 T0 bimodal 别名导致非分支指令被误判为 taken 并重定向到垃圾地址

### F3 — BRAM 读锁存

- BTB 数据从 F2→F3 流水寄存器锁存 (tag, target, valid, bht)
- TAGE BRAM 数据从 F2→F3 锁存 (`f3_entry[0..3]`)

### F4 — TAGE 标签匹配

- 并行 Tag Match 计算 (4 表)
- 提供者选择 (最长历史匹配), 结果锁存至 F4→F5 寄存器
- BTB 预测信号 + NLP 命中信号 bypass 至 F4

### F5 — 预测仲裁 + 微冲刷

- **TAGE/BTB 仲裁**:
  ```
  f5_pc0_taken = BTB_taken ? (TAGE_has_provider ? TAGE_pred : 1)   // BTB taken: TAGE 可否决
                            : (TAGE_add_taken)                       // BTB not-taken: TAGE 可新增(需 add-gate)
  ```
- **微冲刷决策** (NLP-aware):
  ```
  f5_micro_flush = (nlp_hit  & ~f5_any_taken) |   // NLP 过度预测 → 回退到顺序
                   (~nlp_hit &  f5_any_taken)      // NLP 漏预测 → 纠正到目标
  ```
- 微冲刷仅毒化 F1-F4 (`poison_F1_F4 = br_flush | f5_micro_flush`), **不动 IQ**
- 冲刷惩罚: 4 拍气泡, 由 IQ 缓冲吸收

---

## 二、中端 D-Block (指令队列 + 译码)

### IQ — 指令队列

| 属性 | 值 |
|------|-----|
| 深度 | 8 条目 |
| 写入 | 双端口 (push_valid_0/1), 单周期最多推入 2 条 |
| 读出 | 单端口 (pop_ready), 每周期最多弹出 1 条 |
| 反压 | `almost_full` (剩余 < 2), 挂起 F1-F5 |
| 硬重置 | `flush` (poison_IQ = br_flush), 读写指针同步归零 |

- push_valid_1 门控: 若第一条指令被预测 taken 或为无条件跳转, 第二条不推入
- IQ 深度 8 → 可吸收 8 拍后端停顿或 2 次前端微冲刷

### ID — 译码

- 单条 32-bit 指令译码
- Control: isBranch, JmpType, RegWen, MemWen, WbSel, AluSrcA/B, CsrWen, CsrImmSel, IsEcall/Ebreak/Mret
- ACTL: ALU 控制码
- IMMGEN: 立即数生成
- 预计算: `branch_target = pc + imm`, `ret_pc = pc + 4`
- 乘除法预解码: `id_is_M = (opcode==OP && funct7==MUL_DIV)`
- 注毒拦截: `id_valid = id_valid_raw & ~poison_ID; id_inst = id_valid ? raw : NOP`

---

## 三、后端 E-Block (8 级)

### RF — 寄存器读取

- 32×32 通用寄存器文件, x0 硬连线为 0
- 写使能门控: `wb_valid & wb_RegWen` (注毒指令被拦截)
- HazardDetectionUnit: 加载-使用冒险检测

| 检测对象 | 信号来源 | 说明 |
|----------|----------|------|
| EX1 级 | `ex1_valid & ex1_RegWen` | 加载指令即将访问内存 |
| BR 级 | `br_valid & br_RegWen` | 加载地址已计算 |
| MEM1 级 | `mem1_valid & mem1_RegWen` | 加载数据未就绪 |

- 检测到冒险 → `hd_stall_RF` 挂起 RF/ID/IQ, `hd_flush_RF_EX1` 向 EX1 注入气泡

### EX1 — 执行

- **前递多路选择器**: 4 路旁路 (优先级递减)

| 编码 | 来源 | 数据 |
|------|------|------|
| 3'b100 | BR | `br_fw_data` |
| 3'b011 | MEM1 | `mem1_fw_data` |
| 3'b010 | MEM2 | `mem2_fw_data` |
| 3'b001 | WB | `wb_data` |
| 3'b000 | RF | `rs_data_raw` (寄存器文件原始值) |

- **ALU**: 组合逻辑, 操作数选择 (AluSrcA: 0/PC/rs1, AluSrcB: rs2/imm)
- **AGU**: 访存地址计算 (`rs1 + imm`)
- **MDU**: 乘除法单元
  - 乘法: DSP 硬核全流水
  - 除法: 多周期迭代状态机
  - `stall_req_mdu = ex1_valid && ex1_is_M && !mdu_done;` → 挂起 RF/ID/IQ
  - MDU 结果与 ALU 结果通过 `ex1_is_M` 选择

### BR — 分支解析

- BranchUnit: 条件分支比较 (equal/less-signed/less-unsigned), 跳转目标计算 (JAL/JALR/trap)
- 分支预测验证:
  ```
  branch_mispredict = br_actual_taken ^ br_pred_taken
  target_mispredict  = br_actual_taken & br_pred_taken & (pred_target != actual_target)
  br_mispredict      = (is_control & (branch | target_mispredict)) | (~is_control & pred_taken)
  ```
- 非控制流指令但被预测 taken → 也触发冲刷 (BTB 别名误判的兜底)
- CSR: ecall/ebreak/mret, CSR 读写 (mstatus/mtvec/mepc/mcause/mscratch)
- `br_take_trap = ecall | ebreak | mret`
- `br_flush = br_take_trap | br_mispredict` → 全局毒药广播

### MEM1 — 访存请求

- 地址/写数据/字节掩码送出 (`perip_addr/wen/mask/wdata`)
- StoreAlign: 根据 `funct3` 和地址偏移生成字节掩码, 对齐写数据

### MEM2 — 访存数据锁存

- `perip_rdata` 锁存, 传递至 WB
- 前递数据: `mem2_fw_data = (WbSel==load) ? perip_rdata : alu/csr/ret_pc`

### MEM3/WB — 字节对齐与写回

- **MEM3**: 纯组合逻辑, 字节/半字提取与符号扩展 (LB/LH/LW/LBU/LHU), 隶属于 WB 不打拍
- **WB**: `wb_data` 写入寄存器文件, `commit_valid/pc` 输出至 DiffTest

---

## 四、分布式毒药冲刷网络

不接入触发器异步复位端, 通过使能端强制清零 `valid` 位实现流水线气泡注入:

| 毒药信号 | 触发条件 | 影响范围 |
|----------|----------|----------|
| `poison_F1_F4` | `br_flush \| f5_micro_flush` | 前端 4 级 |
| `poison_F5` | `br_flush` | F5 级 |
| `poison_IQ` | `br_flush` | 指令队列 (指针硬归零) |
| `poison_ID` | `br_flush` | 译码级 |
| `poison_RF` | `br_flush` | 寄存器读级 |
| `poison_EX1` | `br_flush \| hd_flush_RF_EX1` | 执行级 + 加载冒险气泡 |
| `poison_BR` | `stall_EX1 \| br_flush` | 分支解析级 + MDU 阻塞 |

**状态安全拦截**: 寄存器写使能 `wb_valid & wb_RegWen`, 外设写使能 `mem1_valid & mem1_MemWen`, 均已通过 valid 门控.

**扇出约束**:
- `(* max_fanout = "16" *)` 应用于 `f5_micro_flush` 和 `br_flush`
- `(* equivalent_register_removal = "no" *)` 应用于全部 7 个 `poison_*` 信号

---

## 五、预测器训练汇总

| 预测器 | 训练时机 | 训练条件 | 延迟 |
|--------|----------|----------|------|
| BTB | BR 级 | `br_is_jump_or_branch` | 1 拍 (同步写) |
| BHT (2-bit) | BR 级 | `br_is_jump_or_branch` | 1 拍 (同步写) |
| NLP | BR 级 | `is_control & actual_taken` (仅后向) | 1 拍 (同步写) |
| TAGE 表 | BR 级 | `update_is_branch` (所有分支/跳转) | 3 拍 (S0→S1→S2) |
| TAGE GHR | BR 级 | `update_ghr` (仅条件分支) | 1 拍 (移位) |
| NLP 降级 | F5 级 | `f5_micro_flush & f5_nlp_hit` | 1 拍 (同步写, 可选) |

---

## 六、性能特征

| 属性 | 值 |
|------|-----|
| 流水线深度 | 15 级 |
| 取指带宽 | 64-bit/cycle (双字) |
| 执行带宽 | 32-bit/cycle (单发射) |
| 取指:执行比 | 2:1 |
| 分支预测延迟 (BTB) | 1 拍 (F1→F2) |
| 分支预测延迟 (TAGE) | 4 拍 (F2→F5) |
| 分支误判惩罚 | 9 拍 (F1→BR), 部分由 IQ 吸收 |
| 微冲刷惩罚 | 4 拍, 由 IQ 吸收 |
| IQ 深度 | 8 条目 |
| cpu-tests 验证 | 37/37 通过 |
| 仿真 checksum | `0x378672d7` |
| 仿真周期数 | 778,111,466 cycles |

---

## 七、Vivado 同步状态

TAGE 训练流水线已从 Vivado 工程同步 (S0→S1→S2 时序拆分)。EX1a/EX1b 拆分维持 Vivado 专属 (依赖 `perip_bridge` 的 DRAM 寄存器时序), 不同步至 Verilator 代码库。

BRAM 输出寄存器 (DOA_REG) 当前关闭, BRAM 读延迟 1 拍, 与 Verilator 行为一致。
