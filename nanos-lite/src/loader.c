#include <proc.h>
#include <elf.h>

// 根据 AM 定义的宏，设定我们期望的 ELF 架构类型
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

// 声明外部的 ramdisk 操作函数 (通常在 ramdisk.c 中定义)
extern size_t ramdisk_read(void *buf, size_t offset, size_t len);
extern size_t get_ramdisk_size();

#ifdef __LP64__
# define Elf_Ehdr Elf64_Ehdr
# define Elf_Phdr Elf64_Phdr
#else
# define Elf_Ehdr Elf32_Ehdr
# define Elf_Phdr Elf32_Phdr
#endif

static uintptr_t loader(PCB *pcb, const char *filename) {
  Elf_Ehdr ehdr;
  
  // 1. 从 ramdisk 的 0 偏移处读取 ELF 文件头 (Header)
  ramdisk_read(&ehdr, 0, sizeof(Elf_Ehdr));

  // 2. 检查魔数：\x7f E L F 
  // (由于 RISC-V 是小端序，内存里的排布是 0x7f, 0x45, 0x4c, 0x46)
  assert(*(uint32_t *)ehdr.e_ident == 0x464c457f);

  // 3. 检查架构是否匹配 (防止把 x86 的程序喂给 RISC-V 的 CPU)
  assert(ehdr.e_machine == EXPECT_TYPE);

  // 4. 读取所有的 Program Headers
  // e_phnum 记录了有几个段，e_phoff 记录了段表在文件中的偏移量
  Elf_Phdr phdr[ehdr.e_phnum];
  ramdisk_read(phdr, ehdr.e_phoff, sizeof(Elf_Phdr) * ehdr.e_phnum);

  // 5. 遍历 Program Headers，把需要加载的段搬到内存里
  for (int i = 0; i < ehdr.e_phnum; i++) {
    // 我们只关心类型为 PT_LOAD (需要被加载到内存) 的段
    if (phdr[i].p_type == PT_LOAD) {
      
      // (a) 将文件中实际存在的数据拷贝到内存对应的虚拟地址 (FileSiz)
      ramdisk_read((void *)phdr[i].p_vaddr, phdr[i].p_offset, phdr[i].p_filesz);
      
      // (b) 处理 .bss 段：将 MemSiz 大于 FileSiz 的部分清零
      if (phdr[i].p_memsz > phdr[i].p_filesz) {
        memset((void *)(phdr[i].p_vaddr + phdr[i].p_filesz), 0, phdr[i].p_memsz - phdr[i].p_filesz);
      }
    }
  }

  // 6. 返回程序的入口地址
  return ehdr.e_entry;
}

void naive_uload(PCB *pcb, const char *filename) {
  uintptr_t entry = loader(pcb, filename);
  Log("Jump to entry = %p", entry);
  
  // 将 entry 强转为函数指针并执行！
  // 此时计算机的生命周期正式突破边界，控制权交给用户程序
  ((void(*)())entry) ();
}