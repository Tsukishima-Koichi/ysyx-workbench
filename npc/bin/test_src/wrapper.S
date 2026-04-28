# wrapper.S

# 将 irom.bin 放入名为 .text.irom 的代码段中
.section .text.irom, "ax"  # "ax" 表示 allocate 和 executable (可执行)
.global _start             # 声明入口符号
_start:
    .incbin "irom.bin"

# 将 dram.bin 放入名为 .data.dram 的数据段中
.section .data.dram, "aw"  # "aw" 表示 allocate 和 writable (可写)
    .incbin "dram.bin"
