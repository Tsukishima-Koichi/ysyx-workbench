Safe：sh1 add  sh2add  sh3add  bset  bclr  binv  bext  bseti  bclri  binvi  bexti  andn  orn  xnor  sext.b  sext.h  orc.b  rev8  brev8  pack  packh  zext.h
Green：rol  ror  rori  max  maxu  min  minu  xperm8
Yellow：clz  ctz  cpop  xperm4
Red：clmul  clmulh clmulr


tests/
├── safe/   (22): sh1add sh2add sh3add bset bclr binv bext bseti bclri binvi bexti
│                  andn orn xnor sext.b sext.h orc.b rev8 brev8 pack packh zext.h
├── green/  (8):  rol ror rori max maxu min minu xperm8
├── yellow/ (4):  clz ctz cpop xperm4
└── red/    (3):  clmul clmulh clmulr

make ARCH=riscv32-npc-bext run-safe     # 只测 Safe
make ARCH=riscv32-npc-bext run-green    # 只测 Green
make ARCH=riscv32-npc-bext run-yellow   # 只测 Yellow
make ARCH=riscv32-npc-bext run-red      # 只测 Red
make ARCH=riscv32-npc-bext run          # 全部




这些指令集前缀（`Zba`、`Zbb`、`Zbc`、`Zbs`、`Zbkb`、`Zbkx`）属于 **RISC-V 指令集架构 (ISA)** 中的两个重要扩展分支：**位操作扩展 (Bit-manipulation Extensions, 简称 B 扩展)** 以及 **标量密码学扩展 (Scalar Cryptography Extensions, 简称 K 扩展)**。

以下将按扩展类别对这些指令集中的具体指令及其功能进行拆解。

---

## 一、 Zba：地址生成扩展 (Address Generation)

此扩展主要用于加速内存地址的计算（如数组索引计算），通过将位移与加法融合为一条指令来替代原有的多指令组合（基于官方《RISC-V Unprivileged ISA Specification》）。

| 指令 / 变体 | 功能描述 | 应用场景 / 备注 |
| --- | --- | --- |
| `sh1add` / `sh2add` / `sh3add` | 将寄存器 `rs1` 的值左移 1、2 或 3 位，然后与 `rs2` 相加 | 常用于数组寻址。例如 `sh2add` 相当于乘以 4 后加基址，适用于 32 位数据寻址 |
| `add.uw` | 将 `rs1` 的低 32 位进行**零扩展 (Zero-extension)** 后与 `rs2` 相加 | **仅限 RV64**。用于在 64 位系统中处理 32 位无符号整数作为索引的场景 |
| `sh1add.uw` / `sh2add.uw` / `sh3add.uw` | 将 `rs1` 的低 32 位零扩展，左移指定位数后与 `rs2` 相加 | **仅限 RV64**。结合了零扩展与位移寻址功能 |

## 二、 Zbb：基础位操作扩展 (Basic Bit-manipulation)

此扩展包含了通用编程中最常用的位级操作，旨在消除软件层面实现这些操作所需的分支和额外循环。指令带有 `w` 后缀的变体（如 `clzw`）专门针对 RV64 环境下对低 32 位数据进行操作。

| 指令 / 变体 | 功能描述 | 应用场景 / 备注 |
| --- | --- | --- |
| `andn` / `orn` / `xnor` | 带取反的逻辑操作（与非、或非、同或） | 例如 `andn` 等价于 `rs1 & ~rs2`，常用于位掩码清除 |
| `clz` / `clzw` | **计算前导零 (Count Leading Zeros)** | 统计从最高位开始到第一个 1 之前的 0 的数量。常用于浮点数归一化、前导零扫描 |
| `ctz` / `ctzw` | **计算尾部零 (Count Trailing Zeros)** | 统计最低位起第一个 1 之前的 0 的数量。常用于位图扫描或快速查表 |
| `cpop` / `cpopw` | **计算置位 (Count Population)** | 统计二进制中 1 的总数（汉明重量），常用于密码学或数据校验 |
| `max` / `maxu` / `min` / `minu` | 求最大值 / 最小值（有符号与无符号版本） | 可替代常规的条件分支语句实现，属于**无分支 (Branchless)** 优化 |
| `sext.b` / `sext.h` / `zext.h` | 符号扩展（字节/半字）与零扩展（半字） | 将 8 位或 16 位的局部数据安全地扩展到整个寄存器宽度 |
| `ror` / `rori` / `rorw` / `roriw` | **循环右移 (Rotate Right)** | 包含寄存器偏移和立即数 (`i`) 偏移版本。溢出的位会重新填补到高位 |
| `rol` / `rolw` | **循环左移 (Rotate Left)** | 循环右移的镜像操作，常用于哈希函数等数据混淆场景 |
| `orc.b` | 字节内按位或结合 (OR Combine) | 如果某个字节内不全为 0，则将该字节所有位设为 1，多用于字符串处理（如快速定位 `NULL` 字节） |
| `rev8` | 字节序反转 (Byte-reverse) | 将寄存器内所有字节顺序颠倒，常用于大小端转换（Endianness swap） |

## 三、 Zbc：无进位乘法扩展 (Carry-less Multiplication)

无进位乘法不执行加法进位，其本质相当于在有限域 GF(2) 上进行多项式乘法，是许多加密和校验算法的核心（如 CRC 校验、GCM 模式中的 GHASH）。

| 指令 / 变体 | 功能描述 | 应用场景 / 备注 |
| --- | --- | --- |
| `clmul` | 无进位乘法，截取并返回乘积的低位部分 | 基础操作，执行两个寄存器的无进位乘积 |
| `clmulh` | 无进位乘法，截取并返回乘积的高位部分 | 配合 `clmul` 使用以获得完整的双倍位宽乘法结果 |
| `clmulr` | 无进位乘法，反转输入位序后计算 | 针对特定标准（如某些特定的 CRC 或密码规范）进行的底层硬件优化 |

## 四、 Zbs：单比特操作扩展 (Single-bit Instructions)

针对寄存器中的某一个独立比特位进行精准控制，后缀带有 `i` 的表示位索引由立即数提供。

| 指令 / 变体 | 功能描述 | 应用场景 / 备注 |
| --- | --- | --- |
| `bset` / `bseti` | **单比特置位 (Bit Set)** | 将指定位置为 1 |
| `bclr` / `bclri` | **单比特清除 (Bit Clear)** | 将指定位置为 0 |
| `binv` / `binvi` | **单比特翻转 (Bit Invert)** | 将指定位的值取反 |
| `bext` / `bexti` | **单比特提取 (Bit Extract)** | 读取指定位的值，并将其放置在目标寄存器的最低位（其余位清零） |

## 五、 Zbkb：密码学基础位操作 (Bit-manipulation for Cryptography)

属于标量密码学规范的一部分。密码学要求指令执行必须是**恒定时间 (Constant-time)** 以抵御时序侧信道攻击。Zbkb 借用了 Zbb 中的部分指令（如 `rev8`, `ror`, `rol`, `andn`, `orn`, `xnor`），并引入了对密码学矩阵或状态块操作极为重要的打包重组指令。

| 指令 / 变体 | 功能描述 | 应用场景 / 备注 |
| --- | --- | --- |
| `pack` | 拼接低半字/字 | 取 `rs1` 的低半部分和 `rs2` 的低半部分，拼合成一个完整的值 |
| `packh` / `packw` | 拼接低字节 / 低半字 | 用于将分散的数据快速组装成密码算法所需的内部状态块格式 |
| `brev8` | **字节内比特反转 (Bit-reverse in bytes)** | 将寄存器中每一个独立的字节内部的 8 个比特顺序全部颠倒 |

## 六、 Zbkx：交叉开关置换扩展 (Crossbar Permutations)

此扩展提供了针对密码学中高频出现的**替换盒 (S-Box)** 操作的硬件级加速，能够实现极高并发度的非线性替换（基于《RISC-V Cryptography Extensions Volume I》）。

| 指令 / 变体 | 功能描述 | 应用场景 / 备注 |
| --- | --- | --- |
| `xperm4` | 基于 4 位半字节 (Nibble) 的置换 | 使用一个寄存器作为控制索引，另一个寄存器作为数据源，并行对所有 4 位块进行重新排列 |
| `xperm8` | 基于 8 位字节 (Byte) 的置换 | 与 `xperm4` 类似，但颗粒度为 8 位。大幅加速如 AES 算法中的 SubBytes (字节替换) 操作，并天然免于缓存侧信道泄露 |
