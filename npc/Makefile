# ============================================================================
# 1. 基础项目配置区
# ============================================================================

# 定义 Verilog 的顶层模块名称 (目前是第一阶段的 example，后续写 CPU 时改成 cpu 等)
TOPNAME = cpu

# 定义统一的构建输出目录，防止编译产物弄脏源码区
BUILD_DIR = ./build
OBJ_DIR = $(BUILD_DIR)/obj_dir
BIN = $(BUILD_DIR)/$(TOPNAME)

# 在 Makefile 解析阶段，自动创建 build 文件夹
$(shell mkdir -p $(BUILD_DIR))

# ============================================================================
# 2. 源代码自动搜刮区
# ============================================================================

# 自动递归搜索 vsrc 目录下所有的 .v (Verilog) 源文件
VSRCS = $(shell find $(abspath ./vsrc) -name "*.v")

# 自动递归搜索 csrc 目录下所有的 C/C++ 测试平台源文件
CSRCS = $(shell find $(abspath ./csrc) -name "*.c" -or -name "*.cc" -or -name "*.cpp")

# ============================================================================
# 3. Verilator 编译参数配置区
# ============================================================================

VERILATOR = verilator

# 核心编译参数融合：
# -Wall: 极其重要！开启所有警告，帮你抓住位宽不匹配、隐式声明等致命硬件 Bug
# --sv: 支持 SystemVerilog，方便后续写更复杂的模块
# -MMD --build -cc: 翻译并调用底层的 C++ 编译器构建
# -O3 --x-assign fast --x-initial fast: 开启最高优化并加速未知状态的初始化
VERILATOR_CFLAGS += -Wall --sv -MMD --build -cc -O3 --x-assign fast --x-initial fast

# ============================================================================
# 4. 核心编译与运行规则
# ============================================================================

# 默认目标设为 sim，以后只敲 `make` 就能直接跑仿真
default: sim

# 编译规则：生成最终的可执行二进制文件
# 依赖于所有的 .v 和 .cpp 文件，有任何修改都会自动重新增量编译
$(BIN): $(VSRCS) $(CSRCS)
	@echo "====== 1. Verilating and Compiling ======"
	$(VERILATOR) $(VERILATOR_CFLAGS) \
		--top-module $(TOPNAME) $^ \
		--Mdir $(OBJ_DIR) --exe -o $(abspath $(BIN))

# 运行规则（重中之重！）
sim: $(BIN)
	$(call git_commit, "sim RTL") # DO NOT REMOVE THIS LINE!!!
	@echo "====== 2. Running Simulation ======"
	@$(BIN) $(IMG)

# 清理规则：一键删除整个 build 文件夹
clean:
	rm -rf $(BUILD_DIR)

.PHONY: default sim clean

# ============================================================================
# 5. 一生一芯全局追踪与依赖
# ============================================================================

# 必须放在最后：引入外层的 Makefile，激活 git_commit 宏和框架环境变量
include ../Makefile
