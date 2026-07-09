#include "monitor.h"
#include "memory.h"
#include <string.h>
#include <stdio.h>

void parse_args_and_load(int argc, char** argv) {
    const char* irom_file = "./bin/test_src/irom.bin"; 
    const char* dram_file = "./bin/test_src/dram.bin"; 
    uint32_t dram_addr = 0x80100000; 

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-i") == 0 && i + 1 < argc) {
            irom_file = argv[++i];
        } else if (strcmp(argv[i], "-d") == 0 && i + 1 < argc) {
            dram_file = argv[++i];
        } else if (strcmp(argv[i], "-a") == 0 && i + 1 < argc) {
            sscanf(argv[++i], "%x", &dram_addr);
        } else if (argv[i][0] != '-') {
            irom_file = argv[i];          
        }
    }
    
    // 初始化物理内存，然后加载镜像
    memset(pmem, 0, PMEM_SIZE);
    load_image(irom_file, PMEM_BASE);           
    if (dram_file != NULL) {
        load_image(dram_file, dram_addr);       
    }
}
