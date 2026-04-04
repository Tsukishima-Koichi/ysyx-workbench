#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>   // 提供了 open 的声明和 O_RDONLY 等宏的定义
#include <sys/time.h>   // 提供了 gettimeofday 的声明和 struct timeval 的定义

static int evtdev = -1;
static int fbdev = -1;
static int screen_w = 0, screen_h = 0;

static int canvas_w = 0, canvas_h = 0;
static int canvas_x = 0, canvas_y = 0; // 画布相对于屏幕左上角的偏移量（用于居中）
static int fb_fd = -1; // 显存文件的 FD

uint32_t NDL_GetTicks() {
  struct timeval tv;
  // 调用底层的系统调用获取时间
  gettimeofday(&tv, NULL);
  // 将秒和微秒统一转换为毫秒并返回
  return tv.tv_sec * 1000 + tv.tv_usec / 1000;
}

// 我们定义一个全局变量来缓存文件描述符，避免每次都 open
static int evt_fd = -1;

// 读出一条事件信息，写入 buf 中
int NDL_PollEvent(char *buf, int len) {
  // 如果是第一次调用，先打开文件
  if (evt_fd == -1) {
    evt_fd = open("/dev/events", 0, 0);
  }

  // 使用无缓冲的 read 系统调用去读事件
  // 因为底层 events_read 在没有按键时会返回 0，所以这里如果 read > 0 就是读到了
  int ret = read(evt_fd, buf, len);
  if (ret > 0) {
    return 1; // 成功读出有效事件
  }
  
  return 0; // 没有按键事件
}

void NDL_OpenCanvas(int *w, int *h) {
  // 原有的 NWM_APP 逻辑保持不动，并且让它独立闭合
  if (getenv("NWM_APP")) {
    int fbctl = 4;
    fbdev = 5;
    screen_w = *w; screen_h = *h;
    char buf[64];
    int len = sprintf(buf, "%d %d", screen_w, screen_h);
    write(fbctl, buf, len);
    while (1) {
      int nread = read(3, buf, sizeof(buf) - 1);
      if (nread <= 0) continue;
      buf[nread] = '\0';
      if (strcmp(buf, "mmap ok") == 0) break;
    }
    close(fbctl);
  } // <--- 确保 NWM_APP 的括号在这里就彻底结束！

  // 【步骤 1】先打开并解析 /proc/dispinfo，获取屏幕真实的宽高！
  int fd = open("/proc/dispinfo", 0, 0);
  if (fd < 0) {
    printf("Failed to open /proc/dispinfo\n");
    return;
  }
  char buf[64];
  read(fd, buf, sizeof(buf));
  close(fd);
  sscanf(buf, "WIDTH:%d\nHEIGHT:%d\n", &screen_w, &screen_h);

  // 【步骤 2】根据 NDL 规约：如果用户传入的 *w 和 *h 是 0，表示要求全屏
  if (*w == 0 && *h == 0) {
    *w = screen_w;
    *h = screen_h;
  }
  canvas_w = *w;
  canvas_h = *h;
  
  // 【步骤 3】计算居中坐标 (必须在 screen_w 被成功解析出来之后再算！)
  canvas_x = (screen_w - canvas_w) / 2;
  canvas_y = (screen_h - canvas_h) / 2;

  // 【步骤 4】打开真正的显存文件以备绘制
  fb_fd = open("/dev/fb", 0, 0);
}

void NDL_DrawRect(uint32_t *pixels, int x, int y, int w, int h) {
  if (fb_fd == -1) return;

  // 逐行绘制
  for (int i = 0; i < h; i++) {
    // 1. 计算这一行在屏幕上的绝对 Y 坐标和 X 坐标
    int screen_y = canvas_y + y + i;
    int screen_x = canvas_x + x;

    // 2. 计算在 /dev/fb 中的字节偏移量
    int offset = (screen_y * screen_w + screen_x) * 4;

    // 3. 将文件指针拨到对应位置
    lseek(fb_fd, offset, SEEK_SET);

    // 4. 写入这完整一行的数据 (w 个像素，即 w * 4 个字节)
    write(fb_fd, pixels + i * w, w * 4);
  }
}

void NDL_OpenAudio(int freq, int channels, int samples) {
}

void NDL_CloseAudio() {
}

int NDL_PlayAudio(void *buf, int len) {
  return 0;
}

int NDL_QueryAudio() {
  return 0;
}

int NDL_Init(uint32_t flags) {
  if (getenv("NWM_APP")) {
    evtdev = 3;
  }
  return 0;
}
void NDL_Quit() {
}
