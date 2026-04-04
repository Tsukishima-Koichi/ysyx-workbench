#include <stdio.h>
#include <NDL.h>

int main() {
  // 根据 NDL 的约定，使用任何功能前必须先初始化
  NDL_Init(0);

  uint32_t start = NDL_GetTicks();
  int count = 0;

  printf("Timer test start! (Using NDL)\n");

  while (1) {
    uint32_t now = NDL_GetTicks();
    
    // 直接使用毫秒级相减，代码逻辑清晰了无数倍
    if (now - start >= 500) {
      printf("Timer report: %d * 0.5s passed\n", ++count);
      start = now;
    }
  }

  // 退出前清理 (虽然这里是死循环执行不到，但保持良好习惯)
  NDL_Quit();
  return 0;
}