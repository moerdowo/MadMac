import SwiftUI

// Shared primitives ported from components.jsx: status pill, delta badge,
// switch, buttons, card, segmented control.

// ── Status pill ────────────────────────────────────────────────────────────

enum PillStatus {
    case active, paused, archived, learning, draft, error

    func label(_: Theme) -> String {
        switch self {
        case .active: return "Active"
        case .paused: return "Paused"
        case .archived: return "Archived"
        case .learning: return "Learning"
        case .draft: return "Draft"
        case .error: return "Error"
        }
    }
    func fg(_ th: Theme) -> Color {
        switch self {
        case .active: return th.success
        case .paused, .draft, .archived: return th.fg3
        case .learning: return th.warning
        case .error: return th.danger
        }
    }
    func bg(_ th: Theme) -> Color {
        switch self {
        case .active: return th.success100
        case .paused, .draft, .archived: return th.bg3
        case .learning: return th.warning100
        case .error: return th.danger100
        }
    }

    init(_ s: EntityStatus) {
        switch s {
        case .active: self = .active
        case .paused: self = .paused
        case .archived: self = .archived
        }
    }
}

struct Pill: View {
    var status: PillStatus
    var dot: Bool = true
    var text: String?
    @Environment(\.theme) private var th

    var body: some View {
        HStack(spacing: 6) {
            if dot { Circle().fill(status.fg(th)).frame(width: 6, height: 6) }
            Text(text ?? status.label(th))
                .font(jakarta(12, .semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(Capsule().fill(status.bg(th)))
        .foregroundStyle(status.fg(th))
        .lineLimit(1)
        .fixedSize()
    }
}

// ── Delta badge ────────────────────────────────────────────────────────────

struct DeltaBadge: View {
    var value: Double
    var invert: Bool = false
    var size: CGFloat = 12
    @Environment(\.theme) private var th

    var body: some View {
        if value == 0 {
            Text("—").font(jakarta(size)).foregroundStyle(th.fg3)
        } else {
            let up = value > 0
            let good = invert ? !up : up
            HStack(spacing: 2) {
                Text(up ? "▲" : "▼").font(.system(size: size - 2))
                Text(String(format: "%.1f%%", abs(value))).font(jakarta(size, .bold))
            }
            .foregroundStyle(good ? th.success : th.danger)
        }
    }
}

// ── Switch (mac-style, accent-tinted) ──────────────────────────────────────

struct PacerSwitch: View {
    var on: Bool
    var action: (Bool) -> Void
    @Environment(\.theme) private var th

    var body: some View {
        Button { action(!on) } label: {
            ZStack(alignment: on ? .trailing : .leading) {
                Capsule().fill(on ? th.accent : th.bg4)
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                    .frame(width: 18, height: 18)
                    .padding(2)
            }
            .frame(width: 38, height: 22)
            .animation(.easeOut(duration: 0.15), value: on)
        }
        .buttonStyle(.plain)
    }
}

// ── Buttons ────────────────────────────────────────────────────────────────

enum BtnVariant { case primary, secondary, ghost, soft, danger }
enum BtnSize { case sm, md, lg }

struct Btn: View {
    var variant: BtnVariant = .secondary
    var size: BtnSize = .md
    var icon: String?
    var label: String
    var disabled: Bool = false
    var action: () -> Void = {}
    @Environment(\.theme) private var th
    @State private var hover = false

    var body: some View {
        let fs: CGFloat = size == .sm ? 13 : size == .lg ? 15 : 14
        let padH: CGFloat = size == .sm ? 12 : size == .lg ? 22 : 16
        let padV: CGFloat = size == .sm ? 6 : size == .lg ? 12 : 9
        Button(action: action) {
            HStack(spacing: 7) {
                if let icon { Image(systemName: icon).font(.system(size: fs - 1, weight: .semibold)) }
                Text(label).font(jakarta(fs, .semibold))
            }
            .padding(.horizontal, padH)
            .padding(.vertical, padV)
            .background(bg)
            .foregroundStyle(fg)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(borderColor, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .brightness(hover && !disabled ? -0.03 : 0)
            .opacity(disabled ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hover = $0 }
        .lineLimit(1)
        .fixedSize()
    }

    private var bg: Color {
        switch variant {
        case .primary: return th.accent
        case .secondary: return th.bg1
        case .ghost: return .clear
        case .soft: return th.accentSoft
        case .danger: return th.danger100
        }
    }
    private var fg: Color {
        switch variant {
        case .primary: return .white
        case .secondary: return th.fg1
        case .ghost: return th.fg2
        case .soft: return th.accent
        case .danger: return th.danger
        }
    }
    private var borderColor: Color {
        variant == .secondary ? th.borderStrong : .clear
    }
}

struct IconButton: View {
    var icon: String
    var size: CGFloat = 32
    var bordered: Bool = true
    var action: () -> Void = {}
    @Environment(\.theme) private var th

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size / 2 - 1, weight: .medium))
                .frame(width: size, height: size)
                .background(bordered ? th.bg1 : th.bg3)
                .foregroundStyle(th.fg2)
                .overlay(RoundedRectangle(cornerRadius: 9)
                    .stroke(bordered ? th.borderStrong : .clear, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }
}

// ── Card ───────────────────────────────────────────────────────────────────

struct Card<Content: View>: View {
    var pad: CGFloat = 20
    @ViewBuilder var content: Content
    @Environment(\.theme) private var th

    var body: some View {
        content
            .padding(pad)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(th.bg1)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(th.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: th.shadowColor, radius: 2, y: 1)
    }
}

// ── Segmented control ──────────────────────────────────────────────────────

struct Segmented<T: Hashable>: View {
    var options: [(T, String)]
    @Binding var value: T
    @Environment(\.theme) private var th

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { opt, label in
                let on = opt == value
                Button { value = opt } label: {
                    Text(label)
                        .font(jakarta(13, on ? .semibold : .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(on ? th.bg1 : .clear)
                        .foregroundStyle(on ? th.fg1 : th.fg3)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .shadow(color: on ? th.shadowColor : .clear, radius: 1, y: 1)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(th.bg3)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// ── Small metric column (campaign rows) ────────────────────────────────────

struct MetricCol: View {
    var label: String
    var value: String
    var width: CGFloat = 90
    var accent: Color?
    @Environment(\.theme) private var th

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(label.uppercased())
                .font(jakarta(9.5, .medium))
                .kerning(0.4)
                .foregroundStyle(th.fg4)
            Text(value)
                .font(jakarta(13, .semibold))
                .monospacedDigit()
                .foregroundStyle(accent ?? th.fg1)
        }
        .frame(width: width, alignment: .trailing)
        .lineLimit(1)
    }
}

// ── ConditionalScroll: plain stack in snapshot mode (ImageRenderer can't
//    rasterize ScrollView content), real ScrollView otherwise ───────────────

struct ConditionalScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        if SnapshotRunner.isActive {
            VStack { content; Spacer(minLength: 0) }
        } else {
            ScrollView { content }
        }
    }
}

// ── Hover row helper ───────────────────────────────────────────────────────

struct HoverRow: ViewModifier {
    @Environment(\.theme) private var th
    @State private var hover = false
    func body(content: Content) -> some View {
        content
            .background(hover ? th.bg3 : .clear)
            .onHover { hover = $0 }
    }
}

extension View {
    func hoverRow() -> some View { modifier(HoverRow()) }
}
