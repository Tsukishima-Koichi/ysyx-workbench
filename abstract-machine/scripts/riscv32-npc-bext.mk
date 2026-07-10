# Platform: riscv32-npc with RISC-V Bit-manipulation Extensions (B-ext)
# Supports: Zba, Zbb, Zbc, Zbs, Zbkb, Zbkx

# 1. Include base RISC-V ISA config and NPC platform config
include $(AM_HOME)/scripts/isa/riscv.mk
include $(AM_HOME)/scripts/platform/npc.mk

# 2. Pass architecture header macro
CFLAGS  += -DISA_H=\"riscv/riscv.h\"

# 3. Override: use RV32IM with Zicsr + all 6 B-extensions
COMMON_CFLAGS += -march=rv32im_zicsr_zba_zbb_zbc_zbs_zbkb_zbkx -mabi=ilp32   # overwrite

# 4. Override: output 32-bit ELF
LDFLAGS       += -melf32lriscv                    # overwrite

# 5. Provide libgcc for software emulation of missing hardware ops
LIBGCC = $(shell $(CC) $(CFLAGS) -print-libgcc-file-name)
