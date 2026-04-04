#include <fs.h>
#include <string.h>

typedef size_t (*ReadFn) (void *buf, size_t offset, size_t len);
typedef size_t (*WriteFn) (const void *buf, size_t offset, size_t len);

typedef struct {
  char *name;
  size_t size;
  size_t disk_offset;
  ReadFn read;
  WriteFn write;
  size_t open_offset; // 【新增】用于记录这个文件当前读写到了哪个位置
} Finfo;

enum {FD_STDIN, FD_STDOUT, FD_STDERR, FD_FB, FD_EVENTS, FD_DISPINFO};

size_t invalid_read(void *buf, size_t offset, size_t len) {
  panic("should not reach here");
  return 0;
}

size_t invalid_write(const void *buf, size_t offset, size_t len) {
  panic("should not reach here");
  return 0;
}

// 引入底层 ramdisk 的读写接口
extern size_t ramdisk_read(void *buf, size_t offset, size_t len);
extern size_t ramdisk_write(const void *buf, size_t offset, size_t len);

extern size_t serial_write(const void *buf, size_t offset, size_t len);

extern size_t events_read(void *buf, size_t offset, size_t len);

extern size_t dispinfo_read(void *buf, size_t offset, size_t len);

extern size_t fb_write(const void *buf, size_t offset, size_t len);

/* This is the information about all files in disk. */
static Finfo file_table[] __attribute__((used)) = {
  [FD_STDIN]  = {"stdin", 0, 0, invalid_read, invalid_write},
  // stdout 和 stderr 的写操作接管给 serial_write！
  [FD_STDOUT] = {"stdout", 0, 0, invalid_read, serial_write},
  [FD_STDERR] = {"stderr", 0, 0, invalid_read, serial_write},
// 这里会自动把 ramdisk.h 里的文件列表展开到数组里
// 注意：展开的普通文件，其 read 和 write 指针默认会被初始化为 NULL
// 【新增这行】先给它占个坑，后面做 VGA 实验时再来完善
  [FD_FB]     = {"/dev/fb", 0, 0, invalid_read, fb_write},
  // 【新增这一行】：/dev/events 支持读，不支持写
  [FD_EVENTS] = {"/dev/events", 0, 0, events_read, invalid_write},
  // 【新增这一行】：/proc/dispinfo 只支持读
  [FD_DISPINFO] = {"/proc/dispinfo", 0, 0, dispinfo_read, invalid_write},
#include "files.h"
};

// 获取文件表的总长度
#define NR_FILES (sizeof(file_table) / sizeof(file_table[0]))

void init_fs() {
  // 初始化 /dev/fb 的文件大小
  AM_GPU_CONFIG_T cfg = io_read(AM_GPU_CONFIG);
  file_table[FD_FB].size = cfg.width * cfg.height * 4;
}

// 1. 打开文件
int fs_open(const char *pathname, int flags, int mode) {
  for (int i = 0; i < NR_FILES; i++) {
    // 【修改判断条件】先确认 name 不是 NULL，再去 strcmp
    if (file_table[i].name != NULL && strcmp(file_table[i].name, pathname) == 0) {
      file_table[i].open_offset = 0;
      return i;
    }
  }
  panic("File %s not found!", pathname);
  return -1;
}

// 2. 读取文件
size_t fs_read(int fd, void *buf, size_t len) {
  Finfo *f = &file_table[fd];
  
  // VFS 核心魔法：如果这个文件自带了特殊的 read 函数，就调用它自己的！
  if (f->read != NULL) {
    return f->read(buf, f->open_offset, len);
  }

  // 否则，这就是一个普通的硬盘文件
  // 越界截断处理
  if (f->open_offset + len > f->size) {
    len = f->size - f->open_offset;
  }
  
  // 只有当 len > 0 时才去读硬盘
  if (len > 0) {
    ramdisk_read(buf, f->disk_offset + f->open_offset, len);
    f->open_offset += len;
  }
  return len;
}

// 3. 写入文件
size_t fs_write(int fd, const void *buf, size_t len) {
  Finfo *f = &file_table[fd];
  
  // VFS 核心魔法：如果自带了 write 函数，就调用它自己的
  if (f->write != NULL) {
    return f->write(buf, f->open_offset, len);
  }

  // 否则，写入普通硬盘文件
  if (f->open_offset + len > f->size) {
    len = f->size - f->open_offset;
  }
  
  if (len > 0) {
    ramdisk_write(buf, f->disk_offset + f->open_offset, len);
    f->open_offset += len;
  }
  return len;
}

// 4. 定位指针
size_t fs_lseek(int fd, size_t offset, int whence) {
  Finfo *f = &file_table[fd];
  
  switch (whence) {
    case SEEK_SET:
      f->open_offset = offset;
      break;
    case SEEK_CUR:
      f->open_offset += offset;
      break;
    case SEEK_END:
      f->open_offset = f->size + offset; // offset 通常是负的
      break;
    default:
      panic("Unhandled whence %d", whence);
  }
  
  // 越界检查
  if (f->open_offset > f->size) {
    f->open_offset = f->size;
  }
  
  return f->open_offset;
}

// 5. 关闭文件
int fs_close(int fd) {
  return 0;
}


// 传入 fd，返回对应的文件名
const char *fs_get_name(int fd) {
  // 增加越界保护
  if (fd >= 0 && fd < NR_FILES) {
    return file_table[fd].name;
  }
  return "UNKNOWN_FILE";
}