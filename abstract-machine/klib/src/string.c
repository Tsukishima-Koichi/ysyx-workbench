#include <klib.h>
#include <klib-macros.h>
#include <stdint.h>

#if !defined(__ISA_NATIVE__) || defined(__NATIVE_USE_KLIB__)

// 1. 求字符串长度
size_t strlen(const char *s) {
  size_t len = 0;
  while (s[len] != '\0') {
    len++;
  }
  return len;
}

// 2. 字符串拷贝
char *strcpy(char *dst, const char *src) {
  char *d = dst;
  // 连带最后的 '\0' 一起拷贝过去
  while ((*d++ = *src++) != '\0');
  return dst;
}

// 4. 字符串拼接 (hello-str 可能也会用到)
char *strcat(char *dst, const char *src) {
  char *d = dst;
  // 先把指针移动到 dst 的末尾 ('\0' 处)
  while (*d != '\0') {
    d++;
  }
  // 然后开始把 src 拷贝过去
  while ((*d++ = *src++) != '\0');
  return dst;
}

// 3. 字符串比较
int strcmp(const char *s1, const char *s2) {
  // 只要还没遇到结束符，并且两个字符相等，就一直往下走
  while (*s1 != '\0' && *s1 == *s2) {
    s1++;
    s2++;
  }
  // 返回差值（转换为无符号字符比较是为了符合 C 标准）
  return *(unsigned char *)s1 - *(unsigned char *)s2;
}

// 安全字符串拷贝
char *strncpy(char *dst, const char *src, size_t n) {
  size_t i;
  // 拷贝字符，直到遇到 \0 或者达到 n 个
  for (i = 0; i < n && src[i] != '\0'; i++) {
    dst[i] = src[i];
  }
  // 如果 src 长度小于 n，剩余的部分必须全部用 \0 填充
  for (; i < n; i++) {
    dst[i] = '\0';
  }
  return dst;
}

// 安全字符串比较
int strncmp(const char *s1, const char *s2, size_t n) {
  while (n > 0 && *s1 != '\0' && *s1 == *s2) {
    s1++;
    s2++;
    n--;
  }
  if (n == 0) return 0;
  return *(unsigned char *)s1 - *(unsigned char *)s2;
}

// 内存拷贝 (不考虑内存重叠的情况)
void *memcpy(void *out, const void *in, size_t n) {
  char *d = (char *)out;
  const char *s = (const char *)in;
  while (n--) {
    *d++ = *s++;
  }
  return out;
}

// 内存比较
int memcmp(const void *s1, const void *s2, size_t n) {
  const unsigned char *p1 = (const unsigned char *)s1;
  const unsigned char *p2 = (const unsigned char *)s2;
  while (n--) {
    if (*p1 != *p2) {
      return *p1 - *p2;
    }
    p1++;
    p2++;
  }
  return 0;
}

// 内存设置 (通常用来清零，比如 memset(buf, 0, size))
void *memset(void *s, int c, size_t n) {
  unsigned char *p = (unsigned char *)s;
  while (n--) {
    *p++ = (unsigned char)c;
  }
  return s;
}

// 内存移动 (必须处理内存地址重叠的情况，防止覆盖)
void *memmove(void *dst, const void *src, size_t n) {
  char *d = (char *)dst;
  const char *s = (const char *)src;
  if (d < s) {
    // 目标在源的前面，从前往后拷
    while (n--) *d++ = *s++;
  } else if (d > s) {
    // 目标在源的后面，从后往前拷
    d += n;
    s += n;
    while (n--) *--d = *--s;
  }
  return dst;
}

#endif
