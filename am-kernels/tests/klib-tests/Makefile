# 如果没有传入 WORK 变量，说明当前是“总调度器”模式
ifeq ($(WORK),)

ifeq ($(ALL),)
TESTS = $(basename $(notdir $(wildcard src/*.c)))
else
TESTS = $(ALL)
endif

# 设置默认目标为 run
.DEFAULT_GOAL := run
run all clean gdb: $(TESTS)

$(TESTS): %:
	@echo "=================================================="
	@echo "  🚀 [ $(if $(MAKECMDGOALS),$(MAKECMDGOALS),run) ] test: $@ "
	@echo "=================================================="
	@$(MAKE) -s -f Makefile WORK=$@ $(MAKECMDGOALS)

.PHONY: run all clean gdb $(TESTS)


# 如果传入了 WORK 变量，说明现在是“干活”模式
else

# 在文件内部给 NAME 和 SRCS 赋值，这样绝不会污染底层的子 Makefile！
NAME = $(WORK)
SRCS = src/$(WORK).c

include $(AM_HOME)/Makefile

endif
