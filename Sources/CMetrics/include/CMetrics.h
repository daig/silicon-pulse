#ifndef CMETRICS_H
#define CMETRICS_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

#define CM_MAX_CORES 64
#define CM_MAX_FANS 4
#define CM_MAX_PROCS 8

typedef struct {
    char chipName[128];
    uint64_t totalMemoryBytes;
    uint64_t gpuWiredLimitBytes;
    uint64_t metalRecommendedMaxBytes;
    uint32_t totalCPUCores;
    uint32_t perfLevel0Cores;       // Super cores on M5 Ultra (10)
    char perfLevel0Name[32];
    uint32_t perfLevel1Cores;       // Performance cores on M5 Ultra (20)
    char perfLevel1Name[32];
    uint32_t gpuCoreCount;          // 64 on M5 Ultra
    uint32_t fanCount;              // 2 on Mac Studio
    bool isDualDie;
} CMStaticInfo;

typedef struct {
    int32_t pid;
    char name[64];
    uint64_t physFootprintBytes;
} CMProcessMem;

typedef struct {
    double timestamp;

    // GPU (IOAccelerator + IOReport)
    int32_t gpuDeviceUtilPct;
    int32_t gpuRendererUtilPct;
    int32_t gpuTilerUtilPct;
    double gpuActiveResidencyPct;   // From GPUPH (100 - OFF%)
    int32_t gpuDominantPState;      // 1..15 (0 = OFF)
    double gpuFreqMHz;              // Weighted active frequency from GPUPH + pmgr table
    uint64_t gpuInUseBytes;
    uint64_t gpuAllocBytes;
    uint64_t gpuRecoveryCount;
    bool gpuThermalThrottling;      // GPU_CLTM active
    double gpuPPMTargetPct;         // GPU_PPM (% of max power budget)
    int64_t gpuThrottleEventsDelta; // Throttle Counter Total delta
    double gpuPowerWatts;           // Energy Model GPU Energy delta

    // Memory Bandwidth (IOReport PMP0/PMP1 DCS BW AMCC0/AMCC1)
    double bwDie0ReadGBs;
    double bwDie0WriteGBs;
    double bwDie0TotalGBs;
    double bwDie1ReadGBs;
    double bwDie1WriteGBs;
    double bwDie1TotalGBs;
    double bwTotalGBs;

    // Memory (Mach vm_statistics64 + sysctl)
    uint64_t memWiredBytes;
    uint64_t memActiveBytes;
    uint64_t memInactiveBytes;
    uint64_t memCompressedBytes;
    uint64_t memFreeBytes;
    uint64_t swapTotalBytes;
    uint64_t swapUsedBytes;
    uint64_t swapInsDelta;
    uint64_t swapOutsDelta;
    int32_t memoryPressureLevel;    // 1=Normal, 2=Warn, 4=Critical
    int32_t memoryAvailablePct;     // kern.memorystatus_level

    // CPU (IOReport CPU Core Performance States + Mach fallback)
    double cpuTotalPct;
    double cpuSuperPct;             // PCPU clusters (10 cores)
    double cpuPerfPct;              // MCPU clusters (20 cores)
    double cpuDie0Pct;
    double cpuDie1Pct;
    uint32_t superCoreCount;
    double superCoreUtil[CM_MAX_CORES]; // 0..100 per Super core
    uint32_t perfCoreCount;
    double perfCoreUtil[CM_MAX_CORES];  // 0..100 per Performance core

    // Power (AppleSMC)
    double powerSystemWatts;        // PD0R or PSTR
    double powerSoCWatts;           // PSVR
    double powerMemWatts;           // PMVR
    double powerDie0Watts;          // PZC0
    double powerDie1Watts;          // PZC1

    // Temperatures (AppleSMC + IOHID fallback)
    double tempDiePeakC;            // TPDX or max(TPD*)
    double tempDieAvgC;             // avg(TPD*)
    double tempHotspotC;            // TCMb / max hotspot
    double tempVRMOrMemC;           // TMVR
    double tempNandC;               // avg(TN00..TN03) or NAND CH0
    int32_t thermalState;           // NSProcessInfoThermalState (0..3)

    // Fans (AppleSMC)
    uint32_t fanCount;
    double fanActualRPM[CM_MAX_FANS];
    double fanTargetRPM[CM_MAX_FANS];
    double fanMinRPM[CM_MAX_FANS];
    double fanMaxRPM[CM_MAX_FANS];

    // Top memory processes
    uint32_t topProcCount;
    CMProcessMem topProcs[CM_MAX_PROCS];

    // Diagnostics
    bool smcAvailable;
    bool ioReportAvailable;
    bool ioAcceleratorAvailable;
} CMSample;

typedef struct CMCollector CMCollector;

CMCollector *cm_collector_create(void);
void cm_collector_destroy(CMCollector *collector);
void cm_collector_get_static_info(CMCollector *collector, CMStaticInfo *outInfo);
bool cm_collector_sample(CMCollector *collector, CMSample *outSample);

#ifdef __cplusplus
}
#endif

#endif // CMETRICS_H
