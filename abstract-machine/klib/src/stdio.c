#include <am.h>
#include <klib.h>
#include <klib-macros.h>
#include <stdarg.h>

#if !defined(__ISA_NATIVE__) || defined(__NATIVE_USE_KLIB__)

int printf(const char *fmt, ...) {
  panic("Not implemented");
}

int vsprintf(char *out, const char *fmt, va_list ap) {
  panic("Not implemented");
}

int sprintf(char *out, const char *fmt, ...) {
  // 1. 定义一个可变参数列表指针
  va_list ap;
  // 2. 初始化 ap，让它指向 fmt 之后的第一个参数
  va_start(ap, fmt);

  char *str = out; // 使用 str 指针遍历并写入目标数组 out

  // 3. 逐个字符解析格式化字符串 fmt
  for (; *fmt != '\0'; ++fmt) {
    // 如果不是 '%'，说明是普通字符，直接原样复制
    if (*fmt != '%') {
      *str++ = *fmt;
      continue;
    }

    // 遇到 '%'，看下一个字符是什么
    ++fmt;

    switch (*fmt) {
      case 's': { // 处理字符串 (%s)
        // 从可变参数列表中提取下一个类型为 char* 的参数
        char *s = va_arg(ap, char *);
        // 逐个字符复制，直到遇到字符串结束符 '\0'
        while (*s != '\0') {
          *str++ = *s++;
        }
        break;
      }
      
      case 'd': { // 处理十进制有符号整数 (%d)
        // 提取下一个类型为 int 的参数
        int num = va_arg(ap, int);
        
        // 处理负数的情况
        unsigned int unum; // 使用无符号数处理，防止 -2147483648 取绝对值时溢出
        if (num < 0) {
          *str++ = '-';
          unum = (unsigned int)(~num + 1); // 负数转正数的安全做法 (取反加一)
        } else {
          unum = (unsigned int)num;
        }

        // 处理数字 0 的特例
        if (unum == 0) {
          *str++ = '0';
        } else {
          char buf[32]; // 临时缓冲区，用来倒序存放数字字符
          int i = 0;
          // 剥离数字的每一位 (从低位到高位)
          while (unum > 0) {
            buf[i++] = (unum % 10) + '0'; // 取余数并转成 ASCII 字符
            unum /= 10;
          }
          // 因为是从低位开始剥离的，所以要倒序写回 out 中
          while (i > 0) {
            *str++ = buf[--i];
          }
        }
        break;
      }

      case 'c': { // 处理单个字符 (%c) (备用)
        // 在可变参数中，char 会被自动提升为 int，所以这里用 int 提取
        char c = (char)va_arg(ap, int);
        *str++ = c;
        break;
      }

      default: { // 如果是不认识的格式符 (比如 %x，目前还没实现)
        *str++ = '%';
        *str++ = *fmt;
        break;
      }
    }
  }

  // 4. 极其重要：在字符串最后补上结束符 '\0'
  *str = '\0';

  // 5. 清理可变参数列表
  va_end(ap);

  // 返回成功写入的字符总数 (不包含最后的 '\0')
  return str - out;
}

int snprintf(char *out, size_t n, const char *fmt, ...) {
  panic("Not implemented");
}

int vsnprintf(char *out, size_t n, const char *fmt, va_list ap) {
  panic("Not implemented");
}

#endif
