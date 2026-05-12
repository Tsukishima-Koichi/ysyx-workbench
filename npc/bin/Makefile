# 1. 自动寻找当前目录下所有文件夹中的 irom.coe 和 dram.coe 文件
# 分别查找两种文件并将它们合并到一个列表中，这样写更清晰且兼容性好
IROM_COES := $(shell find . -name "irom.coe")
DRAM_COES := $(shell find . -name "dram.coe")
COE_FILES := $(IROM_COES) $(DRAM_COES)

# 2. 根据找到的 .coe 文件列表，生成对应的 .bin 和 _asm.txt 文件列表
# 例如：test_src/dram.coe -> test_src/dram_asm.txt 和 test_src/dram.bin
BIN_FILES := $(COE_FILES:.coe=.bin)
ASM_FILES := $(COE_FILES:.coe=_asm.txt)

# 默认目标：生成所有的反汇编文件和 bin 文件
all: $(ASM_FILES) $(BIN_FILES)

# 规则 A：如何从 .bin 生成 _asm.txt
# $@ 代表目标文件（_asm.txt），$< 代表第一个依赖文件（.bin）
%_asm.txt: %.bin
	riscv64-elf-objdump -D -b binary -m riscv:rv32 $< > $@
	@echo "已反汇编: $< -> $@"

# 规则 B：如何从 .coe 生成 .bin
# 使用之前写的 python 脚本
# $(dir $<) 是 Makefile 的内置函数，用于提取文件所在的目录部分
%.bin: %.coe coe_to_bin.py
	python coe_to_bin.py $< $(dir $<)
	@echo "已转换: $< -> $@"

# 清理命令：删除所有生成的 .bin 和 _asm.txt 文件
clean:
	rm -f $(shell find . -name "irom.bin")
	rm -f $(shell find . -name "dram.bin")
	rm -f $(shell find . -name "irom_asm.txt")
	rm -f $(shell find . -name "dram_asm.txt")
	@echo "清理完成。"

# 帮助命令
help:
	@echo "用法:"
	@echo "  make       - 自动搜索子目录下的 irom/dram.coe 并生成 .bin 与反汇编文件"
	@echo "  make clean - 删除所有生成的 .bin 和 .txt 文件"
