#include <proc.h>
#include <elf.h>
#include <fs.h> // 【新增】引入文件系统的头文件

// 设定期望的 ELF 架构类型
#if defined(__ISA_AM_NATIVE__)
# define EXPECT_TYPE EM_X86_64
#elif defined(__ISA_X86__)
# define EXPECT_TYPE EM_386
#elif defined(__ISA_MIPS32__)
# define EXPECT_TYPE EM_MIPS
#elif defined(__ISA_RISCV32__) || defined(__ISA_RISCV64__)
# define EXPECT_TYPE EM_RISCV
#else
# error Unsupported ISA
#endif

// 【新增】声明我们将要使用的文件系统接口
extern int fs_open(const char *pathname, int flags, int mode);
extern size_t fs_read(int fd, void *buf, size_t len);
extern size_t fs_lseek(int fd, size_t offset, int whence);
extern int fs_close(int fd);

#ifdef __LP64__
# define Elf_Ehdr Elf64_Ehdr
# define Elf_Phdr Elf64_Phdr
#else
# define Elf_Ehdr Elf32_Ehdr
# define Elf_Phdr Elf32_Phdr
#endif

static uintptr_t loader(PCB *pcb, const char *filename) {
  Elf_Ehdr ehdr;
  
  // 1. 通过文件名打开文件，获取号码牌 (FD)
  int fd = fs_open(filename, 0, 0);
  if (fd < 0) {
    panic("Loader cannot open file: %s", filename);
  }

  // 2. 读取 ELF 文件头
  // 注意：刚 open 完，文件的读写指针默认在 0，所以直接 read 就是读头部
  fs_read(fd, &ehdr, sizeof(Elf_Ehdr));

  // 3. 检查魔数和架构
  assert(*(uint32_t *)ehdr.e_ident == 0x464c457f);
  assert(ehdr.e_machine == EXPECT_TYPE);

  // 4. 读取所有的 Program Headers
  Elf_Phdr phdr[ehdr.e_phnum];
  // 【关键变化】：段表可能不在文件紧接着开头的地方，必须先 lseek 拨动指针！
  fs_lseek(fd, ehdr.e_phoff, SEEK_SET);
  fs_read(fd, phdr, sizeof(Elf_Phdr) * ehdr.e_phnum);

  // 5. 遍历 Program Headers
  for (int i = 0; i < ehdr.e_phnum; i++) {
    if (phdr[i].p_type == PT_LOAD) {
      
      // (a) 【关键变化】：把文件指针拨到这个段在文件里的偏移量
      fs_lseek(fd, phdr[i].p_offset, SEEK_SET);
      
      // (b) 读取实际的段数据到内存虚拟地址
      fs_read(fd, (void *)phdr[i].p_vaddr, phdr[i].p_filesz);
      
      // (c) 处理 .bss 段 (MemSiz > FileSiz)
      if (phdr[i].p_memsz > phdr[i].p_filesz) {
        memset((void *)(phdr[i].p_vaddr + phdr[i].p_filesz), 0, phdr[i].p_memsz - phdr[i].p_filesz);
      }
    }
  }

  // 6. 记得随手关门 (关闭文件)
  fs_close(fd);

  return ehdr.e_entry;
}

void naive_uload(PCB *pcb, const char *filename) {
  uintptr_t entry = loader(pcb, filename);
  Log("Jump to entry = %p", entry);
  ((void(*)())entry) ();
}