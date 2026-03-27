# 1. 引入基础 RISC-V 架构配置和 NPC 平台底层配置
include $(AM_HOME)/scripts/isa/riscv.mk
include $(AM_HOME)/scripts/platform/npc.mk

# 2. 传递架构头文件宏定义 (与 NEMU 保持一致)
CFLAGS  += -DISA_H=\"riscv/riscv.h\"

# 3. 核心：重写编译参数，榨干你的硬件性能
# -march=rv32im_zicsr : 明确告诉 GCC 你的 CPU 支持 32位基础(I) + 硬件乘除法(M) + CSR指令(Zicsr)
# -mabi=ilp32         : 采用标准的 32 位 ABI (不再是阉割版的 ilp32e)
COMMON_CFLAGS += -march=rv32im_zicsr -mabi=ilp32   # overwrite

# 4. 重写链接参数：指定输出 32 位的 ELF 文件
LDFLAGS       += -melf32lriscv                     # overwrite