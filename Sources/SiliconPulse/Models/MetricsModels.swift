import Foundation
import SwiftUI
import CMetrics

struct HardwareInfo {
    let chipName: String
    let totalMemoryGB: Double
    let gpuWiredLimitGB: Double
    let totalCPUCores: Int
    let perfLevel0Cores: Int
    let perfLevel0Name: String
    let perfLevel1Cores: Int
    let perfLevel1Name: String
    let gpuCoreCount: Int
    let fanCount: Int
    let isDualDie: Bool

    static let empty = HardwareInfo(
        chipName: "Apple Silicon",
        totalMemoryGB: 0,
        gpuWiredLimitGB: 0,
        totalCPUCores: 0,
        perfLevel0Cores: 0,
        perfLevel0Name: "Super",
        perfLevel1Cores: 0,
        perfLevel1Name: "Performance",
        gpuCoreCount: 0,
        fanCount: 0,
        isDualDie: false
    )

    init(
        chipName: String,
        totalMemoryGB: Double,
        gpuWiredLimitGB: Double,
        totalCPUCores: Int,
        perfLevel0Cores: Int,
        perfLevel0Name: String,
        perfLevel1Cores: Int,
        perfLevel1Name: String,
        gpuCoreCount: Int,
        fanCount: Int,
        isDualDie: Bool
    ) {
        self.chipName = chipName
        self.totalMemoryGB = totalMemoryGB
        self.gpuWiredLimitGB = gpuWiredLimitGB
        self.totalCPUCores = totalCPUCores
        self.perfLevel0Cores = perfLevel0Cores
        self.perfLevel0Name = perfLevel0Name
        self.perfLevel1Cores = perfLevel1Cores
        self.perfLevel1Name = perfLevel1Name
        self.gpuCoreCount = gpuCoreCount
        self.fanCount = fanCount
        self.isDualDie = isDualDie
    }

    init(cInfo: CMStaticInfo) {
        self.chipName = withUnsafeBytes(of: cInfo.chipName) { ptr in
            String(cString: ptr.baseAddress!.assumingMemoryBound(to: CChar.self))
        }
        let gb = 1024.0 * 1024.0 * 1024.0
        self.totalMemoryGB = Double(cInfo.totalMemoryBytes) / gb
        self.gpuWiredLimitGB = Double(cInfo.gpuWiredLimitBytes) / gb
        self.totalCPUCores = Int(cInfo.totalCPUCores)
        self.perfLevel0Cores = Int(cInfo.perfLevel0Cores)
        self.perfLevel0Name = withUnsafeBytes(of: cInfo.perfLevel0Name) { ptr in
            String(cString: ptr.baseAddress!.assumingMemoryBound(to: CChar.self))
        }
        self.perfLevel1Cores = Int(cInfo.perfLevel1Cores)
        self.perfLevel1Name = withUnsafeBytes(of: cInfo.perfLevel1Name) { ptr in
            String(cString: ptr.baseAddress!.assumingMemoryBound(to: CChar.self))
        }
        self.gpuCoreCount = Int(cInfo.gpuCoreCount)
        self.fanCount = Int(cInfo.fanCount)
        self.isDualDie = cInfo.isDualDie
    }
}

struct ProcessMemoryItem: Identifiable {
    let pid: Int32
    let name: String
    let memoryGB: Double
    var id: Int32 { pid }
}

struct FanReading: Identifiable {
    let index: Int
    let actualRPM: Double
    let targetRPM: Double
    let minRPM: Double
    let maxRPM: Double
    var id: Int { index }

    var fractionOfMax: Double {
        guard maxRPM > minRPM else { return 0 }
        return min(max((actualRPM - minRPM) / (maxRPM - minRPM), 0), 1)
    }
}

enum HealthSeverity {
    case nominal
    case warning
    case critical

    var color: Color {
        switch self {
        case .nominal: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }
}

struct AlertBadge: Identifiable {
    let id: String
    let label: String
    let severity: HealthSeverity
}

struct MetricsSnapshot {
    let timestamp: Date

    // GPU
    let gpuDeviceUtilPct: Double
    let gpuRendererUtilPct: Double
    let gpuTilerUtilPct: Double
    let gpuActiveResidencyPct: Double
    let gpuDominantPState: Int
    let gpuFreqMHz: Double
    let gpuInUseGB: Double
    let gpuAllocGB: Double
    let gpuRecoveryCount: UInt64
    let gpuThermalThrottling: Bool
    let gpuPPMTargetPct: Double
    let gpuThrottleEventsDelta: Int64
    let gpuPowerWatts: Double

    // Memory Bandwidth
    let bwDie0ReadGBs: Double
    let bwDie0WriteGBs: Double
    let bwDie0TotalGBs: Double
    let bwDie1ReadGBs: Double
    let bwDie1WriteGBs: Double
    let bwDie1TotalGBs: Double
    let bwTotalGBs: Double

    // Unified Memory
    let memWiredGB: Double
    let memActiveGB: Double
    let memInactiveGB: Double
    let memCompressedGB: Double
    let memFreeGB: Double
    let swapTotalGB: Double
    let swapUsedGB: Double
    let swapInsDelta: UInt64
    let swapOutsDelta: UInt64
    let memoryPressureLevel: Int
    let memoryAvailablePct: Int

    // CPU
    let cpuTotalPct: Double
    let cpuSuperPct: Double
    let cpuPerfPct: Double
    let cpuDie0Pct: Double
    let cpuDie1Pct: Double
    let superCoreUtil: [Double]
    let perfCoreUtil: [Double]

    // Power
    let powerSystemWatts: Double
    let powerSoCWatts: Double
    let powerMemWatts: Double
    let powerDie0Watts: Double
    let powerDie1Watts: Double

    // Thermals
    let tempDiePeakC: Double
    let tempDieAvgC: Double
    let tempHotspotC: Double
    let tempVRMOrMemC: Double
    let tempNandC: Double
    let thermalState: Int

    // Fans
    let fans: [FanReading]

    // Top processes
    let topProcs: [ProcessMemoryItem]

    // Diagnostics
    let smcAvailable: Bool
    let ioReportAvailable: Bool
    let ioAcceleratorAvailable: Bool

    var averageFanRPM: Double {
        guard !fans.isEmpty else { return 0 }
        return fans.map(\.actualRPM).reduce(0, +) / Double(fans.count)
    }

    var thermalStateLabel: String {
        switch thermalState {
        case 0: return "Nominal"
        case 1: return "Fair"
        case 2: return "Serious"
        case 3: return "Critical"
        default: return "Unknown"
        }
    }

    var memoryPressureLabel: String {
        switch memoryPressureLevel {
        case 1: return "Normal"
        case 2: return "Warn"
        case 4: return "Critical"
        default: return "Normal"
        }
    }

    static let empty = MetricsSnapshot(
        timestamp: Date(),
        gpuDeviceUtilPct: 0, gpuRendererUtilPct: 0, gpuTilerUtilPct: 0,
        gpuActiveResidencyPct: 0, gpuDominantPState: 0, gpuFreqMHz: 0,
        gpuInUseGB: 0, gpuAllocGB: 0, gpuRecoveryCount: 0,
        gpuThermalThrottling: false, gpuPPMTargetPct: 100, gpuThrottleEventsDelta: 0,
        gpuPowerWatts: 0,
        bwDie0ReadGBs: 0, bwDie0WriteGBs: 0, bwDie0TotalGBs: 0,
        bwDie1ReadGBs: 0, bwDie1WriteGBs: 0, bwDie1TotalGBs: 0, bwTotalGBs: 0,
        memWiredGB: 0, memActiveGB: 0, memInactiveGB: 0, memCompressedGB: 0, memFreeGB: 0,
        swapTotalGB: 0, swapUsedGB: 0, swapInsDelta: 0, swapOutsDelta: 0,
        memoryPressureLevel: 1, memoryAvailablePct: 100,
        cpuTotalPct: 0, cpuSuperPct: 0, cpuPerfPct: 0, cpuDie0Pct: 0, cpuDie1Pct: 0,
        superCoreUtil: [], perfCoreUtil: [],
        powerSystemWatts: 0, powerSoCWatts: 0, powerMemWatts: 0, powerDie0Watts: 0, powerDie1Watts: 0,
        tempDiePeakC: 0, tempDieAvgC: 0, tempHotspotC: 0, tempVRMOrMemC: 0, tempNandC: 0,
        thermalState: 0,
        fans: [], topProcs: [],
        smcAvailable: false, ioReportAvailable: false, ioAcceleratorAvailable: false
    )

    init(
        timestamp: Date,
        gpuDeviceUtilPct: Double, gpuRendererUtilPct: Double, gpuTilerUtilPct: Double,
        gpuActiveResidencyPct: Double, gpuDominantPState: Int, gpuFreqMHz: Double,
        gpuInUseGB: Double, gpuAllocGB: Double, gpuRecoveryCount: UInt64,
        gpuThermalThrottling: Bool, gpuPPMTargetPct: Double, gpuThrottleEventsDelta: Int64,
        gpuPowerWatts: Double,
        bwDie0ReadGBs: Double, bwDie0WriteGBs: Double, bwDie0TotalGBs: Double,
        bwDie1ReadGBs: Double, bwDie1WriteGBs: Double, bwDie1TotalGBs: Double, bwTotalGBs: Double,
        memWiredGB: Double, memActiveGB: Double, memInactiveGB: Double, memCompressedGB: Double, memFreeGB: Double,
        swapTotalGB: Double, swapUsedGB: Double, swapInsDelta: UInt64, swapOutsDelta: UInt64,
        memoryPressureLevel: Int, memoryAvailablePct: Int,
        cpuTotalPct: Double, cpuSuperPct: Double, cpuPerfPct: Double, cpuDie0Pct: Double, cpuDie1Pct: Double,
        superCoreUtil: [Double], perfCoreUtil: [Double],
        powerSystemWatts: Double, powerSoCWatts: Double, powerMemWatts: Double, powerDie0Watts: Double, powerDie1Watts: Double,
        tempDiePeakC: Double, tempDieAvgC: Double, tempHotspotC: Double, tempVRMOrMemC: Double, tempNandC: Double,
        thermalState: Int,
        fans: [FanReading], topProcs: [ProcessMemoryItem],
        smcAvailable: Bool, ioReportAvailable: Bool, ioAcceleratorAvailable: Bool
    ) {
        self.timestamp = timestamp
        self.gpuDeviceUtilPct = gpuDeviceUtilPct
        self.gpuRendererUtilPct = gpuRendererUtilPct
        self.gpuTilerUtilPct = gpuTilerUtilPct
        self.gpuActiveResidencyPct = gpuActiveResidencyPct
        self.gpuDominantPState = gpuDominantPState
        self.gpuFreqMHz = gpuFreqMHz
        self.gpuInUseGB = gpuInUseGB
        self.gpuAllocGB = gpuAllocGB
        self.gpuRecoveryCount = gpuRecoveryCount
        self.gpuThermalThrottling = gpuThermalThrottling
        self.gpuPPMTargetPct = gpuPPMTargetPct
        self.gpuThrottleEventsDelta = gpuThrottleEventsDelta
        self.gpuPowerWatts = gpuPowerWatts
        self.bwDie0ReadGBs = bwDie0ReadGBs
        self.bwDie0WriteGBs = bwDie0WriteGBs
        self.bwDie0TotalGBs = bwDie0TotalGBs
        self.bwDie1ReadGBs = bwDie1ReadGBs
        self.bwDie1WriteGBs = bwDie1WriteGBs
        self.bwDie1TotalGBs = bwDie1TotalGBs
        self.bwTotalGBs = bwTotalGBs
        self.memWiredGB = memWiredGB
        self.memActiveGB = memActiveGB
        self.memInactiveGB = memInactiveGB
        self.memCompressedGB = memCompressedGB
        self.memFreeGB = memFreeGB
        self.swapTotalGB = swapTotalGB
        self.swapUsedGB = swapUsedGB
        self.swapInsDelta = swapInsDelta
        self.swapOutsDelta = swapOutsDelta
        self.memoryPressureLevel = memoryPressureLevel
        self.memoryAvailablePct = memoryAvailablePct
        self.cpuTotalPct = cpuTotalPct
        self.cpuSuperPct = cpuSuperPct
        self.cpuPerfPct = cpuPerfPct
        self.cpuDie0Pct = cpuDie0Pct
        self.cpuDie1Pct = cpuDie1Pct
        self.superCoreUtil = superCoreUtil
        self.perfCoreUtil = perfCoreUtil
        self.powerSystemWatts = powerSystemWatts
        self.powerSoCWatts = powerSoCWatts
        self.powerMemWatts = powerMemWatts
        self.powerDie0Watts = powerDie0Watts
        self.powerDie1Watts = powerDie1Watts
        self.tempDiePeakC = tempDiePeakC
        self.tempDieAvgC = tempDieAvgC
        self.tempHotspotC = tempHotspotC
        self.tempVRMOrMemC = tempVRMOrMemC
        self.tempNandC = tempNandC
        self.thermalState = thermalState
        self.fans = fans
        self.topProcs = topProcs
        self.smcAvailable = smcAvailable
        self.ioReportAvailable = ioReportAvailable
        self.ioAcceleratorAvailable = ioAcceleratorAvailable
    }

    init(cSample s: CMSample) {
        let gb = 1024.0 * 1024.0 * 1024.0
        self.timestamp = Date()
        self.gpuDeviceUtilPct = Double(s.gpuDeviceUtilPct)
        self.gpuRendererUtilPct = Double(s.gpuRendererUtilPct)
        self.gpuTilerUtilPct = Double(s.gpuTilerUtilPct)
        self.gpuActiveResidencyPct = s.gpuActiveResidencyPct
        self.gpuDominantPState = Int(s.gpuDominantPState)
        self.gpuFreqMHz = s.gpuFreqMHz
        self.gpuInUseGB = Double(s.gpuInUseBytes) / gb
        self.gpuAllocGB = Double(s.gpuAllocBytes) / gb
        self.gpuRecoveryCount = s.gpuRecoveryCount
        self.gpuThermalThrottling = s.gpuThermalThrottling
        self.gpuPPMTargetPct = s.gpuPPMTargetPct
        self.gpuThrottleEventsDelta = s.gpuThrottleEventsDelta
        self.gpuPowerWatts = s.gpuPowerWatts

        self.bwDie0ReadGBs = s.bwDie0ReadGBs
        self.bwDie0WriteGBs = s.bwDie0WriteGBs
        self.bwDie0TotalGBs = s.bwDie0TotalGBs
        self.bwDie1ReadGBs = s.bwDie1ReadGBs
        self.bwDie1WriteGBs = s.bwDie1WriteGBs
        self.bwDie1TotalGBs = s.bwDie1TotalGBs
        self.bwTotalGBs = s.bwTotalGBs

        self.memWiredGB = Double(s.memWiredBytes) / gb
        self.memActiveGB = Double(s.memActiveBytes) / gb
        self.memInactiveGB = Double(s.memInactiveBytes) / gb
        self.memCompressedGB = Double(s.memCompressedBytes) / gb
        self.memFreeGB = Double(s.memFreeBytes) / gb
        self.swapTotalGB = Double(s.swapTotalBytes) / gb
        self.swapUsedGB = Double(s.swapUsedBytes) / gb
        self.swapInsDelta = s.swapInsDelta
        self.swapOutsDelta = s.swapOutsDelta
        self.memoryPressureLevel = Int(s.memoryPressureLevel)
        self.memoryAvailablePct = Int(s.memoryAvailablePct)

        self.cpuTotalPct = s.cpuTotalPct
        self.cpuSuperPct = s.cpuSuperPct
        self.cpuPerfPct = s.cpuPerfPct
        self.cpuDie0Pct = s.cpuDie0Pct
        self.cpuDie1Pct = s.cpuDie1Pct

        var sup: [Double] = []
        let supCnt = Int(min(s.superCoreCount, UInt32(CM_MAX_CORES)))
        withUnsafeBytes(of: s.superCoreUtil) { raw in
            let buf = raw.bindMemory(to: Double.self)
            for i in 0..<supCnt { sup.append(buf[i]) }
        }
        self.superCoreUtil = sup

        var perf: [Double] = []
        let perfCnt = Int(min(s.perfCoreCount, UInt32(CM_MAX_CORES)))
        withUnsafeBytes(of: s.perfCoreUtil) { raw in
            let buf = raw.bindMemory(to: Double.self)
            for i in 0..<perfCnt { perf.append(buf[i]) }
        }
        self.perfCoreUtil = perf

        self.powerSystemWatts = s.powerSystemWatts
        self.powerSoCWatts = s.powerSoCWatts
        self.powerMemWatts = s.powerMemWatts
        self.powerDie0Watts = s.powerDie0Watts
        self.powerDie1Watts = s.powerDie1Watts

        self.tempDiePeakC = s.tempDiePeakC
        self.tempDieAvgC = s.tempDieAvgC
        self.tempHotspotC = s.tempHotspotC
        self.tempVRMOrMemC = s.tempVRMOrMemC
        self.tempNandC = s.tempNandC
        self.thermalState = Int(s.thermalState)

        var fanList: [FanReading] = []
        let fCnt = Int(min(s.fanCount, UInt32(CM_MAX_FANS)))
        withUnsafeBytes(of: s.fanActualRPM) { actRaw in
            withUnsafeBytes(of: s.fanTargetRPM) { tgtRaw in
                withUnsafeBytes(of: s.fanMinRPM) { minRaw in
                    withUnsafeBytes(of: s.fanMaxRPM) { maxRaw in
                        let act = actRaw.bindMemory(to: Double.self)
                        let tgt = tgtRaw.bindMemory(to: Double.self)
                        let mn = minRaw.bindMemory(to: Double.self)
                        let mx = maxRaw.bindMemory(to: Double.self)
                        for i in 0..<fCnt {
                            fanList.append(FanReading(
                                index: i,
                                actualRPM: act[i],
                                targetRPM: tgt[i],
                                minRPM: mn[i],
                                maxRPM: mx[i]
                            ))
                        }
                    }
                }
            }
        }
        self.fans = fanList

        var procs: [ProcessMemoryItem] = []
        let pCnt = Int(min(s.topProcCount, UInt32(CM_MAX_PROCS)))
        withUnsafeBytes(of: s.topProcs) { raw in
            let buf = raw.bindMemory(to: CMProcessMem.self)
            for i in 0..<pCnt {
                let item = buf[i]
                let pName = withUnsafeBytes(of: item.name) { nRaw in
                    String(cString: nRaw.baseAddress!.assumingMemoryBound(to: CChar.self))
                }
                procs.append(ProcessMemoryItem(
                    pid: item.pid,
                    name: pName,
                    memoryGB: Double(item.physFootprintBytes) / gb
                ))
            }
        }
        self.topProcs = procs

        self.smcAvailable = s.smcAvailable
        self.ioReportAvailable = s.ioReportAvailable
        self.ioAcceleratorAvailable = s.ioAcceleratorAvailable
    }

    func alerts(for hw: HardwareInfo) -> [AlertBadge] {
        var list: [AlertBadge] = []
        if gpuThermalThrottling {
            list.append(AlertBadge(id: "cltm", label: "GPU CLTM Throttle", severity: .critical))
        }
        if thermalState >= 2 {
            list.append(AlertBadge(id: "therm", label: "Thermal: \(thermalStateLabel)", severity: .critical))
        } else if thermalState == 1 {
            list.append(AlertBadge(id: "therm", label: "Thermal: Fair", severity: .warning))
        }
        if hw.gpuWiredLimitGB > 0 {
            let ratio = gpuInUseGB / hw.gpuWiredLimitGB
            if ratio >= 0.92 {
                list.append(AlertBadge(id: "gpumem", label: "GPU Mem \(Int(ratio * 100))%", severity: .critical))
            } else if ratio >= 0.85 {
                list.append(AlertBadge(id: "gpumem", label: "GPU Mem \(Int(ratio * 100))%", severity: .warning))
            }
        }
        if swapInsDelta > 0 || swapOutsDelta > 0 {
            list.append(AlertBadge(id: "swap", label: "Active Swapping", severity: .warning))
        }
        if memoryPressureLevel >= 4 {
            list.append(AlertBadge(id: "memp", label: "Mem Pressure Critical", severity: .critical))
        } else if memoryPressureLevel >= 2 {
            list.append(AlertBadge(id: "memp", label: "Mem Pressure Warn", severity: .warning))
        }
        if gpuRecoveryCount > 0 {
            list.append(AlertBadge(id: "rec", label: "GPU Resets: \(gpuRecoveryCount)", severity: .warning))
        }
        return list
    }

    func overallSeverity(for hw: HardwareInfo) -> HealthSeverity {
        let a = alerts(for: hw)
        if a.contains(where: { $0.severity == .critical }) { return .critical }
        if a.contains(where: { $0.severity == .warning }) { return .warning }
        return .nominal
    }
}
