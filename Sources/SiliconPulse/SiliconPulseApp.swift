import SwiftUI
import AppKit
import CMetrics

@main
struct SiliconPulseApp: App {
    @StateObject private var collector = MetricsCollector()

    init() {
        // Optional CLI diagnostic mode: `SiliconPulse --dump` prints one live sample and exits.
        if CommandLine.arguments.contains("--dump") {
            Self.runDumpAndExit()
        }
        // Keep purely in the menu bar (no Dock icon), even when launched directly via `swift run`.
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            DashboardView(collector: collector)
        } label: {
            MenuBarLabelView(collector: collector)
        }
        .menuBarExtraStyle(.window)
    }

    private static func runDumpAndExit() -> Never {
        guard let c = cm_collector_create() else {
            fputs("Failed to initialize CMCollector\n", stderr)
            exit(1)
        }
        var info = CMStaticInfo()
        cm_collector_get_static_info(c, &info)
        let hw = HardwareInfo(cInfo: info)

        // Wait 300ms so IOReport delta channels populate
        usleep(300_000)
        var raw = CMSample()
        cm_collector_sample(c, &raw)
        let s = MetricsSnapshot(cSample: raw)
        cm_collector_destroy(c)

        print("Chip: \(hw.chipName) (\(hw.totalCPUCores)C: \(hw.perfLevel0Cores) \(hw.perfLevel0Name) + \(hw.perfLevel1Cores) \(hw.perfLevel1Name), \(hw.gpuCoreCount)C GPU, \(String(format: "%.0f", hw.totalMemoryGB)) GB)")
        print("APIs: SMC=\(s.smcAvailable) IOReport=\(s.ioReportAvailable) IOAccelerator=\(s.ioAcceleratorAvailable)")
        print(String(format: "GPU:  util=%.0f%% (render=%.0f%%, active=%.1f%%) clock=%.0fMHz (P%d) power=%.1fW mem=%.2f/%.1f GB cltm=%@ ppm=%.0f%% resets=%llu",
                     s.gpuDeviceUtilPct, s.gpuRendererUtilPct, s.gpuActiveResidencyPct,
                     s.gpuFreqMHz, s.gpuDominantPState, s.gpuPowerWatts,
                     s.gpuInUseGB, hw.gpuWiredLimitGB,
                     s.gpuThermalThrottling ? "YES" : "NO", s.gpuPPMTargetPct, s.gpuRecoveryCount))
        print(String(format: "BW:   total=%.1f GB/s (Die0 R=%.1f W=%.1f | Die1 R=%.1f W=%.1f)",
                     s.bwTotalGBs, s.bwDie0ReadGBs, s.bwDie0WriteGBs, s.bwDie1ReadGBs, s.bwDie1WriteGBs))
        print(String(format: "CPU:  total=%.1f%% (%@=%.1f%% [%d], %@=%.1f%% [%d], Die0=%.1f%%, Die1=%.1f%%)",
                     s.cpuTotalPct, hw.perfLevel0Name, s.cpuSuperPct, s.superCoreUtil.count,
                     hw.perfLevel1Name, s.cpuPerfPct, s.perfCoreUtil.count, s.cpuDie0Pct, s.cpuDie1Pct))
        print(String(format: "MEM:  wired=%.1fG active=%.1fG comp=%.1fG free=%.1fG swap=%.0fMB pressure=%@ avail=%d%%",
                     s.memWiredGB, s.memActiveGB, s.memCompressedGB, s.memFreeGB,
                     s.swapUsedGB * 1024.0, s.memoryPressureLabel, s.memoryAvailablePct))
        print(String(format: "TEMP: diePeak=%.1fC dieAvg=%.1fC hotspot=%.1fC vrm=%.1fC nand=%.1fC state=%@",
                     s.tempDiePeakC, s.tempDieAvgC, s.tempHotspotC, s.tempVRMOrMemC, s.tempNandC, s.thermalStateLabel))
        print(String(format: "PWR:  sys=%.1fW gpu=%.1fW soc=%.1fW mem=%.1fW die0=%.1fW die1=%.1fW",
                     s.powerSystemWatts, s.gpuPowerWatts, s.powerSoCWatts, s.powerMemWatts, s.powerDie0Watts, s.powerDie1Watts))
        let fanStr = s.fans.map { String(format: "F%d=%.0f/%.0fRPM(tgt %.0f)", $0.index, $0.actualRPM, $0.maxRPM, $0.targetRPM) }.joined(separator: ", ")
        print("FANS: \(fanStr)")
        if !s.topProcs.isEmpty {
            let pStr = s.topProcs.prefix(5).map { String(format: "%@(%d): %.2fG", $0.name, $0.pid, $0.memoryGB) }.joined(separator: " | ")
            print("TOP:  \(pStr)")
        }
        exit(0)
    }
}
