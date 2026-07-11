make                          # 默认编译 vsrc
make CORE=ori                 # 编译 ori
make CORE=z_green             # 编译 z_green
make CORE=z_red               # 编译 z_red
make cores                    # 列出所有可用核心
make clean CORE=ori           # 清理 ori 构建产物
make clean-all                # 清理所有构建产物
make sim CORE=ori             # 编译并运行 ori
