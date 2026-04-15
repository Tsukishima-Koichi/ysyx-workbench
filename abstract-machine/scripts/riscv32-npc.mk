# 1. 引入基础 RISC-V 架构配置和 NPC 平台底层配置
include $(AM_HOME)/scripts/isa/riscv.mk
include $(AM_HOME)/scripts/platform/npc.mk

# 2. 传递架构头文件宏定义 (与 NEMU 保持一致)
CFLAGS  += -DISA_H=\"riscv/riscv.h\"

# 3. 核心：重写编译参数
COMMON_CFLAGS += -march=rv32i_zicsr -mabi=ilp32   # overwrite

# 4. 重写链接参数：指定输出 32 位的 ELF 文件
LDFLAGS       += -melf32lriscv                    # overwrite

# 5.在abstract-machine/Makefile中，添加$(shell $(CC) $(CFLAGS) -print-libgcc-file-name)
LIBGCC = $(shell $(CC) $(CFLAGS) -print-libgcc-file-name)