make                          # 默认编译 vsrc
make CORE=ori                 # 编译 ori
make cores                    # 列出所有可用核心
make clean CORE=ori           # 清理 ori 构建产物
make clean-all                # 清理所有构建产物
make sim CORE=ori             # 编译并运行 ori


cd am-kernels/tests/b-ext

# 用默认核心 (vsrc) 编译 + 运行全部测试
make ARCH=riscv32-npc-bext run

# 指定核心 z_green 运行全部
make ARCH=riscv32-npc-bext CORE=z_green run

# 指定核心运行 safe 组
make ARCH=riscv32-npc-bext CORE=z_green run-safe

# 指定核心跑单条
make ARCH=riscv32-npc-bext CORE=z_green run-zba_sh1add

# 用 runtest.sh 也一样
CORE=z_green ./runtest.sh
