#!/usr/bin/env python3
import sys

def print_led_matrix(hex_string):
    # 1. 将输入的十六进制字符串转为整型，并限制在32位无符号整数范围内
    try:
        num = int(hex_string, 16) & 0xFFFFFFFF
    except ValueError:
        print("输入无效，请输入合法的十六进制数，例如: 0x04887023")
        return

    # 2. 格式化为 32 位长度的二进制字符串，高位补零
    binary_str = f"{num:032b}"
    
    print(f"输入十六进制: {hex_string}")
    print(f"对应二进制: {binary_str[:8]} {binary_str[8:16]} {binary_str[16:24]} {binary_str[24:]}")
    print("-" * 25)
    print("LED 矩阵 (■=亮, □=灭):")
    
    # 3. 按照 4 行 8 列输出矩阵
    for row in range(4):
        row_output = ""
        for col in range(8):
            # 计算当前所在的位索引 (从左向右读取 binary_str)
            bit_index = row * 8 + col
            # 1 为亮，0 为灭
            if binary_str[bit_index] == '1':
                row_output += "■ "
            else:
                row_output += "□ "
        print(row_output)

if __name__ == "__main__":
    # 检查命令行参数的数量
    # sys.argv[0] 是脚本名称本身，sys.argv[1] 是第一个参数
    if len(sys.argv) != 2:
        print("用法: python3 led_check <十六进制数>")
        print("示例: python3 led_check 0x04887023")
        sys.exit(1)
        
    # 获取命令行输入的十六进制数
    input_hex = sys.argv[1]
    print_led_matrix(input_hex)
