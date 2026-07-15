# Makefile for B-Extension Per-Instruction Tests (39 total)
#
# 用法:
#   make ARCH=riscv32-npc-bext                  # 编译全部
#   make ARCH=riscv32-npc-bext run              # 编译全部 + NPC difftest 运行全部
#   make ARCH=riscv32-npc-bext CORE=vsrc run    # 指定核心
#   make ARCH=riscv32-npc-bext zba_sh1add       # 编译一条
#   make ARCH=riscv32-npc-bext run-zba_sh1add   # 编译 + 运行一条
#   make clean

.PHONY: all run clean help

RESULT_FILE = .result

COLOR_RED    = \033[1;31m
COLOR_GREEN  = \033[1;32m
COLOR_YELLOW = \033[1;33m
COLOR_NONE   = \033[0m

ALL_TESTS = $(notdir $(basename $(shell find tests/. -name "*.c" 2>/dev/null)))
TOTAL     = $(words $(ALL_TESTS))

WS_ROOT  = $(abspath ../../..)
NPC_DIR  = $(WS_ROOT)/npc
CORE     ?= vsrc
NPC_BIN  = $(NPC_DIR)/build_$(CORE)/cpu
TIMEOUT  ?= 8

# ======================= 编译 =======================
all: $(addprefix Makefile., $(ALL_TESTS))
	@echo ""
	@echo "========== Build (compile only) =========="
	@passed=$$(grep -c 'OK' $(RESULT_FILE) 2>/dev/null); \
	failed=$$(grep -c 'FAIL' $(RESULT_FILE) 2>/dev/null); \
	[ -z "$$passed" ] && passed=0; [ -z "$$failed" ] && failed=0; \
	cat $(RESULT_FILE); \
	echo "-------------------------------------------"; \
	if [ "$$failed" -eq 0 ]; then \
		printf "$(COLOR_GREEN)%d compiled OK$(COLOR_NONE)\n" $(TOTAL); \
	else \
		printf "$(COLOR_GREEN)%d compiled$(COLOR_NONE), $(COLOR_RED)%d failed$(COLOR_NONE)\n" $$passed $$failed; \
	fi
	@rm -f $(RESULT_FILE)

$(ALL_TESTS): %: Makefile.%

Makefile.%:
	@src=$$(find tests -name "$*.c" 2>/dev/null | head -1); \
	if [ -z "$$src" ]; then echo "ERROR: $*.c not found"; exit 1; fi; \
	/bin/echo -e "NAME = $*\nSRCS = $$src\ninclude \$${AM_HOME}/Makefile" > $@
	@if make -s -f $@ ARCH=$(ARCH) 2>/dev/null; then \
		printf "[%20s] $(COLOR_GREEN)BUILD OK$(COLOR_NONE)\n" $* | tee -a $(RESULT_FILE); \
	else \
		printf "[%20s] $(COLOR_RED)BUILD FAIL$(COLOR_NONE)\n" $* | tee -a $(RESULT_FILE); \
	fi
	@rm -f Makefile.$*

# ======================= 运行一条 =======================
define RUN_ONE
run-$(1): $(1)
	@bin="$$(pwd)/build/$(1)-riscv32-npc-bext.bin"; \
	result=$$$$(cd $(NPC_DIR) && timeout $(TIMEOUT) $(NPC_BIN) "$$$$bin" 2>&1); \
	if   echo "$$$$result" | grep -q 'GOOD TRAP';      then printf "[$(1)] $(COLOR_GREEN)PASS$(COLOR_NONE)\n"; \
	elif echo "$$$$result" | grep -q 'DiffTest Error';  then printf "[$(1)] $(COLOR_RED)FAIL (difftest)$(COLOR_NONE)\n"; \
	elif echo "$$$$result" | grep -q 'BAD TRAP';        then printf "[$(1)] $(COLOR_RED)FAIL (bad trap)$(COLOR_NONE)\n"; \
	elif echo "$$$$result" | grep -q 'TIMEOUT';         then printf "[$(1)] $(COLOR_YELLOW)TIMEOUT$(COLOR_NONE)\n"; \
	else printf "[$(1)] ?\n"; fi
endef

$(foreach t,$(ALL_TESTS),$(eval $(call RUN_ONE,$(t))))

# ======================= 运行全部 =======================
run: all
	@echo ""
	@echo "========== NPC Difftest Results =========="
	@passed=0; failed=0; failed_list=""; self=$$(pwd); \
	for t in $(ALL_TESTS); do \
		bin="$$self/build/$$t-riscv32-npc-bext.bin"; \
		if [ ! -f "$$bin" ]; then printf "[$$t] SKIP (no bin)\n"; continue; fi; \
		cd $(NPC_DIR) && result=$$(timeout $(TIMEOUT) $(NPC_BIN) "$$bin" 2>&1); \
		if   echo "$$result" | grep -q 'GOOD TRAP';      then printf "[$$t] $(COLOR_GREEN)PASS$(COLOR_NONE)\n"; passed=$$((passed+1)); \
		elif echo "$$result" | grep -q 'DiffTest Error';  then printf "[$$t] $(COLOR_RED)FAIL$(COLOR_NONE)\n"; failed=$$((failed+1)); failed_list="$$failed_list $$t"; \
		elif echo "$$result" | grep -q 'BAD TRAP';        then printf "[$$t] $(COLOR_RED)FAIL$(COLOR_NONE)\n"; failed=$$((failed+1)); failed_list="$$failed_list $$t"; \
		elif echo "$$result" | grep -q 'TIMEOUT';         then printf "[$$t] $(COLOR_YELLOW)TIMEOUT$(COLOR_NONE)\n"; failed=$$((failed+1)); \
		else printf "[$$t] ?\n"; failed=$$((failed+1)); fi; \
		cd "$$self"; \
	done; \
	echo "-------------------------------------------"; \
	printf "$(COLOR_GREEN)%d passed$(COLOR_NONE)" $$passed; \
	if [ $$failed -gt 0 ]; then \
		printf ", $(COLOR_RED)%d failed$(COLOR_NONE)\n" $$failed; \
		echo "Need work:$$failed_list"; \
	else \
		echo ", 0 failed"; \
	fi

clean:
	rm -rf Makefile.* build/ $(RESULT_FILE)

help:
	@echo "B-Extension Tests ($(TOTAL) tests)"
	@echo ""
	@echo "Tests:"
	@for t in $(ALL_TESTS); do echo "  $$t"; done | sort | column
	@echo ""
	@echo "Usage:"
	@echo "  make ARCH=riscv32-npc-bext run        全部编译 + 运行"
	@echo "  make ARCH=riscv32-npc-bext CORE=vsrc run  指定核心"
	@echo "  make ARCH=riscv32-npc-bext zba_sh1add 编译一条"
	@echo "  make ARCH=riscv32-npc-bext run-zba_sh1add 编译+运行一条"
	@echo "  make clean"
