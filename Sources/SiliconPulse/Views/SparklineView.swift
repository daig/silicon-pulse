import SwiftUI

struct SparklineView: View {
    let values: [Double]
    let maxValue: Double?
    let color: Color
    var height: CGFloat = 26

    var body: some View {
        Canvas { context, size in
            guard values.count >= 2, size.width > 1, size.height > 1 else { return }
            let upper = max(maxValue ?? (values.max() ?? 1.0), 1.0)
            let stepX = size.width / CGFloat(max(values.count - 1, 1))

            var linePath = Path()
            var fillPath = Path()

            for (idx, val) in values.enumerated() {
                let x = CGFloat(idx) * stepX
                let clamped = min(max(val / upper, 0), 1)
                let y = size.height - CGFloat(clamped) * (size.height - 2) - 1
                let pt = CGPoint(x: x, y: y)
                if idx == 0 {
                    linePath.move(to: pt)
                    fillPath.move(to: CGPoint(x: x, y: size.height))
                    fillPath.addLine(to: pt)
                } else {
                    linePath.addLine(to: pt)
                    fillPath.addLine(to: pt)
                }
            }

            fillPath.addLine(to: CGPoint(x: CGFloat(values.count - 1) * stepX, y: size.height))
            fillPath.closeSubpath()

            context.fill(
                fillPath,
                with: .linearGradient(
                    Gradient(colors: [color.opacity(0.28), color.opacity(0.02)]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: 0, y: size.height)
                )
            )
            context.stroke(linePath, with: .color(color), lineWidth: 1.5)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }
}

struct SegmentedBarSegment: Identifiable {
    let id: String
    let label: String
    let value: Double
    let color: Color
}

struct StackedBarView: View {
    let segments: [SegmentedBarSegment]
    let total: Double
    var height: CGFloat = 9

    var body: some View {
        Canvas { context, size in
            guard size.width > 1, size.height > 1 else { return }
            let bgRect = CGRect(origin: .zero, size: size)
            let radius = size.height / 2
            context.fill(Path(roundedRect: bgRect, cornerRadius: radius), with: .color(Color.primary.opacity(0.08)))

            let safeTotal = max(total, 0.001)
            var x: CGFloat = 0
            context.clip(to: Path(roundedRect: bgRect, cornerRadius: radius))
            for seg in segments {
                let frac = min(max(seg.value / safeTotal, 0), 1)
                let w = size.width * CGFloat(frac)
                if w >= 1.5 {
                    let rect = CGRect(x: x, y: 0, width: max(0, w - 1), height: size.height)
                    context.fill(Path(rect), with: .color(seg.color))
                    x += w
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }
}

struct LinearGaugeBar: View {
    let fraction: Double
    let color: Color
    var height: CGFloat = 6

    var body: some View {
        Canvas { context, size in
            guard size.width > 1, size.height > 1 else { return }
            let r = size.height / 2
            let bg = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: r)
            context.fill(bg, with: .color(Color.primary.opacity(0.08)))

            let clamped = min(max(fraction, 0), 1)
            let fillW = max(clamped > 0 ? 3 : 0, size.width * CGFloat(clamped))
            if fillW > 0 {
                let fg = Path(roundedRect: CGRect(x: 0, y: 0, width: fillW, height: size.height), cornerRadius: r)
                context.fill(fg, with: .color(color))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }
}

struct CoreHeatmapRow: View {
    let title: String
    let utils: [Double]
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                let avg = utils.isEmpty ? 0 : utils.reduce(0, +) / Double(utils.count)
                Text(String(format: "%.0f%%", avg))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
            }
            Canvas { context, size in
                guard !utils.isEmpty, size.width > 1, size.height > 1 else { return }
                let gap: CGFloat = 2
                let count = CGFloat(utils.count)
                let barW = max(2, (size.width - gap * (count - 1)) / count)
                for (i, val) in utils.enumerated() {
                    let x = CGFloat(i) * (barW + gap)
                    let bgRect = CGRect(x: x, y: 0, width: barW, height: size.height)
                    context.fill(Path(roundedRect: bgRect, cornerRadius: 2), with: .color(Color.primary.opacity(0.08)))

                    let frac = min(max(val / 100.0, 0), 1)
                    let h = max(2, size.height * CGFloat(frac))
                    let fgRect = CGRect(x: x, y: size.height - h, width: barW, height: h)
                    context.fill(Path(roundedRect: fgRect, cornerRadius: 2), with: .color(tint.opacity(0.28 + 0.72 * frac)))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 14)
        }
    }
}
