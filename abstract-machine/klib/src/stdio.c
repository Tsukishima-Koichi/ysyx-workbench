#include <am.h>
#include <klib.h>
#include <klib-macros.h>
#include <stdarg.h>

#if !defined(__ISA_NATIVE__) || defined(__NATIVE_USE_KLIB__)

// ======================================================================
// 核心输出引擎：vsnprintf
// 所有的 printf, sprintf, snprintf 最终都会调用这个函数。
// 它安全地将解析出的字符写入缓冲区，并严格遵守最大长度 n 的限制。
// ======================================================================
int vsnprintf(char *out, size_t n, const char *fmt, va_list ap) {
  size_t count = 0;
  
  // 辅助宏：向缓冲区安全地写入一个字符。
  // 即便超出了 n，也会继续计数（返回正确的总长度），但不会发生内存越界写。
  #define PUT_CHAR(c) do { \
    if (out != NULL && count < n - 1) { \
      out[count] = (c); \
    } \
    count++; \
  } while (0)

  for (; *fmt != '\0'; fmt++) {
    if (*fmt != '%') {
      PUT_CHAR(*fmt);
      continue;
    }

    fmt++; // 跳过 '%'
    
    // 1. 解析格式修饰符：是否补 0，以及输出宽度 (例如 "%08x" 中的 '0' 和 '8')
    int width = 0;
    char padc = ' ';
    if (*fmt == '0') {
      padc = '0';
      fmt++;
    }
    while (*fmt >= '0' && *fmt <= '9') {
      width = width * 10 + (*fmt - '0');
      fmt++;
    }

    // 2. 解析类型
    switch (*fmt) {
      case 'd': 
      case 'i': { // 有符号十进制
        int val = va_arg(ap, int);
        unsigned int uval;
        if (val < 0) {
          PUT_CHAR('-');
          uval = (unsigned int)(~val + 1); // 安全取反加一
        } else {
          uval = (unsigned int)val;
        }
        
        char buf[32];
        int i = 0;
        if (uval == 0) buf[i++] = '0';
        while (uval > 0) {
          buf[i++] = '0' + (uval % 10);
          uval /= 10;
        }
        while (i < width && i < 32) buf[i++] = padc; // 处理宽度填充
        while (i > 0) PUT_CHAR(buf[--i]);
        break;
      }
      
      case 'u': 
      case 'x': 
      case 'X': 
      case 'p': { // 无符号及十六进制
        unsigned int val = va_arg(ap, unsigned int);
        if (*fmt == 'p') {
          PUT_CHAR('0');
          PUT_CHAR('x');
        }
        int base = (*fmt == 'x' || *fmt == 'X' || *fmt == 'p') ? 16 : 10;
        char *digits = (*fmt == 'X') ? "0123456789ABCDEF" : "0123456789abcdef";
        
        char buf[32];
        int i = 0;
        if (val == 0) buf[i++] = '0';
        while (val > 0) {
          buf[i++] = digits[val % base];
          val /= base;
        }
        while (i < width && i < 32) buf[i++] = padc;
        while (i > 0) PUT_CHAR(buf[--i]);
        break;
      }

      case 's': { // 字符串
        char *s = va_arg(ap, char *);
        if (s == NULL) s = "(null)";
        while (*s != '\0') {
          PUT_CHAR(*s++);
        }
        break;
      }

      case 'c': { // 单个字符
        char c = (char)va_arg(ap, int);
        PUT_CHAR(c);
        break;
      }

      case '%': { // 转义的 %
        PUT_CHAR('%');
        break;
      }

      default: { // 不支持的格式符原样输出
        PUT_CHAR('%');
        if (*fmt) PUT_CHAR(*fmt);
        else fmt--; // 防止字符串提前结束越界
        break;
      }
    }
  }

  // 3. 极其重要：补充字符串结束符
  if (out != NULL && n > 0) {
    out[count < n ? count : n - 1] = '\0';
  }

  #undef PUT_CHAR
  return count;
}

// ======================================================================
// 各种变体函数：它们全都只是套了一层壳，去调用上面的核心引擎
// ======================================================================

int vsprintf(char *out, const char *fmt, va_list ap) {
  // 假设目标缓冲区无限大，传入 -1 转为无符号最大值
  return vsnprintf(out, (size_t)-1, fmt, ap);
}

int sprintf(char *out, const char *fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  int ret = vsprintf(out, fmt, ap);
  va_end(ap);
  return ret;
}

int snprintf(char *out, size_t n, const char *fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  int ret = vsnprintf(out, n, fmt, ap);
  va_end(ap);
  return ret;
}

// 这是你在系统底层打印日志的神器！
int printf(const char *fmt, ...) {
  char buf[2048]; // 设定一个足够大的内部缓冲区
  va_list ap;
  va_start(ap, fmt);
  int ret = vsprintf(buf, fmt, ap); // 先把组装好的字符串放进 buf 里
  va_end(ap);
  
  // 调用 AM 提供的 putch 接口，将字符一个个打印到终端
  for (int i = 0; i < ret; i++) {
    putch(buf[i]);
  }
  return ret;
}

#endif
