// CPUXLib.c
    
    #include "CPUXLib.h"
    #include <sys/sysctl.h>
    #include <stdlib.h>
    #include <string.h>
    #include <errno.h>
    #include <stdint.h>
    #include <stdio.h>
    
    #ifdef __APPLE__
    #include <mach/mach.h>
    #include <mach/mach_time.h>
    #include <mach/vm_statistics.h>
    #include <mach/task_info.h>
    #endif
    
    // Helper function to handle sysctl errors
    static int sysctl_safe(const int* name, u_int namelen, void* oldp, size_t* oldlenp, const void* newp, size_t newlen) {
        if (sysctl(name, namelen, oldp, oldlenp, newp, newlen) != 0) {
            perror("sysctl failed");
            return -1;
        }
        return 0;
    }
    
    // Helper function to handle sysctlbyname errors
    static int sysctlbyname_safe(const char* name, void* oldp, size_t* oldlenp, const void* newp, size_t newlen) {
        if (sysctlbyname(name, oldp, oldlenp, newp, newlen) != 0) {
            perror("sysctlbyname failed");
            return -1;
        }
        return 0;
    }
    
    CPUInfo* getCPUInfo() {
        CPUInfo* info = (CPUInfo*)malloc(sizeof(CPUInfo));
        if (!info) {
            fprintf(stderr, "Error: Could not allocate memory for CPUInfo.\n");
            return NULL;
        }
    
        memset(info, 0, sizeof(CPUInfo));
    
    #ifdef __APPLE__
        size_t size = sizeof(info->model);
        if (sysctlbyname_safe("hw.machine", &info->model, &size, NULL, 0) != 0) {
            strncpy(info->model, "Unknown", sizeof(info->model) - 1);
            info->model[sizeof(info->model) - 1] = '\0';
        }
    
        int coreCount, threadCount;
        size = sizeof(coreCount);
        if (sysctlbyname_safe("hw.physicalcpu", &coreCount, &size, NULL, 0) == 0) {
            info->coreCount = coreCount;
        }
        size = sizeof(threadCount);
        if (sysctlbyname_safe("hw.logicalcpu", &threadCount, &size, NULL, 0) == 0) {
            info->threadCount = threadCount;
        }
    
        char cpuBrand[256];
        size = sizeof(cpuBrand);
        if (sysctlbyname_safe("machdep.cpu.brand_string", &cpuBrand, &size, NULL, 0) == 0) {
            strncpy(info->cpuBrand, cpuBrand, sizeof(info->cpuBrand) - 1);
            info->cpuBrand[sizeof(info->cpuBrand) - 1] = '\0';
        } else {
            strncpy(info->cpuBrand, "Unknown", sizeof(info->cpuBrand) - 1);
            info->cpuBrand[sizeof(info->cpuBrand) - 1] = '\0';
        }
    
    #else
        strncpy(info->model, "Unknown", sizeof(info->model) - 1);
        info->model[sizeof(info->model) - 1] = '\0';
        strncpy(info->cpuBrand, "Unknown", sizeof(info->cpuBrand) - 1);
        info->cpuBrand[sizeof(info->cpuBrand) - 1] = '\0';
    #endif
        return info;
    }
    
    void freeCPUInfo(CPUInfo* info) {
        free(info);
    }
    
    MemoryInfo* getMemoryInfo() {
        MemoryInfo* memInfo = (MemoryInfo*)malloc(sizeof(MemoryInfo));
        if (!memInfo) {
            fprintf(stderr, "Error: Could not allocate memory for MemoryInfo.\n");
            return NULL;
        }
    
    #ifdef __APPLE__
        int mib= {CTL_HW, HW_MEMSIZE};
        size_t length = sizeof(memInfo->totalMemory);
        if (sysctl_safe(mib, 2, &memInfo->totalMemory, &length, NULL, 0) != 0) {
            fprintf(stderr, "Error: sysctl failed to get total memory.\n");
            free(memInfo);
            return NULL;
        }
    
        vm_statistics64_data_t vm_stats;
        mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
        if (host_statistics64(mach_host_self(), HOST_VM_INFO64, (host_info64_t)&vm_stats, &count) == KERN_SUCCESS) {
            memInfo->freeMemory = (int64_t)vm_stats.free_count * vm_page_size;
        } else {
             fprintf(stderr, "Error: host_statistics64 failed.\n");
        }
    
    #else
        memInfo->totalMemory = 0;
        memInfo->freeMemory = 0;
    #endif
    
        return memInfo;
    }
    
    void freeMemoryInfo(MemoryInfo* info) {
        free(info);
    }