// nemu/src/utils/trace.c (或者相关文件)
#include <common.h>

#define IRINGBUF_SIZE 16    // 维护最近 16 条指令
#define MAX_LOG_LEN 128     // 每条指令的最大日志长度

// 定义环形缓冲区
typedef struct {
    char log[MAX_LOG_LEN];
} Iringbuf;

static Iringbuf iringbuf[IRINGBUF_SIZE];
static int iringbuf_index = 0;   // 当前写入的位置
static bool iringbuf_full = false; // 缓冲区是否已写满一圈

// 1. 记录指令到环形缓冲区
void record_iringbuf(char *logbuf) {
    // 将传入的日志字符串复制到当前索引位置
    strncpy(iringbuf[iringbuf_index].log, logbuf, MAX_LOG_LEN - 1);
    iringbuf[iringbuf_index].log[MAX_LOG_LEN - 1] = '\0'; // 确保字符串正确结束
    
    // 更新索引，如果到达末尾则绕回 0 (取模魔法)
    iringbuf_index = (iringbuf_index + 1) % IRINGBUF_SIZE;
    
    // 记录是否已经写满过一圈
    if (iringbuf_index == 0) {
        iringbuf_full = true;
    }
}

// 2. 打印环形缓冲区 (出错时调用)
void display_iringbuf() {
    printf("--- Instruction Ring Buffer (iringbuf) ---\n");
    
    // 如果还没写满一圈，就从 0 开始打印；如果写满了，就从当前 index 开始打印（最老的一条）
    int start = iringbuf_full ? iringbuf_index : 0;
    int count = iringbuf_full ? IRINGBUF_SIZE : iringbuf_index;

    for (int i = 0; i < count; i++) {
        int idx = (start + i) % IRINGBUF_SIZE;
        
        // 打印箭头指示最后一条执行的指令 (出错指令)
        if (i == count - 1) {
            printf(" --> %s\n", iringbuf[idx].log);
        } else {
            printf("     %s\n", iringbuf[idx].log);
        }
    }
    printf("------------------------------------------\n");
}
