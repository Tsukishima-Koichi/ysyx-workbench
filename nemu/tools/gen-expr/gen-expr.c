/***************************************************************************************
* Copyright (c) 2014-2024 Zihao Yu, Nanjing University
*
* NEMU is licensed under Mulan PSL v2.
* You can use this software according to the terms and conditions of the Mulan PSL v2.
* You may obtain a copy of Mulan PSL v2 at:
*          http://license.coscl.org.cn/MulanPSL2
*
* THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
* EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
* MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
*
* See the Mulan PSL v2 for more details.
***************************************************************************************/


#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <assert.h>
#include <string.h>

static char buf[65536] = {};
static char code_buf[65536 + 128] = {}; // a little larger than `buf`
static char *code_format =
"#include <stdio.h>\n"
"int main() { "
"  unsigned result = %s; "
"  printf(\"%%u\", result); "
"  return 0; "
"}";

static int pos = 0; // 用于记录当前表达式生成到了 buf 的哪个位置

// 辅助函数：生成 [0, n) 的随机数
static inline uint32_t choose(uint32_t n) {
  return rand() % n;
}

// 辅助函数：随机生成 0~2 个空格，增加 NEMU 词法分析的测试强度
static void gen_space() {
  int spaces = choose(3);
  for (int i = 0; i < spaces; i++) {
    if (pos < 65000) buf[pos++] = ' ';
  }
}

// 核心递归函数：基于 BNF 生成合法表达式
static void gen_rand_expr_internal(int depth) {
  // 1. 终极防御：如果生成的字符串太长，直接截断，防止爆缓冲区
  if (pos > 60000) return;

  // 2. 递归深度控制：如果不加限制，表达式可能会无限嵌套下去导致段错误
  if (depth > 12) {
    gen_space();
    // 生成数字 (为了减少除以 0 的概率，可以稍微避免生成 0，或者直接生成较小的数)
    pos += sprintf(buf + pos, "%uu", choose(100) + 1); 
    gen_space();
    return;
  }

  // 3. 递归生成结构
  switch (choose(3)) {
    case 0: // 生成数字
      gen_space();
      pos += sprintf(buf + pos, "%uu", choose(65535));
      gen_space();
      break;
    case 1: // 生成 ( Expr )
      gen_space();
      buf[pos++] = '(';
      gen_rand_expr_internal(depth + 1);
      buf[pos++] = ')';
      gen_space();
      break;
    default: // 生成 Expr op Expr
      gen_rand_expr_internal(depth + 1);
      gen_space();
      char ops[] = {'+', '-', '*', '/'};
      buf[pos++] = ops[choose(4)];
      gen_space();
      gen_rand_expr_internal(depth + 1);
      break;
  }
}

static void gen_rand_expr() {
  pos = 0;
  gen_rand_expr_internal(0);
  buf[pos] = '\0'; // 千万别忘了给 C 字符串加上结束符
}

int main(int argc, char *argv[]) {
  int seed = time(0);
  srand(seed);
  int loop = 1;
  if (argc > 1) {
    sscanf(argv[1], "%d", &loop);
  }

  int i = 0;
  // 重点 1：将 for 循环改成 while 循环。
  // 因为如果生成的表达式有除以 0 的行为，我们要丢弃它，此时不应该增加计数器 i。
  while (i < loop) { 
    gen_rand_expr();

    sprintf(code_buf, code_format, buf);

    FILE *fp = fopen("/tmp/.code.c", "w");
    assert(fp != NULL);
    fputs(code_buf, fp);
    fclose(fp);

    int ret = system("gcc /tmp/.code.c -Werror -o /tmp/.expr 2>/dev/null");
    if (ret != 0) continue; 

    fp = popen("/tmp/.expr", "r");
    assert(fp != NULL);

    unsigned result; // 重点 2：原版骨架这里是 int，我们必须改成 unsigned
    
    // 重点 3：如何过滤除以 0 的表达式？
    // 如果程序除以 0 崩溃了，fscanf 会读不到任何数据，返回 0 或 EOF。
    ret = fscanf(fp, "%u", &result); 
    
    // pclose 会返回该命令执行的退出状态。如果发生除 0 异常（SIGFPE），返回值不会是 0。
    int pclose_ret = pclose(fp);

    if (ret != 1 || pclose_ret != 0) {
      // 说明这个表达式是个“毒药”（引发了崩溃或读取失败），直接跳过本轮，重新生成！
      continue;
    }

    // ⬇️ 新增这段代码：消除欺骗 GCC 用的 'u' 字符
    for (int j = 0; buf[j] != '\0'; j++) {
        if (buf[j] == 'u') {
            buf[j] = ' '; // 替换成空格，NEMU 会自动忽略它
        }
    }

    // 4. 打印出 结果 和 干净的表达式
    printf("%u %s\n", result, buf);
    i++; 
  }
  return 0;
}










// #include <stdint.h>
// #include <stdio.h>
// #include <stdlib.h>
// #include <time.h>
// #include <assert.h>
// #include <string.h>

// // this should be enough
// static char buf[65536] = {};
// static char code_buf[65536 + 128] = {}; // a little larger than `buf`
// static char *code_format =
// "#include <stdio.h>\n"
// "int main() { "
// "  unsigned result = %s; "
// "  printf(\"%%u\", result); "
// "  return 0; "
// "}";

// static void gen_rand_expr() {
//   buf[0] = '\0';
// }

// int main(int argc, char *argv[]) {
//   int seed = time(0);
//   srand(seed);
//   int loop = 1;
//   if (argc > 1) {
//     sscanf(argv[1], "%d", &loop);
//   }
//   int i;
//   for (i = 0; i < loop; i ++) {
//     gen_rand_expr();

//     sprintf(code_buf, code_format, buf);

//     FILE *fp = fopen("/tmp/.code.c", "w");
//     assert(fp != NULL);
//     fputs(code_buf, fp);
//     fclose(fp);

//     int ret = system("gcc /tmp/.code.c -o /tmp/.expr");
//     if (ret != 0) continue;

//     fp = popen("/tmp/.expr", "r");
//     assert(fp != NULL);

//     int result;
//     ret = fscanf(fp, "%d", &result);
//     pclose(fp);

//     printf("%u %s\n", result, buf);
//   }
//   return 0;
// }
