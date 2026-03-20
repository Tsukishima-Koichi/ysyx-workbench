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

/* We use the POSIX regex functions to process regular expressions.
 * Type 'man regex' for more information about POSIX regex functions.
 */
#include <regex.h>

#include <memory/vaddr.h> // 需要用到虚拟地址读取函数 vaddr_read

#define TOKEN_NUM 65535

enum {
  TK_NOTYPE = 256, TK_EQ,

  /* TODO: Add more token types */
  TK_NUM,       // 十进制整数
  TK_HEX,       // 十六进制整数 (0x...)
  TK_REG,       // 寄存器 (如 $eax, $pc)
  TK_NEQ,       // 不等于 !=
  TK_AND,       // 逻辑与 &&
  TK_DEREF      // 指针解引用 (这个留到后面区分乘号和指针时再处理，目前先不用)

};

static struct rule {
  const char *regex;
  int token_type;
} rules[] = {

  /* TODO: Add more rules.
   * Pay attention to the precedence level of different rules.
   */

  {" +", TK_NOTYPE},    // spaces
  {"\\+", '+'},         // plus
  {"==", TK_EQ},        // equal
  {"-", '-'},                   // 减号
  {"\\*", '*'},                 // 乘号 / 指针解引用
  {"/", '/'},                   // 除号
  {"\\(", '('},                 // 左括号
  {"\\)", ')'},                 // 右括号
  {"!=", TK_NEQ},               // 不等于
  {"&&", TK_AND},               // 逻辑与
  {"0x[0-9a-fA-F]+", TK_HEX},   // 十六进制数 (⚠️ 必须放在十进制数前面！)
  {"[0-9]+", TK_NUM},           // 十进制数
  {"\\$[a-zA-Z0-9]+", TK_REG},  // 寄存器 (以 $ 开头，后面跟字母或数字)
};

#define NR_REGEX ARRLEN(rules)

static regex_t re[NR_REGEX] = {};


/* Rules are used for many times.
 * Therefore we compile them only once before any usage.
 */
void init_regex() {
  int i;
  char error_msg[128];
  int ret;

  for (i = 0; i < NR_REGEX; i ++) {
    ret = regcomp(&re[i], rules[i].regex, REG_EXTENDED);
    if (ret != 0) {
      regerror(ret, &re[i], error_msg, 128);
      panic("regex compilation failed: %s\n%s", error_msg, rules[i].regex);
    }
  }
}

typedef struct token {
  int type;
  char str[32];
} Token;

static Token tokens[TOKEN_NUM] __attribute__((used)) = {};
static int nr_token __attribute__((used))  = 0;

static bool make_token(char *e) {
  int position = 0;
  int i;
  regmatch_t pmatch;

  nr_token = 0;

  while (e[position] != '\0') {
    /* Try all rules one by one. */
    for (i = 0; i < NR_REGEX; i ++) {
      if (regexec(&re[i], e + position, 1, &pmatch, 0) == 0 && pmatch.rm_so == 0) {
        char *substr_start = e + position;
        int substr_len = pmatch.rm_eo;

        // Log("match rules[%d] = \"%s\" at position %d with len %d: %.*s",
        //     i, rules[i].regex, position, substr_len, substr_len, substr_start);

        position += substr_len;

        /* TODO: Now a new token is recognized with rules[i]. Add codes
         * to record the token in the array `tokens'. For certain types
         * of tokens, some extra actions should be performed.
         */

        // 防御性编程：防止表达式太长，超过 tokens 数组的容量 (默认通常是 32)
        if (nr_token >= TOKEN_NUM) {
            panic("Expression is too long, nr_token >= %d!", TOKEN_NUM);
        }

        switch (rules[i].token_type) {
          case TK_NOTYPE:
            // 匹配到了空格。空格在表达式里没有实际计算意义，所以直接忽略，什么都不做
            break;

          case '+':
          case '-':
          case '*':
          case '/':
          case '(':
          case ')':
          case TK_EQ:  // ==
          case TK_NEQ: // !=
          case TK_AND: // &&
            // 对于单纯的符号，我们只需要记住它的“类型”就足够了
            tokens[nr_token].type = rules[i].token_type;
            nr_token++; // 存入成功，Token 数量加 1
            break;

          case TK_NUM:
          case TK_HEX:
          case TK_REG:
            // 对于数字和寄存器，光记住类型不够（比如光知道它是数字，但不知道是 5 还是 10）
            // 所以还要把具体的字符串内容拷贝到 tokens[nr_token].str 里
            tokens[nr_token].type = rules[i].token_type;
            
            // 检查长度，防止越界 (str 数组大小是 32)
            if (substr_len >= 32) {
                panic("Token is too long: %.*s", substr_len, substr_start);
            }
            
            // 将匹配到的内容拷贝进去
            strncpy(tokens[nr_token].str, substr_start, substr_len);
            tokens[nr_token].str[substr_len] = '\0'; // C语言字符串必须以 '\0' 结尾
            
            nr_token++; // 存入成功，Token 数量加 1
            break;

          default: 
            panic("Unknown token type: %d", rules[i].token_type);
        }

        break;
      }
    }

    if (i == NR_REGEX) {
      printf("no match at position %d\n%s\n%*.s^\n", position, e, position, "");
      return false;
    }
  }

  return true;
}

static bool check_parentheses(int p, int q) {
  // 1. 如果最左边不是左括号，或者最右边不是右括号，那它肯定没有被一对大括号完全包围
  if (tokens[p].type != '(' || tokens[q].type != ')') {
    return false;
  }

  int cnt = 0; // 记录括号嵌套的深度（模拟栈）
  
  for (int i = p; i <= q; i++) {
    if (tokens[i].type == '(') {
      cnt++;
    } else if (tokens[i].type == ')') {
      cnt--;
      
      // 2. 核心防坑点：如果在到达最后一个字符之前，cnt 竟然提前归零了！
      // 这说明最左边的括号在半路上就找到了它的另一半，比如 "(1 + 2) * (3 + 4)"
      // 这种情况整个表达式并没有被最外层的一对括号包围，必须返回 false
      if (cnt == 0 && i < q) {
        return false;
      }
    }
  }

  // 3. 扫完整个表达式后，如果深度正好为 0，说明最外层的两个括号完美匹配！
  return cnt == 0;
}

// 辅助函数：定义运算符的优先级
// 返回值越小，说明优先级越低，越可能是主运算符！
static int get_precedence(int type) {
    switch (type) {
        case TK_AND: return 1;           // 逻辑与 && 优先级最低
        case TK_EQ:
        case TK_NEQ: return 2;           // == 和 != 其次
        case '+':
        case '-': return 3;              // 加减法
        case '*':
        case '/': return 4;              // 乘除法优先级较高
        case TK_DEREF: return 5;         // 单目运算符优先级极高
        // 如果是数字、寄存器等，给一个超高优先级，让它永远当不了主运算符
        default: return 100; 
    }
}

static int find_main_op(int p, int q) {
    int op = -1;               // 记录主运算符在 tokens 数组中的下标
    int min_precedence = 100;  // 记录当前扫到的最低优先级
    int depth = 0;             // 模拟括号栈深度

    for (int i = p; i <= q; i++) {
        int type = tokens[i].type;

        // 处理括号嵌套深度
        if (type == '(') {
            depth++;
        } else if (type == ')') {
            depth--;
        } 
        // 只有完全暴露在括号外面的运算符，才有资格竞选主运算符
        else if (depth == 0) {
            // 如果它是个合法的运算符
            if (type == TK_AND || type == TK_EQ || type == TK_NEQ || 
                type == '+' || type == '-' || type == '*' || type == '/' ||
                type == TK_DEREF) {  // <--- 把解引用也放进来！
                
                int prec = get_precedence(type);
                
                // ⚠️ 核心防坑点：注意这里是 <= 而不是 <
                // 因为 1 + 2 + 3 应该被拆成 (1 + 2) 和 3
                // 所以当遇到两个同级的 + 号时，主运算符应该是最右边的那个！
                if (prec <= min_precedence) {
                    min_precedence = prec;
                    op = i;
                }
            }
        }
    }

    // 如果扫完发现没找到合法的运算符（op 还是 -1），说明表达式有问题
    if (op == -1) {
        panic("Cannot find main operator from %d to %d", p, q);
    }

    return op;
}

static word_t eval(int p, int q) {
    if (p > q) {
        /* Bad expression */
        panic("Bad expression: p > q (p=%d, q=%d)", p, q);
    }
    else if (p == q) {
        /* 递归边界：只有一个 Token，这应该是一个数字或寄存器 */
        // TODO: 使用 strtol 函数把 tokens[p].str 转换成数字并返回
        // 记得区分十进制 (TK_NUM) 和十六进制 (TK_HEX)
        // 处理数字和十六进制
        if (tokens[p].type == TK_NUM || tokens[p].type == TK_HEX) {
            return strtol(tokens[p].str, NULL, 0); 
        }
        // ⬇️ 补全寄存器的处理逻辑
        if (tokens[p].type == TK_REG) {
            bool reg_success = true;
            
            // 💡 核心魔法：为什么要 + 1 ？
            // 因为你的正则表达式匹配到的 tokens[p].str 是带有 '$' 的，比如 "$t0"
            // 但 isa_reg_str2val 和 regs 数组里只认 "t0"
            // 在 C 语言里，对字符指针 + 1，就相当于把字符串的开头往后挪了一位，巧妙地跳过了 '$'
            word_t val = isa_reg_str2val(tokens[p].str + 1, &reg_success);
            
            if (!reg_success) {
                panic("Unknown register: %s", tokens[p].str);
            }
            return val;
        }
        
        panic("Unknown single token type: %d", tokens[p].type);
        return 0;
    }
    else if (check_parentheses(p, q) == true) {
        /* 该表达式被一对匹配的括号包围。
         * 此时直接脱去括号，计算里面的表达式。
         */
        return eval(p + 1, q - 1);
    }
    else {
        /* 我们遇到的是一个普通的表达式。
         * 需要找到它的主运算符 (最后一步执行的运算符)。
         */
        int op = find_main_op(p, q);

        // 特殊拦截单目运算符 TK_DEREF
        if (tokens[op].type == TK_DEREF) {
            // 它只有右边，所以我们只去递归计算它右边的值 (代表内存地址)
            word_t addr = eval(op + 1, q);
            // 去该内存地址处读取 4 个字节 (一个 word) 的数据并返回
            return vaddr_read(addr, 4); 
        }
        
        // 分治：递归计算主运算符左边和右边的值
        word_t val1 = eval(p, op - 1);
        word_t val2 = eval(op + 1, q);

        // 根据主运算符的类型，把两边的结果算起来
        switch (tokens[op].type) {
            case '+': return val1 + val2;
            case '-': return val1 - val2;
            case '*': return val1 * val2;
            case '/': 
                if (val2 == 0) panic("Division by zero!");
                return val1 / val2;
            case TK_EQ: return val1 == val2;
            case TK_NEQ: return val1 != val2;
            case TK_AND: return val1 && val2;
            default: panic("Unknown operator type: %d", tokens[op].type);
        }
    }
}

word_t expr(char *e, bool *success) {
  // 1. 词法分析阶段：尝试切分 Token
  if (!make_token(e)) {
    *success = false;
    return 0; // 如果切词失败（比如有不认识的乱码），直接返回并报错
  }

  // 区分乘号和指针解引用
  for (int i = 0; i < nr_token; i++) {
    if (tokens[i].type == '*') {
      // 如果 '*' 是表达式的第一个字符，或者它的前一个字符不是数字、寄存器、右括号
      // 那么它必定是一个指针解引用 (单目运算符)！
      if (i == 0 || (tokens[i - 1].type != TK_NUM && 
                     tokens[i - 1].type != TK_HEX && 
                     tokens[i - 1].type != TK_REG && 
                     tokens[i - 1].type != ')')) {
        tokens[i].type = TK_DEREF;
      }
    }
  }

  // 2. 语法分析与求值阶段：调用递归引擎
  /* * 此时，所有的 token 已经按顺序存放在 tokens 数组中。
   * 数组的有效下标是从 0 到 nr_token - 1。
   * 我们把这个范围传给 eval 函数，让它去帮我们算！
   */
  word_t result = eval(0, nr_token - 1);

  // 3. 收尾工作
  *success = true;  // 告诉调用者："算成功啦！"
  return result;    // 把算出来的最终数字返回出去
}
