# 1. 引入基础 RISC-V 配置和 NPC 平台配置
include $(AM_HOME)/scripts/isa/riscv.mk
include $(AM_HOME)/scripts/platform/npc.mk

# 2. 覆盖默认的交叉编译器 (可选)
# riscv.mk 默认使用的是 riscv64-linux-gnu- 
# 这是一个 64 位编译器，但通过下面的 -march 参数，它可以完美编译 32 位代码。
# 所以我们不再需要特殊的 minirv-gcc 了，直接用系统的原生工具链！

# 3. 核心：重写编译参数 (告诉 GCC 我们是一颗强大的 32 位芯片)
# -march=rv32im_zicsr : 启用 32 位基础整数(I) + 乘除法(M) + CSR寄存器(Zicsr)
# -mabi=ilp32         : 使用标准的 32 位 ABI (32 个完整通用寄存器，不再带 'e')
COMMON_CFLAGS += -march=rv32im_zicsr -mabi=ilp32

# 4. 重写链接参数：指定输出 32 位的 ELF 文件
LDFLAGS       += -melf32lriscv

# 【极其重要】：彻底删除了原本的 AM_SRCS += ... libgcc/div.S 等文件！
# 你的硬件 MDU 现在会直接接管乘除法运算，GCC 会原生生成 mul 和 div 指令，
# 再也不需要那些慢吞吞的软件模拟库了！
