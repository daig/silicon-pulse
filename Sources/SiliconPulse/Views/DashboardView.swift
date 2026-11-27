import SwiftUI

struct DashboardView: View {
    @ObservedObject var collector: MetricsCollector
    @State private var showSettings: Bool = false

    var body: some View {
        let s = collector.snapshot
        let hw = collector.hardware
        let alerts = s.alerts(for: hw)

        VStack(alignment: .leading, spacing: 8) {
            headerSection(hw: hw, alerts: alerts)

            if showSettings {
                SettingsView(collector: collector)
            } else {
                // Hero Row: GPU Compute + Memory Bandwidth
                HStack(spacing: 8) {
                    gpuCard(s: s, hw: hw)
                    bandwidthCard(s: s, hw: hw)
                }

                // Unified Memory & LLM Headroom
                memoryCard(s: s, hw: hw)

                // CPU (Super + Performance)
                cpuCard(s: s, hw: hw)

                // Thermals, Power & Fans
                thermalsAndPowerCard(s: s)

                // Top Memory Processes
                if !s.topProcs.isEmpty {
                    processesCard(s: s)
                }
            }
        }
        .padding(12)
        .frame(width: 460)
        .fixedSize(horizontal: true, vertical: true)
    }

    // MARK: - Header

    private func headerSection(hw: HardwareInfo, alerts: [AlertBadge]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(hw.chipName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text("\(hw.totalCPUCores)C CPU (\(hw.perfLevel0Cores) \(hw.perfLevel0Name) + \(hw.perfLevel1Cores) \(hw.perfLevel1Name)) · \(hw.gpuCoreCount)C GPU · \(Int(hw.totalMemoryGB.rounded())) GB")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Button {
                    collector.togglePause()
                } label: {
                    Image(systemName: collector.isPaused ? "play.fill" : "pause.fill")
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.borderless)
                .help(collector.isPaused ? "Resume polling" : "Pause polling")

                Button {
                    showSettings.toggle()
                } label: {
                    Image(systemName: showSettings ? "chart.bar.xaxis" : "gearshape")
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.borderless)
                .help(showSettings ? "Back to dashboard" : "Settings")

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.borderless)
                .help("Quit SiliconPulse")
            }

            if !alerts.isEmpty {
                HStack(spacing: 5) {
                    ForEach(alerts.prefix(4)) { badge in
                        Text(badge.label)
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(badge.severity.color.opacity(0.18))
                            .foregroundStyle(badge.severity.color)
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    // MARK: - GPU Card

    private func gpuCard(s: MetricsSnapshot, hw: HardwareInfo) -> some View {
        cardContainer {
            HStack(alignment: .firstTextBaseline) {
                Label("GPU", systemImage: "square.grid.3x3.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(String(format: "%.0f%%", s.gpuDeviceUtilPct))
                    .font(.system(size: 17, weight: .bold, design: .monospaced))
                    .foregroundStyle(.cyan)
                    .lineLimit(1)
            }

            SparklineView(values: collector.gpuHistory, maxValue: 100, color: .cyan, height: 24)

            HStack(spacing: 6) {
                miniStat("Render", String(format: "%.0f%%", s.gpuRendererUtilPct))
                Spacer(minLength: 2)
                miniStat("Power", String(format: "%.1fW", s.gpuPowerWatts))
                Spacer(minLength: 2)
                let clockStr = s.gpuFreqMHz > 0
                    ? String(format: "%.0fMHz", s.gpuFreqMHz)
                    : (s.gpuDominantPState > 0 ? "P\(s.gpuDominantPState)" : "OFF")
                miniStat("Clock", clockStr)
            }

            HStack {
                Text(s.gpuThermalThrottling ? "CLTM Throttled" : "PPM \(Int(s.gpuPPMTargetPct))%")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(s.gpuThermalThrottling ? .red : .secondary)
                    .lineLimit(1)
                Spacer()
                if s.gpuRecoveryCount > 0 {
                    Text("Resets: \(s.gpuRecoveryCount)")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                } else {
                    Text("Active \(String(format: "%.0f%%", s.gpuActiveResidencyPct))")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: - DRAM Bandwidth Card

    private func bandwidthCard(s: MetricsSnapshot, hw: HardwareInfo) -> some View {
        cardContainer {
            HStack(alignment: .firstTextBaseline) {
                Label("DRAM BW", systemImage: "arrow.left.arrow.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(String(format: "%.0f", s.bwTotalGBs))
                        .font(.system(size: 17, weight: .bold, design: .monospaced))
                        .foregroundStyle(.mint)
                    Text("GB/s")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
            }

            SparklineView(values: collector.bwHistory, maxValue: max(800, collector.bwHistory.max() ?? 800), color: .mint, height: 24)

            VStack(spacing: 3) {
                bwRow(label: "Die 0", rd: s.bwDie0ReadGBs, wr: s.bwDie0WriteGBs)
                if hw.isDualDie || s.bwDie1TotalGBs > 0 || s.bwDie1ReadGBs > 0 {
                    bwRow(label: "Die 1", rd: s.bwDie1ReadGBs, wr: s.bwDie1WriteGBs)
                } else {
                    bwRow(label: "Total", rd: s.bwDie0ReadGBs, wr: s.bwDie0WriteGBs)
                }
            }

            // Bottom spacer line to match GPU card height cleanly
            HStack {
                Text("AMCC Read / Write")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Spacer()
            }
        }
    }

    private func bwRow(label: String, rd: Double, wr: Double) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .leading)
            Text(String(format: "R %.0f", rd))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.mint)
                .lineLimit(1)
            Spacer()
            Text(String(format: "W %.0f GB/s", wr))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    // MARK: - Unified Memory & LLM Headroom Card

    private func memoryCard(s: MetricsSnapshot, hw: HardwareInfo) -> some View {
        let total = max(hw.totalMemoryGB, 1)
        let otherWired = max(0, s.memWiredGB - s.gpuInUseGB)
        let gpuLimit = max(hw.gpuWiredLimitGB, 1)
        let gpuLimitPct = min(s.gpuInUseGB / gpuLimit, 1.0)
        let gpuBarColor: Color = gpuLimitPct >= 0.92 ? .red : (gpuLimitPct >= 0.85 ? .orange : .cyan)

        return cardContainer {
            HStack {
                Label("Unified Memory & LLM Headroom", systemImage: "memorychip")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text("Pressure: \(s.memoryPressureLabel)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(s.memoryPressureLevel > 1 ? .orange : .secondary)
                    .lineLimit(1)
            }

            StackedBarView(
                segments: [
                    SegmentedBarSegment(id: "gpu", label: "GPU", value: s.gpuInUseGB, color: .cyan),
                    SegmentedBarSegment(id: "wired", label: "Wired", value: otherWired, color: .blue),
                    SegmentedBarSegment(id: "active", label: "Active", value: s.memActiveGB, color: .indigo),
                    SegmentedBarSegment(id: "comp", label: "Compressed", value: s.memCompressedGB, color: .purple),
                    SegmentedBarSegment(id: "inact", label: "Inactive", value: s.memInactiveGB, color: .gray.opacity(0.45))
                ],
                total: total,
                height: 9
            )

            HStack(spacing: 0) {
                legendDot(.cyan, String(format: "GPU %.1fG", s.gpuInUseGB))
                Spacer(minLength: 4)
                legendDot(.blue, String(format: "Wired %.1fG", otherWired))
                Spacer(minLength: 4)
                legendDot(.indigo, String(format: "Act %.0fG", s.memActiveGB))
                Spacer(minLength: 4)
                legendDot(.purple, String(format: "Cmp %.1fG", s.memCompressedGB))
                Spacer(minLength: 4)
                legendDot(.gray.opacity(0.6), String(format: "Inact %.0fG", s.memInactiveGB))
            }

            Divider().opacity(0.4)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("GPU Wired Ceiling")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.1f / %.1f GB (%.0f%%)", s.gpuInUseGB, hw.gpuWiredLimitGB, gpuLimitPct * 100))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(gpuBarColor)
                        .lineLimit(1)
                }
                LinearGaugeBar(fraction: gpuLimitPct, color: gpuBarColor, height: 6)
            }

            HStack {
                let swapStr = s.swapUsedGB >= 1.0
                    ? String(format: "%.2f GB", s.swapUsedGB)
                    : String(format: "%.0f MB", s.swapUsedGB * 1024.0)
                Text("Swap: \(swapStr)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(s.swapInsDelta > 0 || s.swapOutsDelta > 0 ? .orange : .secondary)
                    .lineLimit(1)
                if s.swapInsDelta > 0 || s.swapOutsDelta > 0 {
                    Text("(+\(s.swapInsDelta)in / +\(s.swapOutsDelta)out)")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
                Spacer()
                Text(String(format: "Free %.1f GB · Avail %d%%", s.memFreeGB, s.memoryAvailablePct))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - CPU Card

    private func cpuCard(s: MetricsSnapshot, hw: HardwareInfo) -> some View {
        cardContainer {
            HStack(alignment: .firstTextBaseline) {
                Label("CPU", systemImage: "cpu")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if hw.isDualDie {
                    Text(String(format: "D0 %.0f%% · D1 %.0f%%", s.cpuDie0Pct, s.cpuDie1Pct))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(String(format: "%.1f%%", s.cpuTotalPct))
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }

            SparklineView(values: collector.cpuHistory, maxValue: 100, color: .orange, height: 20)

            if !s.superCoreUtil.isEmpty {
                CoreHeatmapRow(
                    title: "\(s.superCoreUtil.count) \(hw.perfLevel0Name) Cores",
                    utils: s.superCoreUtil,
                    tint: .orange
                )
            }
            if !s.perfCoreUtil.isEmpty {
                CoreHeatmapRow(
                    title: "\(s.perfCoreUtil.count) \(hw.perfLevel1Name) Cores",
                    utils: s.perfCoreUtil,
                    tint: .yellow
                )
            }
        }
    }

    // MARK: - Thermals, Power & Cooling Card

    private func thermalsAndPowerCard(s: MetricsSnapshot) -> some View {
        cardContainer {
            HStack {
                Label("Thermals, Power & Fans", systemImage: "thermometer.medium")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(s.thermalStateLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(s.thermalState == 0 ? .green : (s.thermalState == 1 ? .orange : .red))
            }

            HStack(spacing: 0) {
                miniStat("Die Peak", String(format: "%.1f°C", s.tempDiePeakC), highlight: s.tempDiePeakC >= 90 ? .red : (s.tempDiePeakC >= 80 ? .orange : .primary))
                Spacer(minLength: 4)
                miniStat("Die Avg", String(format: "%.1f°C", s.tempDieAvgC))
                Spacer(minLength: 4)
                miniStat("Hotspot", String(format: "%.1f°C", s.tempHotspotC))
                Spacer(minLength: 4)
                miniStat("VRM/Mem", String(format: "%.1f°C", s.tempVRMOrMemC))
                Spacer(minLength: 4)
                miniStat("NAND", String(format: "%.1f°C", s.tempNandC))
            }

            Divider().opacity(0.4)

            HStack(spacing: 0) {
                miniStat("System", String(format: "%.1fW", s.powerSystemWatts), highlight: .yellow)
                Spacer(minLength: 4)
                miniStat("GPU", String(format: "%.1fW", s.gpuPowerWatts), highlight: .cyan)
                Spacer(minLength: 4)
                miniStat("SoC", String(format: "%.1fW", s.powerSoCWatts))
                Spacer(minLength: 4)
                miniStat("Mem", String(format: "%.1fW", s.powerMemWatts))
                if s.powerDie0Watts > 0 || s.powerDie1Watts > 0 {
                    Spacer(minLength: 4)
                    miniStat("D0 / D1", String(format: "%.0f/%.0fW", s.powerDie0Watts, s.powerDie1Watts))
                }
            }

            if !s.fans.isEmpty {
                Divider().opacity(0.4)
                VStack(spacing: 4) {
                    ForEach(s.fans) { fan in
                        HStack(spacing: 8) {
                            Text("Fan \(fan.index)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 34, alignment: .leading)
                            LinearGaugeBar(
                                fraction: fan.fractionOfMax,
                                color: fan.fractionOfMax > 0.75 ? .orange : .blue,
                                height: 6
                            )
                            Text(String(format: "%.0f / %.0f RPM", fan.actualRPM, fan.maxRPM))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .frame(width: 104, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Top Memory Processes

    private func processesCard(s: MetricsSnapshot) -> some View {
        cardContainer {
            HStack {
                Label("Top Memory Processes", systemImage: "list.bullet.rectangle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            VStack(spacing: 3) {
                ForEach(s.topProcs.prefix(5)) { proc in
                    HStack(spacing: 4) {
                        Text(proc.name)
                            .font(.system(size: 10.5))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("(\(proc.pid))")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        let memStr = proc.memoryGB >= 1.0
                            ? String(format: "%.2f GB", proc.memoryGB)
                            : String(format: "%.0f MB", proc.memoryGB * 1024.0)
                        Text(memStr)
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(proc.memoryGB >= 10.0 ? .cyan : .primary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func cardContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            content()
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.045))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func miniStat(_ title: String, _ value: String, highlight: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(highlight)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}
