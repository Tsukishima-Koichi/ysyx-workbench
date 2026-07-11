# ============================================================================
# 1. 基础项目配置区
# ============================================================================

# 定义 Verilog 的顶层模块名称
TOPNAME = cpu

# ---- CPU 核心选择 ----
# 用法: make CORE=ori  或  make CORE=z_green
# 可用核心: $(shell ls -d */cpu.sv 2>/dev/null | sed 's|/cpu.sv||')
CORE ?= vsrc
CORE_DIR := $(abspath ./$(CORE))
$(if $(wildcard $(CORE_DIR)/cpu.sv),,$(error "Core '$(CORE)' not found at $(CORE_DIR)/ (expected cpu.sv)"))

# 根据核心名称动态命名构建目录，避免不同核心的编译产物互相覆盖
BUILD_DIR = ./build_$(CORE)
OBJ_DIR = $(BUILD_DIR)/obj_dir
BIN = $(BUILD_DIR)/$(TOPNAME)

# 在 Makefile 解析阶段，自动创建 build 文件夹
$(shell mkdir -p $(BUILD_DIR))

# ============================================================================
# 2. 源代码自动搜刮区
# ============================================================================

# 自动递归搜索 CORE 目录下所有的 .v (Verilog) 和 .sv (SystemVerilog) 源文件
VSRCS = $(shell find $(CORE_DIR) -name "*.v" -or -name "*.sv" | grep -v '_bak')

# 自动递归搜索 csrc 目录下所有的 C/C++ 测试平台源文件
CSRCS = $(shell find $(abspath ./csrc) -name "*.c" -or -name "*.cc" -or -name "*.cpp")

# 显式定义包含目录，解决 `include "defines.sv" 找不到的问题
INC_PATH = $(CORE_DIR)

# ============================================================================
# 3. Verilator 编译参数配置区
# ============================================================================

VERILATOR = verilator

# --- C++ 编译参数与宏定义控制区 ---
# 默认关闭 波形(WAVE) 和 DiffTest(TRACE)，设置最大周期
WAVE ?= 0
TRACE ?= 1
MAX_CYCLES ?= 0

# 将 csrc 目录加入 C++ 的头文件搜索路径
CXXFLAGS = -I$(abspath ./csrc)

# 根据开关，动态生成 GCC 的 -D 参数 (等价于代码里的 #define)
ifeq ($(WAVE), 1)
CXXFLAGS += -DGEN_WAVEFORM
endif

ifeq ($(TRACE), 1)
CXXFLAGS += -DNEMU_TRACE
endif

ifneq ($(MAX_CYCLES), 0)
CXXFLAGS += -DMAX_CYCLES=$(MAX_CYCLES)
endif
# ----------------------------------------

# 核心编译参数融合：
# -Wall: 开启所有警告
# --sv: 支持 SystemVerilog
# -MMD --build -cc: 自动构建依赖并调用 GCC 编译成二进制
# -O3: 开启最高优化
# -I$(INC_PATH): 🌟 告诉 Verilator 去哪里找 `include 的文件
VERILATOR_CFLAGS += -Wall -Wno-fatal --sv -MMD --build -cc -O3 \
					--trace \
                    --x-assign fast --x-initial fast \
                    -I$(INC_PATH) \
					+define+NPC_TEST \
					-Wno-DECLFILENAME \
                    -Wno-UNUSEDSIGNAL \
					-Wno-PROCASSINIT \
					-LDFLAGS -ldl \
					-CFLAGS "$(CXXFLAGS)"  # 🌟 新增：把 C++ 的宏定义和头文件路径传给底层的 GCC
					

# ============================================================================
# 4. 核心编译与运行规则
# ============================================================================
# 新增：定义默认的 bin 文件路径和起始地址 (?= 表示可被终端环境变量覆盖)
IROM_BIN  ?= ./bin/withMext/irom.bin
DRAM_BIN  ?= ./bin/withMext/dram.bin
DRAM_ADDR ?= 80100000

# 默认目标设为 sim
default: sim

# 编译规则：生成最终的可执行二进制文件
# 依赖于所有的 Verilog 和 C++ 文件
$(BIN): $(VSRCS) $(CSRCS)
	@echo "====== 1. Verilating and Compiling ======"
	$(VERILATOR) $(VERILATOR_CFLAGS) \
		--top-module $(TOPNAME) $^ \
		--Mdir $(OBJ_DIR) --exe -o $(abspath $(BIN))

# 运行规则
# $(IMG) 参数用于接收来自 AM 框架传进来的 .bin 镜像路径
sim: $(BIN)
	$(call git_commit, "sim RTL") # DO NOT REMOVE THIS LINE!!!
	@echo "====== 2. Running Simulation ======"
	@$(BIN) $(IMG) -i $(IROM_BIN) -d $(DRAM_BIN) -a $(DRAM_ADDR)

# 清理规则 — 只清理当前核心的构建产物
clean:
	rm -rf $(BUILD_DIR)

# 清理所有核心的构建产物
clean-all:
	rm -rf ./build_*

# 列出可用核心
cores:
	@echo "Available cores:"
	@for d in $$(ls -d */cpu.sv 2>/dev/null | sed 's|/cpu.sv||'); do \
		if [ "$$d" = "$(CORE)" ]; then \
			echo "  $$d  <-- current (CORE=$$d)"; \
		else \
			echo "  $$d"; \
		fi; \
	done
	@echo ""
	@echo "Usage: make CORE=<name>   (default: CORE=vsrc)"

.PHONY: default sim clean clean-all cores

# ============================================================================
# 5. 一生一芯全局追踪与依赖
# ============================================================================

# 必须放在最后：引入外层的 Makefile，激活 git_commit 宏和框架环境变量
include ../Makefile
