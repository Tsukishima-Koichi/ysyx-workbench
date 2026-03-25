#include <common.h>
#include <elf.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// 存放符号信息的结构体
typedef struct {
    char name[64];
    paddr_t start;
    uint32_t size;
} SymbolEntry;

#define MAX_SYMS 1024
static SymbolEntry sym_table[MAX_SYMS];
static int sym_count = 0;
static int call_depth = 0; // 记录函数调用的缩进层级

// 1. 初始化 ftrace，读取 ELF 文件
void init_ftrace(const char *elf_file) {
    if (elf_file == NULL) {
        Log("No ELF file provided. ftrace will not work.");
        return;
    }

    FILE *fp = fopen(elf_file, "rb");
    if (!fp) {
        panic("Failed to open ELF file: %s", elf_file);
    }

    // 读取 ELF 文件头
    Elf32_Ehdr ehdr;
    if (fread(&ehdr, sizeof(Elf32_Ehdr), 1, fp) != 1) {
        panic("Failed to read ELF header");
    }

    // 检查魔数，确认是不是 ELF 文件 (0x7F 'E' 'L' 'F')
    if (*(uint32_t *)ehdr.e_ident != 0x464c457f) {
        panic("File is not a valid ELF file");
    }

    // 读取所有的节头表 (Section Headers)
    Elf32_Shdr *shdrs = malloc(sizeof(Elf32_Shdr) * ehdr.e_shnum);
    fseek(fp, ehdr.e_shoff, SEEK_SET);
    if (fread(shdrs, sizeof(Elf32_Shdr), ehdr.e_shnum, fp) != ehdr.e_shnum) {
        panic("Failed to read section headers");
    }

    Elf32_Shdr *symtab = NULL;
    Elf32_Shdr *strtab = NULL;

    // 寻找符号表 (.symtab) 和它对应的字符串表 (.strtab)
    for (int i = 0; i < ehdr.e_shnum; i++) {
        if (shdrs[i].sh_type == SHT_SYMTAB) {
            symtab = &shdrs[i];
            strtab = &shdrs[symtab->sh_link]; // sh_link 存着对应字符串表的索引
            break;
        }
    }

    // 如果找到了，就开始提取函数符号
    if (symtab && strtab) {
        Elf32_Sym *syms = malloc(symtab->sh_size);
        fseek(fp, symtab->sh_offset, SEEK_SET);
        if (fread(syms, symtab->sh_size, 1, fp) != 1) {
            panic("Failed to read symbol table");
        }
        char *strs = malloc(strtab->sh_size);
        fseek(fp, strtab->sh_offset, SEEK_SET);
        if (fread(strs, strtab->sh_size, 1, fp) != 1) {
            panic("Failed to read string table");
        }

        int num_syms = symtab->sh_size / sizeof(Elf32_Sym);
        for (int i = 0; i < num_syms; i++) {
            // 我们只关心类型为 FUNC（函数）的符号
            if (ELF32_ST_TYPE(syms[i].st_info) == STT_FUNC) {
                strncpy(sym_table[sym_count].name, strs + syms[i].st_name, 63);
                sym_table[sym_count].start = syms[i].st_value;
                sym_table[sym_count].size = syms[i].st_size;
                sym_count++;
                if (sym_count >= MAX_SYMS) break; // 防溢出
            }
        }
        free(syms);
        free(strs);
        Log("Loaded %d functions from ELF for ftrace", sym_count);
    } else {
        Log("No Symbol Table found in ELF");
    }

    free(shdrs);
    fclose(fp);
}

// 2. 根据地址查函数名
const char* get_func_name(paddr_t pc) {
    for (int i = 0; i < sym_count; i++) {
        if (pc >= sym_table[i].start && pc < sym_table[i].start + sym_table[i].size) {
            return sym_table[i].name;
        }
    }
    return "???";
}

// 3. 拦截机器码，判断 Call / Ret 并打印
void trace_func_call(paddr_t pc, paddr_t dnpc, uint32_t inst) {
    // 提取 RISC-V 32 位机器码的关键字段
    uint32_t opcode = inst & 0x7F;
    uint32_t rd     = (inst >> 7) & 0x1F;
    uint32_t rs1    = (inst >> 15) & 0x1F;

    // jal (0x6f) 或 jalr (0x67)，且目标寄存器是 ra (x1) 或 t0 (x5)
    bool is_call = (opcode == 0x6f || opcode == 0x67) && (rd == 1 || rd == 5);
    
    // 必须是 jalr (0x67)，目标寄存器是 x0 (丢弃返回地址)，源寄存器是 ra (x1) 或 t0 (x5)
    bool is_ret  = (opcode == 0x67) && (rd == 0) && (rs1 == 1 || rs1 == 5);

    if (is_call) {
        printf(FMT_WORD ": %*scall [%s@" FMT_WORD "]\n", pc, call_depth * 2, "", get_func_name(dnpc), dnpc);
        call_depth++;
    } else if (is_ret) {
        call_depth--;
        if (call_depth < 0) call_depth = 0; // 防手抖
        printf(FMT_WORD ": %*sret  [%s]\n", pc, call_depth * 2, "", get_func_name(pc));
    }
}
