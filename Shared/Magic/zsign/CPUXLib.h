// CPUXLib.h
    
    #ifndef CPUX_LIB_H
    #define CPUX_LIB_H
    
    #ifdef __cplusplus
    extern "C" {
    #endif
    
    #include <stdint.h>
    
    typedef struct {
        char model[256];
        char cpuBrand[256];
        uint32_t coreCount;
        uint32_t threadCount;
    } CPUInfo;
    
    typedef struct {
        uint64_t totalMemory;
        uint64_t freeMemory;
    } MemoryInfo;
    
    CPUInfo* getCPUInfo();
    MemoryInfo* getMemoryInfo();
    
    void freeCPUInfo(CPUInfo* info);
    void freeMemoryInfo(MemoryInfo* info);
    
    #ifdef __cplusplus
    }
    #endif
    
    #endif /* CPUX_LIB_H */