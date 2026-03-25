#include <am.h>
#include <klib.h>
#include <klib-macros.h>

void test_sprintf() {
  char buf[128];
  
  sprintf(buf, "%d", 0);            assert(strcmp(buf, "0") == 0);
  sprintf(buf, "%d", 123);          assert(strcmp(buf, "123") == 0);
  sprintf(buf, "%d", -123);         assert(strcmp(buf, "-123") == 0);
  sprintf(buf, "%d", 2147483647);   assert(strcmp(buf, "2147483647") == 0);
  sprintf(buf, "%d", -2147483648);  assert(strcmp(buf, "-2147483648") == 0);

  // 测试宽度与补零 (如果你的 klib 实现了的话)
  sprintf(buf, "%04d", 42);         assert(strcmp(buf, "0042") == 0);
  sprintf(buf, "%x", 0x1a2b);       assert(strcmp(buf, "1a2b") == 0 || strcmp(buf, "1A2B") == 0);
  
  // 混合测试
  sprintf(buf, "Score: %d, Name: %s", 100, "NEMU");
  assert(strcmp(buf, "Score: 100, Name: NEMU") == 0);
}

void test_snprintf() {
  char buf[10];
  // n = 5, 实际上只能写 4 个字符 + '\0'
  int ret = snprintf(buf, 5, "HelloWorld");
  assert(strcmp(buf, "Hell") == 0);
  assert(ret == 10); // C标准规定：返回值是如果不受限制原本应该写入的字符数
}

int main() {
  test_sprintf();
  test_snprintf();
  printf("If you can see this, printf is also working!\n");
  printf("[PASS] All stdio tests passed!\n");
  return 0;
}
