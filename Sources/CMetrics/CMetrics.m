#import "CMetrics.h"

#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/hidsystem/IOHIDEventSystemClient.h>
#import <Metal/Metal.h>
#import <mach/mach.h>
#import <mach/mach_host.h>
#import <mach/processor_info.h>
#import <sys/sysctl.h>
#import <libproc.h>
#import <sys/proc_info.h>
#import <sys/resource.h>
#import <math.h>
#import <stdlib.h>
#import <string.h>

// ---- IOReport private API declarations ----
typedef struct IOReportSubscriptionRef *IOReportSubscriptionRef;
extern CFDictionaryRef IOReportCopyChannelsInGroup(CFStringRef group, CFStringRef subgroup, uint64_t a, uint64_t b, uint64_t c);
extern void IOReportMergeChannels(CFDictionaryRef a, CFDictionaryRef b, CFTypeRef unused);
extern IOReportSubscriptionRef IOReportCreateSubscription(void *a, CFMutableDictionaryRef desiredChannels, CFMutableDictionaryRef *subbedChannels, uint64_t channel_id, CFTypeRef b);
extern CFDictionaryRef IOReportCreateSamples(IOReportSubscriptionRef sub, CFMutableDictionaryRef subbedChannels, CFTypeRef a);
extern CFDictionaryRef IOReportCreateSamplesDelta(CFDictionaryRef prev, CFDictionaryRef curr, CFTypeRef a);
extern CFStringRef IOReportChannelGetGroup(CFDictionaryRef ch);
extern CFStringRef IOReportChannelGetSubGroup(CFDictionaryRef ch);
extern CFStringRef IOReportChannelGetChannelName(CFDictionaryRef ch);
extern CFStringRef IOReportChannelGetUnitLabel(CFDictionaryRef ch);
extern int IOReportChannelGetFormat(CFDictionaryRef ch);
extern int64_t IOReportSimpleGetIntegerValue(CFDictionaryRef ch, int32_t idx);
extern int32_t IOReportStateGetCount(CFDictionaryRef ch);
extern CFStringRef IOReportStateGetNameForIndex(CFDictionaryRef ch, int32_t idx);
extern int64_t IOReportStateGetResidency(CFDictionaryRef ch, int32_t idx);
extern void IOReportIterate(CFDictionaryRef samples, int (^block)(CFDictionaryRef channel));

// ---- IOHID private API declarations (fallback for temps) ----
typedef struct __IOHIDEvent *IOHIDEventRef;
typedef struct __IOHIDServiceClient *IOHIDServiceClientRef;
typedef struct __IOHIDEventSystemClient *IOHIDEventSystemClientRef;
extern IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
extern int IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client, CFDictionaryRef match);
extern CFArrayRef IOHIDEventSystemClientCopyServices(IOHIDEventSystemClientRef client);
extern CFTypeRef IOHIDServiceClientCopyProperty(IOHIDServiceClientRef service, CFStringRef key);
extern IOHIDEventRef IOHIDServiceClientCopyEvent(IOHIDServiceClientRef service, int64_t type, int32_t options, int64_t timestamp);
extern double IOHIDEventGetFloatValue(IOHIDEventRef event, int32_t field);
#define kIOHIDEventTypeTemperature 15

// ---- AppleSMC structures ----
typedef struct {
    uint32_t key;
    struct {
        uint8_t major;
        uint8_t minor;
        uint8_t build;
        uint8_t reserved;
        uint16_t release;
    } vers;
    struct {
        uint16_t version;
        uint16_t length;
        uint32_t cpuPLimit;
        uint32_t gpuPLimit;
        uint32_t memPLimit;
    } pLimitData;
    struct {
        uint32_t dataSize;
        uint32_t dataType;
        uint8_t dataAttributes;
    } keyInfo;
    uint8_t result;
    uint8_t status;
    uint8_t data8;
    uint32_t data32;
    uint8_t bytes[32];
} SMCParamStruct;

typedef struct {
    char name[5];
    uint32_t key;
    uint32_t dataType;
    uint32_t dataSize;
    bool valid;
} SMCCachedKey;

#define MAX_GPU_PSTATES 32

struct CMCollector {
    CMStaticInfo staticInfo;

    // IOReport state
    IOReportSubscriptionRef ioReportSub;
    CFMutableDictionaryRef ioReportSubbedChannels;
    CFDictionaryRef prevIOReportSample;
    double prevSampleTime;
    bool ioReportReady;

    // GPU frequency table from pmgr (MHz indexed by P-state 1..N)
    uint32_t gpuFreqCount;
    double gpuFreqTableMHz[MAX_GPU_PSTATES];

    // AppleSMC state
    io_connect_t smcConn;
    bool smcReady;
    SMCCachedKey smcFanAc[CM_MAX_FANS];
    SMCCachedKey smcFanTg[CM_MAX_FANS];
    SMCCachedKey smcFanMn[CM_MAX_FANS];
    SMCCachedKey smcFanMx[CM_MAX_FANS];

    SMCCachedKey smcPD0R;
    SMCCachedKey smcPSTR;
    SMCCachedKey smcPSVR;
    SMCCachedKey smcPMVR;
    SMCCachedKey smcPZC0;
    SMCCachedKey smcPZC1;

    SMCCachedKey smcTPDX;
    SMCCachedKey smcTCMb;
    SMCCachedKey smcTCDX;
    SMCCachedKey smcTMVR;
    SMCCachedKey smcTPD[16];
    SMCCachedKey smcTN[4];

    // Mach CPU fallback state
    uint32_t prevCPUCount;
    uint64_t prevCPUTicks[CM_MAX_CORES][4];
    bool hasPrevCPUTicks;

    // Swap delta tracking
    uint64_t prevSwapIns;
    uint64_t prevSwapOuts;
    bool hasPrevSwap;

    // IOHID temp fallback
    IOHIDEventSystemClientRef hidTempClient;
};

// ---- Helpers ----

static uint32_t smcStrToKey(const char *s) {
    return ((uint32_t)(uint8_t)s[0] << 24) |
           ((uint32_t)(uint8_t)s[1] << 16) |
           ((uint32_t)(uint8_t)s[2] << 8) |
           ((uint32_t)(uint8_t)s[3]);
}

static kern_return_t smcCall(io_connect_t conn, SMCParamStruct *in, SMCParamStruct *out) {
    size_t outSize = sizeof(SMCParamStruct);
    return IOConnectCallStructMethod(conn, 2, in, sizeof(SMCParamStruct), out, &outSize);
}

static void smcCacheKey(io_connect_t conn, const char *name, SMCCachedKey *ck) {
    memset(ck, 0, sizeof(*ck));
    strncpy(ck->name, name, 4);
    ck->key = smcStrToKey(name);
    SMCParamStruct in = {0}, info = {0};
    in.key = ck->key;
    in.data8 = 9; // kSMCGetKeyInfo
    if (smcCall(conn, &in, &info) == KERN_SUCCESS && info.result == 0 && info.keyInfo.dataSize > 0) {
        ck->dataType = info.keyInfo.dataType;
        ck->dataSize = info.keyInfo.dataSize;
        ck->valid = true;
    }
}

static bool smcReadCached(io_connect_t conn, const SMCCachedKey *ck, double *outVal) {
    if (!ck->valid) return false;
    SMCParamStruct in = {0}, out = {0};
    in.key = ck->key;
    in.keyInfo.dataSize = ck->dataSize;
    in.data8 = 5; // kSMCReadKey
    if (smcCall(conn, &in, &out) != KERN_SUCCESS || out.result != 0) return false;

    uint32_t t = ck->dataType;
    uint32_t sz = ck->dataSize;
    if (t == smcStrToKey("flt ") && sz == 4) {
        float f = 0;
        memcpy(&f, out.bytes, 4);
        if (isnan(f) || isinf(f)) return false;
        *outVal = (double)f;
        return true;
    } else if (t == smcStrToKey("sp78") && sz == 2) {
        int16_t raw = (int16_t)((out.bytes[0] << 8) | out.bytes[1]);
        *outVal = (double)raw / 256.0;
        return true;
    } else if (t == smcStrToKey("fpe2") && sz == 2) {
        uint16_t raw = (uint16_t)((out.bytes[0] << 8) | out.bytes[1]);
        *outVal = (double)raw / 4.0;
        return true;
    } else if (t == smcStrToKey("ui8 ") && sz == 1) {
        *outVal = (double)out.bytes[0];
        return true;
    } else if (t == smcStrToKey("ui16") && sz == 2) {
        *outVal = (double)((out.bytes[0] << 8) | out.bytes[1]);
        return true;
    } else if (t == smcStrToKey("ui32") && sz == 4) {
        uint32_t v = ((uint32_t)out.bytes[0] << 24) | ((uint32_t)out.bytes[1] << 16) |
                     ((uint32_t)out.bytes[2] << 8) | out.bytes[3];
        *outVal = (double)v;
        return true;
    } else if (t == smcStrToKey("ioft") && sz == 8) {
        uint64_t raw = 0;
        memcpy(&raw, out.bytes, 8);
        *outVal = (double)raw / 65536.0;
        return true;
    }
    return false;
}

static void readSysctlString(const char *name, char *buf, size_t bufLen) {
    size_t len = bufLen - 1;
    if (sysctlbyname(name, buf, &len, NULL, 0) == 0) {
        buf[len < bufLen ? len : bufLen - 1] = '\0';
    } else {
        buf[0] = '\0';
    }
}

static uint64_t readSysctlU64(const char *name) {
    uint64_t val = 0;
    size_t len = sizeof(val);
    if (sysctlbyname(name, &val, &len, NULL, 0) == 0) {
        if (len == 4) {
            uint32_t v32 = 0;
            memcpy(&v32, &val, 4);
            return (uint64_t)v32;
        }
        return val;
    }
    return 0;
}

static int32_t readSysctlI32(const char *name) {
    int32_t val = 0;
    size_t len = sizeof(val);
    if (sysctlbyname(name, &val, &len, NULL, 0) == 0) return val;
    return 0;
}

static void initPMGRGPUFreqs(CMCollector *c) {
    io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceNameMatching("pmgr"));
    if (!svc) return;
    CFMutableDictionaryRef props = NULL;
    if (IORegistryEntryCreateCFProperties(svc, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS && props) {
        NSDictionary *d = (__bridge_transfer NSDictionary *)props;
        // voltage-states9 holds GPU DVFS states on Apple Silicon (pairs of uint32 freqHz, voltMv)
        NSData *data = d[@"voltage-states9"];
        if (![data isKindOfClass:[NSData class]]) data = d[@"voltage-states14"];
        if ([data isKindOfClass:[NSData class]]) {
            const uint32_t *u = (const uint32_t *)data.bytes;
            NSUInteger count = data.length / 8;
            uint32_t outIdx = 0;
            for (NSUInteger i = 0; i < count && outIdx < MAX_GPU_PSTATES; i++) {
                uint32_t hz = u[i * 2];
                if (hz > 0) {
                    c->gpuFreqTableMHz[outIdx++] = (double)hz / 1e6;
                }
            }
            c->gpuFreqCount = outIdx;
        }
    }
    IOObjectRelease(svc);
}

static void initSMC(CMCollector *c) {
    io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!svc) return;
    kern_return_t kr = IOServiceOpen(svc, mach_task_self(), 0, &c->smcConn);
    IOObjectRelease(svc);
    if (kr != KERN_SUCCESS) return;
    c->smcReady = true;

    // Fan count & keys
    SMCCachedKey fnum;
    smcCacheKey(c->smcConn, "FNum", &fnum);
    double nFans = 0;
    if (smcReadCached(c->smcConn, &fnum, &nFans) && nFans >= 1) {
        c->staticInfo.fanCount = (uint32_t)MIN((int)nFans, CM_MAX_FANS);
    } else {
        // Probe F0Ac, F1Ac directly
        uint32_t detected = 0;
        for (int i = 0; i < CM_MAX_FANS; i++) {
            char k[5];
            snprintf(k, sizeof(k), "F%dAc", i);
            SMCCachedKey tmp;
            smcCacheKey(c->smcConn, k, &tmp);
            if (tmp.valid) detected = (uint32_t)(i + 1);
        }
        c->staticInfo.fanCount = detected;
    }

    for (uint32_t i = 0; i < c->staticInfo.fanCount; i++) {
        char k[5];
        snprintf(k, sizeof(k), "F%uAc", i); smcCacheKey(c->smcConn, k, &c->smcFanAc[i]);
        snprintf(k, sizeof(k), "F%uTg", i); smcCacheKey(c->smcConn, k, &c->smcFanTg[i]);
        snprintf(k, sizeof(k), "F%uMn", i); smcCacheKey(c->smcConn, k, &c->smcFanMn[i]);
        snprintf(k, sizeof(k), "F%uMx", i); smcCacheKey(c->smcConn, k, &c->smcFanMx[i]);
    }

    // Power keys
    smcCacheKey(c->smcConn, "PD0R", &c->smcPD0R);
    smcCacheKey(c->smcConn, "PSTR", &c->smcPSTR);
    smcCacheKey(c->smcConn, "PSVR", &c->smcPSVR);
    smcCacheKey(c->smcConn, "PMVR", &c->smcPMVR);
    smcCacheKey(c->smcConn, "PZC0", &c->smcPZC0);
    smcCacheKey(c->smcConn, "PZC1", &c->smcPZC1);

    // Temperature keys
    smcCacheKey(c->smcConn, "TPDX", &c->smcTPDX);
    smcCacheKey(c->smcConn, "TCMb", &c->smcTCMb);
    smcCacheKey(c->smcConn, "TCDX", &c->smcTCDX);
    smcCacheKey(c->smcConn, "TMVR", &c->smcTMVR);

    const char *hex = "0123456789abcdef";
    for (int i = 0; i < 16; i++) {
        char k[5] = {'T', 'P', 'D', hex[i], '\0'};
        smcCacheKey(c->smcConn, k, &c->smcTPD[i]);
    }
    for (int i = 0; i < 4; i++) {
        char k[5] = {'T', 'N', '0', (char)('0' + i), '\0'};
        smcCacheKey(c->smcConn, k, &c->smcTN[i]);
    }
}

static void initIOReport(CMCollector *c) {
    struct { CFStringRef group; CFStringRef subgroup; } specs[] = {
        { CFSTR("Energy Model"), NULL },
        { CFSTR("GPU Stats"), CFSTR("GPU Performance States") },
        { CFSTR("GPU Stats"), CFSTR("CLTM-induced GPU Performance States") },
        { CFSTR("GPU Stats"), CFSTR("PPM Target as % of Max GPU Power") },
        { CFSTR("GPU Stats"), CFSTR("GPU Throttler Counters") },
        { CFSTR("CPU Stats"), CFSTR("CPU Core Performance States") },
        { CFSTR("PMP0"), CFSTR("DCS BW") },
        { CFSTR("PMP1"), CFSTR("DCS BW") },
    };
    int count = (int)(sizeof(specs) / sizeof(specs[0]));

    CFMutableDictionaryRef merged = NULL;
    for (int i = 0; i < count; i++) {
        CFDictionaryRef ch = IOReportCopyChannelsInGroup(specs[i].group, specs[i].subgroup, 0, 0, 0);
        if (!ch) continue;
        if (!merged) {
            merged = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, ch);
        } else {
            IOReportMergeChannels(merged, ch, NULL);
        }
        CFRelease(ch);
    }
    if (!merged) return;

    CFMutableDictionaryRef subbed = NULL;
    IOReportSubscriptionRef sub = IOReportCreateSubscription(NULL, merged, &subbed, 0, NULL);
    CFRelease(merged);
    if (!sub || !subbed) return;

    c->ioReportSub = sub;
    c->ioReportSubbedChannels = subbed;
    c->prevIOReportSample = IOReportCreateSamples(sub, subbed, NULL);
    c->prevSampleTime = CFAbsoluteTimeGetCurrent();
    c->ioReportReady = (c->prevIOReportSample != NULL);
}

static void initStaticInfo(CMCollector *c) {
    CMStaticInfo *si = &c->staticInfo;
    memset(si, 0, sizeof(*si));

    readSysctlString("machdep.cpu.brand_string", si->chipName, sizeof(si->chipName));
    if (si->chipName[0] == '\0') strncpy(si->chipName, "Apple Silicon", sizeof(si->chipName) - 1);

    si->totalMemoryBytes = readSysctlU64("hw.memsize");
    uint64_t wiredMB = readSysctlU64("iogpu.wired_limit_mb");
    si->gpuWiredLimitBytes = wiredMB * 1024ULL * 1024ULL;
    si->totalCPUCores = (uint32_t)readSysctlU64("hw.ncpu");
    si->perfLevel0Cores = (uint32_t)readSysctlU64("hw.perflevel0.physicalcpu");
    si->perfLevel1Cores = (uint32_t)readSysctlU64("hw.perflevel1.physicalcpu");
    readSysctlString("hw.perflevel0.name", si->perfLevel0Name, sizeof(si->perfLevel0Name));
    readSysctlString("hw.perflevel1.name", si->perfLevel1Name, sizeof(si->perfLevel1Name));
    if (si->perfLevel0Name[0] == '\0') strncpy(si->perfLevel0Name, "Performance", sizeof(si->perfLevel0Name) - 1);
    if (si->perfLevel1Name[0] == '\0') strncpy(si->perfLevel1Name, "Efficiency", sizeof(si->perfLevel1Name) - 1);

    // Metal recommended max working set
    NSArray<id<MTLDevice>> *devs = MTLCopyAllDevices();
    if (devs.count > 0) {
        si->metalRecommendedMaxBytes = (uint64_t)devs.firstObject.recommendedMaxWorkingSetSize;
        if (si->gpuWiredLimitBytes == 0) si->gpuWiredLimitBytes = si->metalRecommendedMaxBytes;
    }

    // GPU core count from IOAccelerator
    io_iterator_t it = 0;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &it) == KERN_SUCCESS) {
        io_object_t svc;
        while ((svc = IOIteratorNext(it))) {
            CFMutableDictionaryRef props = NULL;
            if (IORegistryEntryCreateCFProperties(svc, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS && props) {
                NSDictionary *d = (__bridge_transfer NSDictionary *)props;
                NSNumber *cores = d[@"gpu-core-count"];
                if (cores) si->gpuCoreCount = cores.unsignedIntValue;
            }
            IOObjectRelease(svc);
        }
        IOObjectRelease(it);
    }

    si->isDualDie = (strstr(si->chipName, "Ultra") != NULL);
}

// Parse DCS BW histogram (states like "  64GB/s", " 128GB/s", ... upper bounds of 64 GB/s buckets).
// Bucket 0 ([0..64]) is treated as 0 GB/s so idle doesn't show a false floor; buckets i>=1 use midpoint.
static double parseBandwidthHistogramGBs(CFDictionaryRef ch) {
    int32_t cnt = IOReportStateGetCount(ch);
    if (cnt <= 0) return 0.0;
    int64_t totalHits = 0;
    double weightedSum = 0.0;
    double prevUpper = 0.0;
    for (int32_t i = 0; i < cnt; i++) {
        int64_t hits = IOReportStateGetResidency(ch, i);
        NSString *label = (__bridge NSString *)IOReportStateGetNameForIndex(ch, i);
        double upper = label ? label.doubleValue : (double)((i + 1) * 64);
        if (hits > 0) {
            totalHits += hits;
            if (i > 0) {
                double mid = (prevUpper + upper) * 0.5;
                weightedSum += (double)hits * mid;
            }
        }
        prevUpper = upper;
    }
    if (totalHits == 0) return 0.0;
    return weightedSum / (double)totalHits;
}

static void sampleIOAccelerator(CMSample *s) {
    io_iterator_t it = 0;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &it) != KERN_SUCCESS) {
        return;
    }
    io_object_t svc;
    while ((svc = IOIteratorNext(it))) {
        CFMutableDictionaryRef props = NULL;
        if (IORegistryEntryCreateCFProperties(svc, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS && props) {
            NSDictionary *d = (__bridge_transfer NSDictionary *)props;
            NSDictionary *ps = d[@"PerformanceStatistics"];
            if (ps) {
                s->ioAcceleratorAvailable = true;
                s->gpuDeviceUtilPct = [ps[@"Device Utilization %"] intValue];
                s->gpuRendererUtilPct = [ps[@"Renderer Utilization %"] intValue];
                s->gpuTilerUtilPct = [ps[@"Tiler Utilization %"] intValue];
                s->gpuInUseBytes = [ps[@"In use system memory"] unsignedLongLongValue];
                s->gpuAllocBytes = [ps[@"Alloc system memory"] unsignedLongLongValue];
                s->gpuRecoveryCount = [ps[@"recoveryCount"] unsignedLongLongValue];
            }
        }
        IOObjectRelease(svc);
    }
    IOObjectRelease(it);
}

static void sampleIOReport(CMCollector *c, CMSample *s, double now) {
    if (!c->ioReportReady) return;
    CFDictionaryRef curr = IOReportCreateSamples(c->ioReportSub, c->ioReportSubbedChannels, NULL);
    if (!curr) return;
    CFDictionaryRef delta = IOReportCreateSamplesDelta(c->prevIOReportSample, curr, NULL);
    double dt = now - c->prevSampleTime;
    if (dt < 0.05) dt = 0.05;

    CFRelease(c->prevIOReportSample);
    c->prevIOReportSample = curr;
    c->prevSampleTime = now;

    if (!delta) return;
    s->ioReportAvailable = true;

    __block double superSum = 0;
    __block uint32_t superCnt = 0;
    __block double perfSum = 0;
    __block uint32_t perfCnt = 0;
    __block double die0Sum = 0;
    __block uint32_t die0Cnt = 0;
    __block double die1Sum = 0;
    __block uint32_t die1Cnt = 0;

    IOReportIterate(delta, ^int(CFDictionaryRef ch) {
        NSString *g = (__bridge NSString *)IOReportChannelGetGroup(ch) ?: @"";
        NSString *sg = (__bridge NSString *)IOReportChannelGetSubGroup(ch) ?: @"";
        NSString *name = (__bridge NSString *)IOReportChannelGetChannelName(ch) ?: @"";
        int fmt = IOReportChannelGetFormat(ch);

        if ([g isEqualToString:@"Energy Model"] && fmt == 1) {
            if ([name isEqualToString:@"GPU Energy"]) {
                int64_t val = IOReportSimpleGetIntegerValue(ch, 0);
                NSString *unit = (__bridge NSString *)IOReportChannelGetUnitLabel(ch) ?: @"nJ";
                double joules = 0;
                if ([unit isEqualToString:@"nJ"]) joules = (double)val / 1e9;
                else if ([unit isEqualToString:@"uJ"]) joules = (double)val / 1e6;
                else if ([unit isEqualToString:@"mJ"]) joules = (double)val / 1e3;
                if (joules >= 0) s->gpuPowerWatts = joules / dt;
            }
        } else if ([g isEqualToString:@"PMP0"] && [sg isEqualToString:@"DCS BW"] && fmt == 2) {
            if ([name isEqualToString:@"AMCC0 RD"]) s->bwDie0ReadGBs = parseBandwidthHistogramGBs(ch);
            else if ([name isEqualToString:@"AMCC0 WR"]) s->bwDie0WriteGBs = parseBandwidthHistogramGBs(ch);
            else if ([name isEqualToString:@"AMCC0 RD+WR"]) s->bwDie0TotalGBs = parseBandwidthHistogramGBs(ch);
        } else if ([g isEqualToString:@"PMP1"] && [sg isEqualToString:@"DCS BW"] && fmt == 2) {
            if ([name isEqualToString:@"AMCC1 RD"]) s->bwDie1ReadGBs = parseBandwidthHistogramGBs(ch);
            else if ([name isEqualToString:@"AMCC1 WR"]) s->bwDie1WriteGBs = parseBandwidthHistogramGBs(ch);
            else if ([name isEqualToString:@"AMCC1 RD+WR"]) s->bwDie1TotalGBs = parseBandwidthHistogramGBs(ch);
        } else if ([g isEqualToString:@"GPU Stats"]) {
            if ([sg isEqualToString:@"GPU Performance States"] && [name isEqualToString:@"GPUPH"] && fmt == 2) {
                int32_t cnt = IOReportStateGetCount(ch);
                int64_t total = 0, offTicks = 0, activeTicks = 0;
                int64_t bestActive = 0;
                int32_t bestIdx = 0;
                double freqWeighted = 0;
                for (int32_t i = 0; i < cnt; i++) {
                    int64_t r = IOReportStateGetResidency(ch, i);
                    NSString *sn = (__bridge NSString *)IOReportStateGetNameForIndex(ch, i) ?: @"";
                    total += r;
                    if ([sn isEqualToString:@"OFF"] || i == 0) {
                        offTicks += r;
                    } else {
                        activeTicks += r;
                        if (r > bestActive) { bestActive = r; bestIdx = i; }
                        // Map P-state index (1-based) to pmgr frequency table
                        if (c->gpuFreqCount > 0) {
                            uint32_t fi = (uint32_t)(i - 1);
                            if (fi >= c->gpuFreqCount) fi = c->gpuFreqCount - 1;
                            freqWeighted += (double)r * c->gpuFreqTableMHz[fi];
                        }
                    }
                }
                if (total > 0) {
                    s->gpuActiveResidencyPct = 100.0 * (double)(total - offTicks) / (double)total;
                }
                s->gpuDominantPState = bestIdx;
                if (activeTicks > 0 && c->gpuFreqCount > 0) {
                    s->gpuFreqMHz = freqWeighted / (double)activeTicks;
                }
            } else if ([sg isEqualToString:@"CLTM-induced GPU Performance States"] && [name isEqualToString:@"GPU_CLTM"] && fmt == 2) {
                int32_t cnt = IOReportStateGetCount(ch);
                int64_t total = 0, noCltm = 0;
                for (int32_t i = 0; i < cnt; i++) {
                    int64_t r = IOReportStateGetResidency(ch, i);
                    NSString *sn = (__bridge NSString *)IOReportStateGetNameForIndex(ch, i) ?: @"";
                    total += r;
                    if ([sn isEqualToString:@"NO_CLTM"] || [sn isEqualToString:@"OFF"]) noCltm += r;
                }
                if (total > 0 && (total - noCltm) > (total / 100)) {
                    s->gpuThermalThrottling = true;
                }
            } else if ([sg isEqualToString:@"PPM Target as % of Max GPU Power"] && [name isEqualToString:@"GPU_PPM"] && fmt == 2) {
                int32_t cnt = IOReportStateGetCount(ch);
                int64_t total = 0;
                double wSum = 0;
                for (int32_t i = 0; i < cnt; i++) {
                    int64_t r = IOReportStateGetResidency(ch, i);
                    NSString *sn = (__bridge NSString *)IOReportStateGetNameForIndex(ch, i) ?: @"100%";
                    total += r;
                    wSum += (double)r * sn.doubleValue;
                }
                s->gpuPPMTargetPct = (total > 0) ? (wSum / (double)total) : 100.0;
            } else if ([sg isEqualToString:@"GPU Throttler Counters"] && [name isEqualToString:@"Throttle Counter Total"] && fmt == 1) {
                s->gpuThrottleEventsDelta = IOReportSimpleGetIntegerValue(ch, 0);
            }
        } else if ([g isEqualToString:@"CPU Stats"] && [sg isEqualToString:@"CPU Core Performance States"] && fmt == 2) {
            int32_t cnt = IOReportStateGetCount(ch);
            int64_t total = 0, idle = 0;
            for (int32_t i = 0; i < cnt; i++) {
                int64_t r = IOReportStateGetResidency(ch, i);
                NSString *sn = (__bridge NSString *)IOReportStateGetNameForIndex(ch, i) ?: @"";
                total += r;
                if ([sn isEqualToString:@"IDLE"] || [sn isEqualToString:@"DOWN"] || [sn isEqualToString:@"OFF"]) {
                    idle += r;
                }
            }
            double util = (total > 0) ? (100.0 * (double)(total - idle) / (double)total) : 0.0;
            BOOL isSuper = [name containsString:@"PCPU"] || [name containsString:@"PACC"];
            BOOL isPerf = [name containsString:@"MCPU"] || [name containsString:@"ECPU"];
            if (isSuper && superCnt < CM_MAX_CORES) {
                s->superCoreUtil[superCnt++] = util;
                superSum += util;
            } else if (isPerf && perfCnt < CM_MAX_CORES) {
                s->perfCoreUtil[perfCnt++] = util;
                perfSum += util;
            }
            if ([name hasPrefix:@"DIE_0"]) { die0Sum += util; die0Cnt++; }
            else if ([name hasPrefix:@"DIE_1"]) { die1Sum += util; die1Cnt++; }
        }
        return 0;
    });

    s->bwTotalGBs = s->bwDie0TotalGBs + s->bwDie1TotalGBs;
    if (s->bwTotalGBs == 0.0) {
        s->bwTotalGBs = s->bwDie0ReadGBs + s->bwDie0WriteGBs + s->bwDie1ReadGBs + s->bwDie1WriteGBs;
    }

    s->superCoreCount = superCnt;
    s->perfCoreCount = perfCnt;
    if (superCnt > 0) s->cpuSuperPct = superSum / (double)superCnt;
    if (perfCnt > 0) s->cpuPerfPct = perfSum / (double)perfCnt;
    if (superCnt + perfCnt > 0) {
        s->cpuTotalPct = (superSum + perfSum) / (double)(superCnt + perfCnt);
    }
    if (die0Cnt > 0) s->cpuDie0Pct = die0Sum / (double)die0Cnt;
    if (die1Cnt > 0) s->cpuDie1Pct = die1Sum / (double)die1Cnt;

    CFRelease(delta);
}

static void sampleMachCPUFallback(CMCollector *c, CMSample *s) {
    natural_t numCPUs = 0;
    processor_info_array_t info = NULL;
    mach_msg_type_number_t numInfo = 0;
    if (host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPUs, &info, &numInfo) != KERN_SUCCESS) {
        return;
    }
    uint32_t count = (uint32_t)MIN(numCPUs, CM_MAX_CORES);
    double totalPct = 0;
    if (c->hasPrevCPUTicks && c->prevCPUCount == count) {
        for (uint32_t i = 0; i < count; i++) {
            uint64_t u = (uint64_t)info[i * CPU_STATE_MAX + CPU_STATE_USER];
            uint64_t sy = (uint64_t)info[i * CPU_STATE_MAX + CPU_STATE_SYSTEM];
            uint64_t n = (uint64_t)info[i * CPU_STATE_MAX + CPU_STATE_NICE];
            uint64_t id = (uint64_t)info[i * CPU_STATE_MAX + CPU_STATE_IDLE];
            uint64_t du = u - c->prevCPUTicks[i][0];
            uint64_t dsy = sy - c->prevCPUTicks[i][1];
            uint64_t dn = n - c->prevCPUTicks[i][2];
            uint64_t did = id - c->prevCPUTicks[i][3];
            uint64_t dtot = du + dsy + dn + did;
            double pct = dtot > 0 ? 100.0 * (double)(du + dsy + dn) / (double)dtot : 0.0;
            totalPct += pct;
        }
        if (s->superCoreCount == 0 && s->perfCoreCount == 0 && count > 0) {
            s->cpuTotalPct = totalPct / (double)count;
        }
    }
    for (uint32_t i = 0; i < count; i++) {
        c->prevCPUTicks[i][0] = (uint64_t)info[i * CPU_STATE_MAX + CPU_STATE_USER];
        c->prevCPUTicks[i][1] = (uint64_t)info[i * CPU_STATE_MAX + CPU_STATE_SYSTEM];
        c->prevCPUTicks[i][2] = (uint64_t)info[i * CPU_STATE_MAX + CPU_STATE_NICE];
        c->prevCPUTicks[i][3] = (uint64_t)info[i * CPU_STATE_MAX + CPU_STATE_IDLE];
    }
    c->prevCPUCount = count;
    c->hasPrevCPUTicks = true;
    vm_deallocate(mach_task_self(), (vm_address_t)info, numInfo * sizeof(integer_t));
}

static void sampleMemory(CMCollector *c, CMSample *s) {
    vm_size_t pageSize = 16384;
    host_page_size(mach_host_self(), &pageSize);

    vm_statistics64_data_t vm;
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    if (host_statistics64(mach_host_self(), HOST_VM_INFO64, (host_info64_t)&vm, &count) == KERN_SUCCESS) {
        s->memWiredBytes = (uint64_t)vm.wire_count * (uint64_t)pageSize;
        s->memActiveBytes = (uint64_t)vm.active_count * (uint64_t)pageSize;
        s->memInactiveBytes = (uint64_t)vm.inactive_count * (uint64_t)pageSize;
        s->memCompressedBytes = (uint64_t)vm.compressor_page_count * (uint64_t)pageSize;
        s->memFreeBytes = (uint64_t)(vm.free_count + vm.speculative_count) * (uint64_t)pageSize;

        if (c->hasPrevSwap) {
            s->swapInsDelta = (vm.swapins >= c->prevSwapIns) ? (vm.swapins - c->prevSwapIns) : 0;
            s->swapOutsDelta = (vm.swapouts >= c->prevSwapOuts) ? (vm.swapouts - c->prevSwapOuts) : 0;
        }
        c->prevSwapIns = vm.swapins;
        c->prevSwapOuts = vm.swapouts;
        c->hasPrevSwap = true;
    }

    struct xsw_usage xsw;
    size_t xswLen = sizeof(xsw);
    if (sysctlbyname("vm.swapusage", &xsw, &xswLen, NULL, 0) == 0) {
        s->swapTotalBytes = xsw.xsu_total;
        s->swapUsedBytes = xsw.xsu_used;
    }

    s->memoryPressureLevel = readSysctlI32("kern.memorystatus_vm_pressure_level");
    s->memoryAvailablePct = readSysctlI32("kern.memorystatus_level");
}

static void sampleSMC(CMCollector *c, CMSample *s) {
    if (!c->smcReady) return;
    s->smcAvailable = true;

    // Fans
    s->fanCount = c->staticInfo.fanCount;
    for (uint32_t i = 0; i < s->fanCount; i++) {
        smcReadCached(c->smcConn, &c->smcFanAc[i], &s->fanActualRPM[i]);
        smcReadCached(c->smcConn, &c->smcFanTg[i], &s->fanTargetRPM[i]);
        smcReadCached(c->smcConn, &c->smcFanMn[i], &s->fanMinRPM[i]);
        smcReadCached(c->smcConn, &c->smcFanMx[i], &s->fanMaxRPM[i]);
    }

    // Power
    double v = 0;
    if (smcReadCached(c->smcConn, &c->smcPD0R, &v) && v > 0) s->powerSystemWatts = v;
    else if (smcReadCached(c->smcConn, &c->smcPSTR, &v) && v > 0) s->powerSystemWatts = v;
    if (smcReadCached(c->smcConn, &c->smcPSVR, &v) && v >= 0) s->powerSoCWatts = v;
    if (smcReadCached(c->smcConn, &c->smcPMVR, &v) && v >= 0) s->powerMemWatts = v;
    if (smcReadCached(c->smcConn, &c->smcPZC0, &v) && v >= 0) s->powerDie0Watts = v;
    if (smcReadCached(c->smcConn, &c->smcPZC1, &v) && v >= 0) s->powerDie1Watts = v;

    // Temperatures
    double dieMax = 0, dieSum = 0;
    int dieCnt = 0;
    for (int i = 0; i < 16; i++) {
        if (smcReadCached(c->smcConn, &c->smcTPD[i], &v) && v > 5.0 && v < 130.0) {
            dieSum += v;
            dieCnt++;
            if (v > dieMax) dieMax = v;
        }
    }
    if (smcReadCached(c->smcConn, &c->smcTPDX, &v) && v > 5.0 && v < 130.0) {
        s->tempDiePeakC = MAX(v, dieMax);
    } else {
        s->tempDiePeakC = dieMax;
    }
    if (dieCnt > 0) s->tempDieAvgC = dieSum / (double)dieCnt;

    double hot = s->tempDiePeakC;
    if (smcReadCached(c->smcConn, &c->smcTCMb, &v) && v > 5.0 && v < 130.0 && v > hot) hot = v;
    if (smcReadCached(c->smcConn, &c->smcTCDX, &v) && v > 5.0 && v < 130.0 && v > hot) hot = v;
    s->tempHotspotC = hot;

    if (smcReadCached(c->smcConn, &c->smcTMVR, &v) && v > 5.0 && v < 130.0) s->tempVRMOrMemC = v;

    double nandSum = 0;
    int nandCnt = 0;
    for (int i = 0; i < 4; i++) {
        if (smcReadCached(c->smcConn, &c->smcTN[i], &v) && v > 5.0 && v < 110.0) {
            nandSum += v;
            nandCnt++;
        }
    }
    if (nandCnt > 0) s->tempNandC = nandSum / (double)nandCnt;
}

static void sampleIOHIDTempFallback(CMCollector *c, CMSample *s) {
    if (s->tempDiePeakC > 5.0) return;
    if (!c->hidTempClient) {
        c->hidTempClient = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
        if (!c->hidTempClient) return;
        NSDictionary *match = @{@"PrimaryUsagePage": @(0xff00), @"PrimaryUsage": @(5)};
        IOHIDEventSystemClientSetMatching(c->hidTempClient, (__bridge CFDictionaryRef)match);
    }
    CFArrayRef svcs = IOHIDEventSystemClientCopyServices(c->hidTempClient);
    if (!svcs) return;
    CFIndex n = CFArrayGetCount(svcs);
    double dieMax = 0, dieSum = 0;
    int dieCnt = 0;
    for (CFIndex i = 0; i < n; i++) {
        IOHIDServiceClientRef svc = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(svcs, i);
        NSString *prod = (__bridge_transfer NSString *)IOHIDServiceClientCopyProperty(svc, CFSTR("Product"));
        IOHIDEventRef ev = IOHIDServiceClientCopyEvent(svc, kIOHIDEventTypeTemperature, 0, 0);
        if (!ev) continue;
        double val = IOHIDEventGetFloatValue(ev, kIOHIDEventTypeTemperature << 16);
        CFRelease(ev);
        if (val < 5.0 || val > 130.0) continue;
        if ([prod containsString:@"tdie"]) {
            dieSum += val;
            dieCnt++;
            if (val > dieMax) dieMax = val;
        } else if ([prod containsString:@"NAND"] && s->tempNandC <= 0) {
            s->tempNandC = val;
        }
    }
    CFRelease(svcs);
    if (dieCnt > 0) {
        s->tempDiePeakC = dieMax;
        s->tempDieAvgC = dieSum / (double)dieCnt;
        s->tempHotspotC = dieMax;
    }
}

static int compareProcMemDesc(const void *a, const void *b) {
    const CMProcessMem *pa = (const CMProcessMem *)a;
    const CMProcessMem *pb = (const CMProcessMem *)b;
    if (pb->physFootprintBytes > pa->physFootprintBytes) return 1;
    if (pb->physFootprintBytes < pa->physFootprintBytes) return -1;
    return 0;
}

static void sampleTopProcesses(CMSample *s) {
    int bufSize = proc_listallpids(NULL, 0);
    if (bufSize <= 0) return;
    int maxPids = bufSize + 64;
    pid_t *pids = (pid_t *)malloc(sizeof(pid_t) * (size_t)maxPids);
    if (!pids) return;
    int nPids = proc_listallpids(pids, (int)(sizeof(pid_t) * (size_t)maxPids));
    if (nPids <= 0) { free(pids); return; }

    CMProcessMem *found = (CMProcessMem *)malloc(sizeof(CMProcessMem) * (size_t)nPids);
    if (!found) { free(pids); return; }
    int foundCnt = 0;

    for (int i = 0; i < nPids; i++) {
        pid_t pid = pids[i];
        if (pid <= 0) continue;
        struct rusage_info_v4 ru;
        if (proc_pid_rusage(pid, RUSAGE_INFO_V4, (rusage_info_t *)&ru) == 0) {
            if (ru.ri_phys_footprint >= (32ULL * 1024ULL * 1024ULL)) { // >= 32 MB
                CMProcessMem *pm = &found[foundCnt];
                pm->pid = (int32_t)pid;
                pm->physFootprintBytes = ru.ri_phys_footprint;
                pm->name[0] = '\0';
                proc_name(pid, pm->name, (uint32_t)sizeof(pm->name));
                if (pm->name[0] == '\0') snprintf(pm->name, sizeof(pm->name), "pid %d", pid);
                foundCnt++;
            }
        }
    }

    qsort(found, (size_t)foundCnt, sizeof(CMProcessMem), compareProcMemDesc);
    uint32_t take = (uint32_t)MIN(foundCnt, CM_MAX_PROCS);
    s->topProcCount = take;
    for (uint32_t i = 0; i < take; i++) {
        s->topProcs[i] = found[i];
    }

    free(found);
    free(pids);
}

// ---- Public C API ----

CMCollector *cm_collector_create(void) {
    @autoreleasepool {
        CMCollector *c = (CMCollector *)calloc(1, sizeof(CMCollector));
        if (!c) return NULL;
        initStaticInfo(c);
        initPMGRGPUFreqs(c);
        initSMC(c);
        initIOReport(c);
        return c;
    }
}

void cm_collector_destroy(CMCollector *c) {
    if (!c) return;
    if (c->prevIOReportSample) CFRelease(c->prevIOReportSample);
    if (c->ioReportSubbedChannels) CFRelease(c->ioReportSubbedChannels);
    if (c->smcReady) IOServiceClose(c->smcConn);
    if (c->hidTempClient) CFRelease(c->hidTempClient);
    free(c);
}

void cm_collector_get_static_info(CMCollector *c, CMStaticInfo *outInfo) {
    if (!c || !outInfo) return;
    *outInfo = c->staticInfo;
}

bool cm_collector_sample(CMCollector *c, CMSample *outSample) {
    if (!c || !outSample) return false;
    @autoreleasepool {
        memset(outSample, 0, sizeof(*outSample));
        double now = CFAbsoluteTimeGetCurrent();
        outSample->timestamp = now;
        outSample->gpuPPMTargetPct = 100.0;
        outSample->thermalState = (int32_t)[NSProcessInfo processInfo].thermalState;

        sampleIOAccelerator(outSample);
        sampleIOReport(c, outSample, now);
        sampleMachCPUFallback(c, outSample);
        sampleMemory(c, outSample);
        sampleSMC(c, outSample);
        sampleIOHIDTempFallback(c, outSample);
        sampleTopProcesses(outSample);
        return true;
    }
}
