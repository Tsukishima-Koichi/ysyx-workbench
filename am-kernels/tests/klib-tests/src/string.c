#include <am.h>
#include <klib.h>
#include <klib-macros.h>

#define N 32
uint8_t data[N];

void reset() {
  for (int i = 0; i < N; i ++) data[i] = i + 1;
}

void check_seq(int l, int r, int val) {
  for (int i = l; i < r; i ++) assert(data[i] == val + i - l);
}

void check_eq(int l, int r, int val) {
  for (int i = l; i < r; i ++) assert(data[i] == val);
}

// ---------------- 写入类 ----------------
void test_memset() {
  for (int l = 0; l < N; l ++) {
    for (int r = l + 1; r <= N; r ++) {
      reset();
      uint8_t val = (l + r) / 2;
      memset(data + l, val, r - l);
      check_seq(0, l, 1);
      check_eq(l, r, val);
      check_seq(r, N, r + 1);
    }
  }
}

void test_memcpy() {
  uint8_t src[N];
  for (int i = 0; i < N; i++) src[i] = i + 100;
  for (int l = 0; l < N; l ++) {
    for (int r = l + 1; r <= N; r ++) {
      reset();
      memcpy(data + l, src, r - l);
      check_seq(0, l, 1);
      for (int i = l; i < r; i ++) assert(data[i] == src[i - l]);
      check_seq(r, N, r + 1);
    }
  }
}

void test_memmove() {
  // 测试区间重叠 (向前拷贝和向后拷贝)
  reset();
  memmove(data + 5, data, 10); // 源 < 目标
  for (int i = 0; i < 10; i++) assert(data[5 + i] == i + 1);
  
  reset();
  memmove(data, data + 5, 10); // 源 > 目标
  for (int i = 0; i < 10; i++) assert(data[i] == i + 6);
}

void test_strcpy_strcat() {
  char buf[N];
  strcpy(buf, "Hello");
  assert(buf[0]=='H' && buf[4]=='o' && buf[5]=='\0');
  
  strcat(buf, " World");
  assert(strcmp(buf, "Hello World") == 0);

  strncpy(buf, "Hi", 10);
  assert(buf[0]=='H' && buf[1]=='i' && buf[2]=='\0');
}

// ---------------- 读取类 ----------------
void test_strcmp_memcmp_strlen() {
  assert(strlen("") == 0);
  assert(strlen("ysyx") == 4);

  assert(strcmp("abc", "abc") == 0);
  assert(strcmp("abc", "abd") < 0);
  assert(strcmp("abd", "abc") > 0);
  assert(strncmp("abcd", "abce", 3) == 0);
  assert(strncmp("abcd", "abce", 4) < 0);

  uint8_t a[] = {1, 2, 3};
  uint8_t b[] = {1, 2, 4};
  assert(memcmp(a, a, 3) == 0);
  assert(memcmp(a, b, 2) == 0);
  assert(memcmp(a, b, 3) < 0);
}

int main() {
  test_memset();
  test_memcpy();
  test_memmove();
  test_strcpy_strcat();
  test_strcmp_memcmp_strlen();
  printf("[PASS] All string/memory tests passed!\n");
  return 0;
}
