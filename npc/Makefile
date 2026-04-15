# ============================================================================
# 1. 基础项目配置区
# ============================================================================

# 定义 Verilog 的顶层模块名称
TOPNAME = cpu

# 定义统一的构建输出目录
BUILD_DIR = ./build
OBJ_DIR = $(BUILD_DIR)/obj_dir
BIN = $(BUILD_DIR)/$(TOPNAME)

# 在 Makefile 解析阶段，自动创建 build 文件夹
$(shell mkdir -p $(BUILD_DIR))

# ============================================================================
# 2. 源代码自动搜刮区
# ============================================================================

# 自动递归搜索 vsrc 目录下所有的 .v (Verilog) 和 .sv (SystemVerilog) 源文件
VSRCS = $(shell find $(abspath ./vsrc) -name "*.v" -or -name "*.sv")

# 自动递归搜索 csrc 目录下所有的 C/C++ 测试平台源文件
CSRCS = $(shell find $(abspath ./csrc) -name "*.c" -or -name "*.cc" -or -name "*.cpp")

# = [关键修改] = 显式定义包含目录，解决 `include "defines.sv" 找不到的问题
INC_PATH = $(abspath ./vsrc)

# ============================================================================
# 3. Verilator 编译参数配置区
# ============================================================================

VERILATOR = verilator

# 核心编译参数融合：
# -Wall: 开启所有警告
# --sv: 支持 SystemVerilog
# -MMD --build -cc: 自动构建依赖并调用 GCC 编译成二进制
# -O3: 开启最高优化
# -I$(INC_PATH): 🌟 告诉 Verilator 去哪里找 `include 的文件
VERILATOR_CFLAGS += -Wall --sv -MMD --build -cc -O3 \
					--trace \
                    --x-assign fast --x-initial fast \
                    -I$(INC_PATH) \
					-Wno-DECLFILENAME \
                    -Wno-UNUSEDSIGNAL 
					

# ============================================================================
# 4. 核心编译与运行规则
# ============================================================================

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
	@$(BIN) $(IMG)

# 清理规则
clean:
	rm -rf $(BUILD_DIR)

.PHONY: default sim clean

# ============================================================================
# 5. 一生一芯全局追踪与依赖
# ============================================================================

# 必须放在最后：引入外层的 Makefile，激活 git_commit 宏和框架环境变量
include ../Makefile