import SwiftUI

// SVG-free ports of the prototype's charts: smooth bezier area chart,
// sparkline, donut, and the diagnostics health ring.

private func smoothPath(values: [Double], in size: CGSize, pad: CGFloat = 6) -> Path {
    var path = Path()
    guard values.count > 1 else { return path }
    let maxV = values.max() ?? 1, minV = values.min() ?? 0
    let span = max(maxV - minV, 0.000001)
    let xs = (0..<values.count).map { pad + CGFloat($0) / CGFloat(values.count - 1) * (size.width - pad * 2) }
    let ys = values.map { size.height - pad - CGFloat(($0 - minV) / span) * (size.height - pad * 2) }
    path.move(to: CGPoint(x: xs[0], y: ys[0]))
    for i in 1..<values.count {
        let cx = (xs[i - 1] + xs[i]) / 2
        path.addCurve(to: CGPoint(x: xs[i], y: ys[i]),
                      control1: CGPoint(x: cx, y: ys[i - 1]),
                      control2: CGPoint(x: cx, y: ys[i]))
    }
    return path
}

struct AreaChart: View {
    var data: [Double]
    var color: Color
    var fill: Bool = true
    var strokeWidth: CGFloat = 2.5
    var showDot: Bool = false

    var body: some View {
        GeometryReader { geo in
            let line = smoothPath(values: data, in: geo.size)
            ZStack {
                if fill {
                    var area = line
                    let _ = area.addLine(to: CGPoint(x: geo.size.width - 6, y: geo.size.height))
                    let _ = area.addLine(to: CGPoint(x: 6, y: geo.size.height))
                    let _ = area.closeSubpath()
                    area.fill(LinearGradient(colors: [color.opacity(0.22), color.opacity(0)],
                                             startPoint: .top, endPoint: .bottom))
                }
                line.stroke(color, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round))
                if showDot, data.count > 1, let last = data.last {
                    let maxV = data.max() ?? 1, minV = data.min() ?? 0
                    let span = max(maxV - minV, 0.000001)
                    let y = geo.size.height - 6 - CGFloat((last - minV) / span) * (geo.size.height - 12)
                    Circle().fill(color)
                        .frame(width: 7, height: 7)
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                        .position(x: geo.size.width - 6, y: y)
                }
            }
        }
    }
}

struct Sparkline: View {
    var data: [Double]
    var color: Color
    var width: CGFloat = 120
    var height: CGFloat = 28

    var body: some View {
        Path { p in
            guard data.count > 1 else { return }
            let maxV = data.max() ?? 1, minV = data.min() ?? 0
            let span = max(maxV - minV, 0.000001)
            for (i, v) in data.enumerated() {
                let x = CGFloat(i) / CGFloat(data.count - 1) * width
                let y = height - 2 - CGFloat((v - minV) / span) * (height - 4)
                if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
            }
        }
        .stroke(color, style: StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round))
        .frame(width: width, height: height)
    }
}

struct DonutSegment: Identifiable {
    var id: String { label }
    var label: String
    var value: Double
    var color: Color
}

struct DonutChart: View {
    var segments: [DonutSegment]
    var size: CGFloat = 120
    var thickness: CGFloat = 16

    var body: some View {
        let total = segments.reduce(0) { $0 + $1.value }
        ZStack {
            ForEach(Array(segments.enumerated()), id: \.element.id) { i, seg in
                let start = segments.prefix(i).reduce(0) { $0 + $1.value } / total
                let end = start + seg.value / total
                Circle()
                    .trim(from: start, to: end)
                    .stroke(seg.color, style: StrokeStyle(lineWidth: thickness))
                    .rotationEffect(.degrees(-90))
            }
        }
        .padding(thickness / 2)
        .frame(width: size, height: size)
    }
}

struct HealthRing: View {
    var score: Int
    @Environment(\.theme) private var th

    var body: some View {
        let color = score >= 80 ? th.success : score >= 60 ? th.warning : th.danger
        ZStack {
            Circle().stroke(th.bg3, lineWidth: 9)
            Circle()
                .trim(from: 0, to: CGFloat(score) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(score)")
                .font(jakarta(22, .extra))
                .foregroundStyle(th.fg1)
        }
        .frame(width: 78, height: 78)
    }
}
