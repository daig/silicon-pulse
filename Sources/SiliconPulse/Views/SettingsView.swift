import SwiftUI

struct SettingsView: View {
    @ObservedObject var collector: MetricsCollector

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Menu Bar & Sampling")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Button("Reset") {
                    collector.resetMenuBarDefaults()
                }
                .buttonStyle(.link)
                .font(.system(size: 11))
            }

            HStack {
                Text("Refresh")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $collector.refreshInterval) {
                    Text("0.5s").tag(0.5)
                    Text("1s").tag(1.0)
                    Text("2s").tag(2.0)
                    Text("5s").tag(5.0)
                }
                .pickerStyle(.segmented)
                .frame(width: 190)
                .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Pin to Menu Bar")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 5) {
                    Toggle("GPU %", isOn: $collector.mbShowGPU)
                    Toggle("GPU Mem", isOn: $collector.mbShowGPUMem)
                    Toggle("DRAM BW", isOn: $collector.mbShowBW)
                    Toggle("Temp", isOn: $collector.mbShowTemp)
                    Toggle("Power W", isOn: $collector.mbShowPower)
                    Toggle("Fan RPM", isOn: $collector.mbShowFan)
                    Toggle("CPU %", isOn: $collector.mbShowCPU)
                }
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
            }

            Divider()

            Toggle(isOn: Binding(
                get: { collector.isLaunchAtLoginEnabled },
                set: { collector.setLaunchAtLogin($0) }
            )) {
                Text("Launch at Login (LaunchAgent)")
                    .font(.system(size: 11))
            }
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(10)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
