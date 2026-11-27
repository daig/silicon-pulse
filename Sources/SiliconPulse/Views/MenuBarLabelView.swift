import SwiftUI

struct MenuBarLabelView: View {
    @ObservedObject var collector: MetricsCollector

    var body: some View {
        let s = collector.snapshot
        let hw = collector.hardware
        let severity = s.overallSeverity(for: hw)

        HStack(spacing: 5) {
            Image(systemName: severity == .nominal ? "cpu" : "exclamationmark.triangle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(severity == .nominal ? Color.primary : severity.color)

            Text(formattedParts(s: s, hw: hw))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .monospacedDigit()
        }
    }

    private func formattedParts(s: MetricsSnapshot, hw: HardwareInfo) -> String {
        var parts: [String] = []
        if collector.mbShowGPU {
            parts.append(String(format: "GPU %2.0f%%", s.gpuDeviceUtilPct))
        }
        if collector.mbShowGPUMem && hw.gpuWiredLimitGB > 0 {
            parts.append(String(format: "%.0f/%.0fG", s.gpuInUseGB, hw.gpuWiredLimitGB))
        }
        if collector.mbShowBW {
            if s.bwTotalGBs >= 1.0 {
                parts.append(String(format: "%.0fGB/s", s.bwTotalGBs))
            } else {
                parts.append("0GB/s")
            }
        }
        if collector.mbShowCPU {
            parts.append(String(format: "CPU %2.0f%%", s.cpuTotalPct))
        }
        if collector.mbShowTemp && s.tempDiePeakC > 0 {
            parts.append(String(format: "%.0f°C", s.tempDiePeakC))
        }
        if collector.mbShowPower && s.powerSystemWatts > 0 {
            parts.append(String(format: "%.0fW", s.powerSystemWatts))
        }
        if collector.mbShowFan && !s.fans.isEmpty {
            parts.append(String(format: "%.1fk", s.averageFanRPM / 1000.0))
        }
        return parts.isEmpty ? "Pulse" : parts.joined(separator: " · ")
    }
}
