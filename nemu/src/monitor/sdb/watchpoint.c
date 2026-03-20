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

#include "sdb.h"

#define NR_WP 32

typedef struct watchpoint {
  int NO;
  struct watchpoint *next;

  /* TODO: Add more members if necessary */
  char expr[128];  // 用于保存被监视的表达式字符串
  word_t old_val;  // 用于保存上一次计算出的表达式的值
} WP;

static WP wp_pool[NR_WP] = {};
static WP *head = NULL, *free_ = NULL;

void init_wp_pool() {
  int i;
  for (i = 0; i < NR_WP; i ++) {
    wp_pool[i].NO = i;
    wp_pool[i].next = (i == NR_WP - 1 ? NULL : &wp_pool[i + 1]);
  }

  head = NULL;
  free_ = wp_pool;
}

/* TODO: Implement the functionality of watchpoint */

WP* new_wp() {
  // 1. 检查是否还有空闲的监视点
  if (free_ == NULL) {
    panic("No more free watchpoints! Please increase NR_WP.");
  }

  // 2. 从 free_ 链表的头部摘下一个节点
  WP *wp = free_;
  free_ = free_->next;

  // 3. 将取出的节点清空（初始化），防止残留上一轮的数据
  wp->expr[0] = '\0';
  wp->old_val = 0;

  // 4. 将它头插法插入到 head 链表中 (表示该监视点正在被使用)
  wp->next = head;
  head = wp;

  return wp;
}

void free_wp(WP *wp) {
  if (wp == NULL) {
    return;
  }

  // 1. 将 wp 从 head 链表中摘除
  if (head == wp) {
    // 如果要删除的正好是头节点
    head = head->next;
  } else {
    // 如果要删除的是中间节点，需要遍历找到它的前驱节点
    WP *curr = head;
    while (curr != NULL && curr->next != wp) {
      curr = curr->next;
    }
    
    // 如果找到了前驱节点，将其从链表中断开
    if (curr != NULL) {
      curr->next = wp->next;
    } else {
      panic("Error: Watchpoint to free is not in the active list!");
    }
  }

  // 2. 将摘除的 wp 归还到 free_ 链表的头部
  wp->next = free_;
  free_ = wp;
}

#include <string.h>
#include <stdlib.h>

// 声明外部的表达式求值函数
extern word_t expr(char *e, bool *success);

// 1. 创建监视点
void create_watchpoint(char *args) {
  bool success = false;
  // 先求一次值，验证表达式是否合法，并作为初始值
  word_t val = expr(args, &success);
  if (!success) {
    printf("Error: Invalid expression '%s'\n", args);
    return;
  }

  WP *wp = new_wp();
  strcpy(wp->expr, args); // 记录表达式
  wp->old_val = val;      // 记录初始值
  printf("Hardware watchpoint %d: %s\n", wp->NO, wp->expr);
}

// 2. 删除监视点
void delete_watchpoint(int no) {
  WP *curr = head;
  while (curr != NULL) {
    if (curr->NO == no) {
      free_wp(curr);
      printf("Watchpoint %d deleted\n", no);
      return;
    }
    curr = curr->next;
  }
  printf("Error: Watchpoint %d not found\n", no);
}

// 3. 打印所有使用中的监视点 (给 info w 用)
void display_watchpoints() {
  if (head == NULL) {
    printf("No watchpoints.\n");
    return;
  }
  printf("Num\tType\t\tDisp\tEnb\tAddress\t\tWhat\n");
  WP *curr = head;
  while (curr != NULL) {
    printf("%d\thw watchpoint\tkeep\ty\t\t\t%s\n", curr->NO, curr->expr);
    curr = curr->next;
  }
}

// 4. 检查监视点是否发生变化 (给 cpu_exec 用)
bool check_watchpoints() {
  bool changed = false;
  WP *curr = head;
  
  while (curr != NULL) {
    bool success = false;
    word_t new_val = expr(curr->expr, &success);
    
    // 如果求值成功，且新值不等于旧值，说明数据被篡改了！
    if (success && new_val != curr->old_val) {
      printf("\nHardware watchpoint %d: %s\n", curr->NO, curr->expr);
      printf("Old value = %u (0x%08x)\n", curr->old_val, curr->old_val);
      printf("New value = %u (0x%08x)\n", new_val, new_val);
      curr->old_val = new_val; // 更新为新值，以备下次比较
      changed = true;          // 标记发生了变化
    }
    curr = curr->next;
  }
  
  return changed;
}