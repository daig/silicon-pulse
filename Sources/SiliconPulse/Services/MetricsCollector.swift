import Foundation
import SwiftUI
import CMetrics

@MainActor
final class MetricsCollector: ObservableObject {
    @Published private(set) var hardware: HardwareInfo = .empty
    @Published private(set) var snapshot: MetricsSnapshot = .empty

    // Rolling histories (latest 60 samples)
    @Published private(set) var gpuHistory: [Double] = []
    @Published private(set) var bwHistory: [Double] = []
    @Published private(set) var cpuHistory: [Double] = []
    @Published private(set) var powerHistory: [Double] = []
    @Published private(set) var tempHistory: [Double] = []

    @Published var isPaused: Bool = false

    // User-configurable preferences (persisted)
    @AppStorage("refreshInterval") var refreshInterval: Double = 1.0 {
        didSet { restartTimer() }
    }
    @AppStorage("mbShowGPU") var mbShowGPU: Bool = true
    @AppStorage("mbShowGPUMem") var mbShowGPUMem: Bool = true
    @AppStorage("mbShowBW") var mbShowBW: Bool = true
    @AppStorage("mbShowTemp") var mbShowTemp: Bool = true
    @AppStorage("mbShowPower") var mbShowPower: Bool = false
    @AppStorage("mbShowFan") var mbShowFan: Bool = false
    @AppStorage("mbShowCPU") var mbShowCPU: Bool = false

    private let maxHistory = 60
    private let workQueue = DispatchQueue(label: "com.local.SiliconPulse.collector", qos: .utility)
    private nonisolated(unsafe) var cCollector: OpaquePointer?
    private var timer: Timer?

    init() {
        let ptr = cm_collector_create()
        self.cCollector = ptr
        if let ptr {
            var info = CMStaticInfo()
            cm_collector_get_static_info(ptr, &info)
            self.hardware = HardwareInfo(cInfo: info)

            // Populate initial snapshot synchronously so MenuBarExtra measures the full layout on frame 0.
            var initialRaw = CMSample()
            if cm_collector_sample(ptr, &initialRaw) {
                let initialSnap = MetricsSnapshot(cSample: initialRaw)
                self.snapshot = initialSnap
                self.appendHistory(&self.gpuHistory, initialSnap.gpuDeviceUtilPct)
                self.appendHistory(&self.bwHistory, initialSnap.bwTotalGBs)
                self.appendHistory(&self.cpuHistory, initialSnap.cpuTotalPct)
                self.appendHistory(&self.powerHistory, initialSnap.powerSystemWatts)
                self.appendHistory(&self.tempHistory, initialSnap.tempDiePeakC)
            }
        }
        restartTimer()
    }

    deinit {
        timer?.invalidate()
        if let ptr = cCollector {
            cm_collector_destroy(ptr)
        }
    }

    func togglePause() {
        isPaused.toggle()
    }

    func resetMenuBarDefaults() {
        refreshInterval = 1.0
        mbShowGPU = true
        mbShowGPUMem = true
        mbShowBW = true
        mbShowTemp = true
        mbShowPower = false
        mbShowFan = false
        mbShowCPU = false
    }

    private func restartTimer() {
        timer?.invalidate()
        let interval = max(0.5, min(refreshInterval, 10.0))
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isPaused else { return }
                self.pollOnce()
            }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func pollOnce() {
        guard cCollector != nil else { return }
        workQueue.async { [weak self] in
            guard let ptr = self?.cCollector else { return }
            var raw = CMSample()
            guard cm_collector_sample(ptr, &raw) else { return }
            let snap = MetricsSnapshot(cSample: raw)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.snapshot = snap
                self.appendHistory(&self.gpuHistory, snap.gpuDeviceUtilPct)
                self.appendHistory(&self.bwHistory, snap.bwTotalGBs)
                self.appendHistory(&self.cpuHistory, snap.cpuTotalPct)
                self.appendHistory(&self.powerHistory, snap.powerSystemWatts)
                self.appendHistory(&self.tempHistory, snap.tempDiePeakC)
            }
        }
    }

    private func appendHistory(_ array: inout [Double], _ value: Double) {
        array.append(value)
        if array.count > maxHistory {
            array.removeFirst(array.count - maxHistory)
        }
    }

    // MARK: - LaunchAgent helper (works reliably with ad-hoc signed local .app bundles)

    private var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.local.SiliconPulse.plist")
    }

    var isLaunchAtLoginEnabled: Bool {
        FileManager.default.fileExists(atPath: launchAgentURL.path)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        let fm = FileManager.default
        if enabled {
            let execPath = Bundle.main.executablePath ?? ProcessInfo.processInfo.arguments[0]
            let plist: [String: Any] = [
                "Label": "com.local.SiliconPulse",
                "ProgramArguments": [execPath],
                "RunAtLoad": true,
                "KeepAlive": false
            ]
            do {
                try fm.createDirectory(at: launchAgentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                try data.write(to: launchAgentURL, options: .atomic)
            } catch {
                NSLog("SiliconPulse: failed to write LaunchAgent: %@", error.localizedDescription)
            }
        } else {
            try? fm.removeItem(at: launchAgentURL)
        }
        objectWillChange.send()
    }
}
