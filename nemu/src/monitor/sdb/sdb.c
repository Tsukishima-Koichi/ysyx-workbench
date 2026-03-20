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

#include <isa.h>
#include <cpu/cpu.h>
#include <readline/readline.h>
#include <readline/history.h>
#include "sdb.h"
#include <memory/vaddr.h>  // used to access vaddr_read

static int is_batch_mode = false;

void init_regex();
void init_wp_pool();

/* We use the `readline' library to provide more flexibility to read from stdin. */
static char* rl_gets() {
  static char *line_read = NULL;

  if (line_read) {
    free(line_read);
    line_read = NULL;
  }

  line_read = readline("(nemu) ");

  if (line_read && *line_read) {
    add_history(line_read);
  }

  return line_read;
}

static int cmd_c(char *args) {
  cpu_exec(-1);
  return 0;
}


static int cmd_q(char *args) {
  return -1;
}

static int cmd_help(char *args);

static int cmd_si(char *args);

static int cmd_info(char *args);

static int cmd_x(char *args);

static int cmd_p(char *args);

static int cmd_w(char *args);

static int cmd_d(char *args);

static struct {
  const char *name;
  const char *description;
  int (*handler) (char *);
} cmd_table [] = {
  { "help", "Display information about all supported commands", cmd_help },
  { "c", "Continue the execution of the program", cmd_c },
  { "q", "Exit NEMU", cmd_q },
  
  /* TODO: Add more commands */
  { "si", "Step into instruction", cmd_si },
  { "info", "Print program state (r for registers, w for watchpoints)", cmd_info },
  { "x", "Scan memory: x N EXPR", cmd_x },
  { "p", "Evaluate an expression: p EXPR", cmd_p },
  { "w", "Set a watchpoint: w EXPR", cmd_w },
  { "d", "Delete a watchpoint: d N", cmd_d },

};

#define NR_CMD ARRLEN(cmd_table)

static int cmd_help(char *args) {
  /* extract the first argument */
  char *arg = strtok(NULL, " ");
  int i;

  if (arg == NULL) {
    /* no argument given */
    for (i = 0; i < NR_CMD; i ++) {
      printf("%s - %s\n", cmd_table[i].name, cmd_table[i].description);
    }
  }
  else {
    for (i = 0; i < NR_CMD; i ++) {
      if (strcmp(arg, cmd_table[i].name) == 0) {
        printf("%s - %s\n", cmd_table[i].name, cmd_table[i].description);
        return 0;
      }
    }
    printf("Unknown command '%s'\n", arg);
  }
  return 0;
}

static int cmd_si(char *args) {
  /* executes 1 instruction by default */
  int n = 1; 

  /* args is the string following the command */
  if (args != NULL) {
    /* use strtok to extract the first parameter
     * and use atoi to convert the string into an integer. 
     */
    char *arg = strtok(args, " ");
    if (arg != NULL) {
      n = atoi(arg);
    }
  }

  /* call the function to simulate CPU executing instructions */
  cpu_exec(n);
  return 0;
}

/* declare the underlying register printing function
 * which is defined in another source file
 */
void isa_reg_display();

static int cmd_info(char *args) {
  if (args == NULL) {
    printf("Missing argument for info command\n");
    return 0;
  }

  /* extract the first subcommand argument */
  char *subcmd = strtok(args, " ");

  if (strcmp(subcmd, "r") == 0) {
    /* if it is 'r', call the architecture-specific register printing function */
    isa_reg_display();
  } 
  else if (strcmp(subcmd, "w") == 0) {
    display_watchpoints();
  } 
  else {
    printf("Unknown subcommand '%s' for info\n", subcmd);
  }

  return 0;
}

static int cmd_x(char *args) {
  /* check if arguments are provided */
  if (args == NULL) {
    printf("Missing arguments. Usage: x N EXPR\n");
    return 0;
  }

  /* extract the first argument: N (number of 4-byte words to read) */
  char *n_str = strtok(args, " ");
  if (n_str == NULL) {
    printf("Missing N. Usage: x N EXPR\n");
    return 0;
  }
  int n = atoi(n_str);

  /* extract the second argument: EXPR (starting address) */
  char *expr_str = strtok(NULL, " ");
  if (expr_str == NULL) {
    printf("Missing EXPR. Usage: x N EXPR\n");
    return 0;
  }

  /* * TEMPORARY HACK: 
   * Since we haven't implemented the expression evaluator (expr.c) yet,
   * we simply treat the EXPR string as a hexadecimal address string.
   * Use strtol to convert string (e.g., "0x80000000") to an integer.
   * * TODO: In the future, replace this with:
   * bool success;
   * vaddr_t addr = expr(expr_str, &success);
   * if (!success) return 0;
   */
  vaddr_t addr = strtol(expr_str, NULL, 16);

  /* loop N times to read and print memory */
  int i;
  for (i = 0; i < n; i++) {
    /* read 4 bytes (a word) from the virtual address */
    word_t val = vaddr_read(addr, 4);
    
    /* print the address and the corresponding value in hex format */
    printf("0x%08x:    0x%08x\n", addr, val);
    
    /* move to the next 4-byte memory location */
    addr += 4;
  }

  return 0;
}

static int cmd_p(char *args) {
  if (args == NULL) {
    printf("Missing expression!\n");
    return 0;
  }

  // success 标志位用于接收 expr 函数的解析状态
  bool success = true;
  
  // 调用 expr 求值函数 (目前它里面只有 make_token，还没写递归求值)
  word_t result = expr(args, &success);

  if (success) {
    // 如果解析并求值成功，打印结果（同时打印十进制和十六进制方便看）
    printf("%u\t0x%08x\n", result, result);
  } else {
    // 如果失败（比如正则没匹配上，或者存在语法错误），打印提示
    printf("Bad expression\n");
  }

  return 0;
}

static int cmd_w(char *args) {
  if (args == NULL) {
    printf("Usage: w EXPR\n");
    return 0;
  }
  create_watchpoint(args);
  return 0;
}

static int cmd_d(char *args) {
  if (args == NULL) {
    printf("Usage: d N\n");
    return 0;
  }
  delete_watchpoint(atoi(args));
  return 0;
}

void sdb_set_batch_mode() {
  is_batch_mode = true;
}

void sdb_mainloop() {
  if (is_batch_mode) {
    cmd_c(NULL);
    return;
  }

  for (char *str; (str = rl_gets()) != NULL; ) {
    char *str_end = str + strlen(str);

    /* extract the first token as the command */
    char *cmd = strtok(str, " ");
    if (cmd == NULL) { continue; }

    /* treat the remaining string as the arguments,
     * which may need further parsing
     */
    char *args = cmd + strlen(cmd) + 1;
    if (args >= str_end) {
      args = NULL;
    }

#ifdef CONFIG_DEVICE
    extern void sdl_clear_event_queue();
    sdl_clear_event_queue();
#endif

    int i;
    for (i = 0; i < NR_CMD; i ++) {
      if (strcmp(cmd, cmd_table[i].name) == 0) {
        if (cmd_table[i].handler(args) < 0) { return; }
        break;
      }
    }

    if (i == NR_CMD) { printf("Unknown command '%s'\n", cmd); }
  }
}

void test_expr();

void init_sdb() {
  /* Compile the regular expressions. */
  init_regex();

  /* Initialize the watchpoint pool. */
  init_wp_pool();

  // 正则初始化完之后，立刻开始批量测试
  // test_expr();
}


#include <stdio.h> // 如果没包含的话加上

// 声明一下 expr 函数，防止编译器报隐式声明警告
word_t expr(char *e, bool *success);

void test_expr() {
  // 注意：这里的路径是相对你运行 make run 时所在的 nemu 根目录的
  // 假设你的 input 文件生成在 nemu/tools/gen-expr/input
  FILE *fp = fopen("tools/gen-expr/input", "r"); 
  if (fp == NULL) {
    Log("The test file input was not found. The expression evaluation test was skipped.");
    return;
  }

  uint32_t expected_result;
  char buf[65536]; // 用于存放读取到的表达式字符串
  int test_count = 0;

  Log("开始全自动批量测试表达式求值...");

  // fscanf 的 "%u %[^\n]" 意思是：先读一个无符号整数，然后跳过空格，读剩下的所有字符直到遇到换行符
  while (fscanf(fp, "%u %[^\n]", &expected_result, buf) == 2) {
    bool success;

    // 每次开始算之前，把即将要算的表达式记下来，一旦下面崩溃了，你往上翻一下终端就能看到
    Log("Testing: %s", buf);
    
    // 让 NEMU 去算！
    word_t actual_result = expr(buf, &success);

    // 1. 检查是否成功切词和解析
    if (!success) {
      panic("Test failed! NEMU could not parse the expression.: %s", buf);
    }

    // 2. 检查结果是否正确
    if (actual_result != expected_result) {
      panic("Test failed!\nExpression: %s\nExpected result: %u\nYour result: %u\n", buf, expected_result, actual_result);
    }

    test_count++;
  }

  fclose(fp);
  Log("That's incredible! It passed the %d random expression test perfectly!", test_count);
}