#include "utils.h"
#include <sys/time.h>
#include <stddef.h>

static uint64_t boot_time = 0;

uint64_t get_time() {
    struct timeval now;
    gettimeofday(&now, NULL);
    uint64_t us = now.tv_sec * 1000000ULL + now.tv_usec;
    if (boot_time == 0) boot_time = us;
    return us - boot_time;
}
