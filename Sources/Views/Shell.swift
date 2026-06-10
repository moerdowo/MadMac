import SwiftUI

// Sidebar, toolbar, review bar — the macOS window chrome from shell.jsx.

struct SidebarView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.theme) private var th

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // room for the traffic lights (hidden title bar)
            Color.clear.frame(height: 52)

            HStack(spacing: 9) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(th.accent)
                        .frame(width: 26, height: 26)
                        .overlay(Image(systemName: "bolt.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white))
                        .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                    Circle()
                        .fill(th.brandMagenta)
                        .frame(width: 9, height: 9)
                        .overlay(Circle().stroke(th.sidebar, lineWidth: 1.5))
                        .offset(x: 3, y: -3)
                }
                Text("Pacer")
                    .font(jakarta(16, .extra))
                    .kerning(-0.3)
                    .foregroundStyle(th.fg1)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)

            VStack(spacing: 2) {
                ForEach(AppSection.allCases) { section in
                    NavItem(section: section)
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            Rectangle().fill(th.border).frame(height: 1)
            AccountCard()
                .padding(10)
        }
        .frame(width: 228)
        .background(th.sidebar)
    }
}

private struct NavItem: View {
    var section: AppSection
    @EnvironmentObject private var state: AppState
    @Environment(\.theme) private var th
    @State private var hover = false

    var body: some View {
        let on = state.section == section
        Button {
            state.section = section
        } label: {
            HStack(spacing: 11) {
                Image(systemName: section.icon)
                    .font(.system(size: 15, weight: on ? .semibold : .regular))
                    .frame(width: 18)
                Text(section.rawValue)
                    .font(jakarta(13.5, on ? .bold : .medium))
                Spacer()
                if section == .diagnostics && state.snapshot.diagnostics.contains(where: { $0.level == .danger }) {
                    Circle().fill(th.danger).frame(width: 7, height: 7)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(on ? th.accentSoft : hover ? th.bg3.opacity(0.6) : .clear)
            .foregroundStyle(on ? th.accent : th.fg2)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

private struct AccountCard: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.theme) private var th

    var body: some View {
        if SnapshotRunner.isActive {
            cardLabel
        } else {
            menuBody
        }
    }

    private var menuBody: some View {
        Menu {
            if state.mode == .live {
                Button("Refresh account") { Task { await state.reload() } }
                Button("Switch to sample data") { state.switchToSample() }
            } else {
                Button("Connect Meta account…") { state.connectOpen = true }
                if Credentials.load() != nil {
                    Button("Use connected account") { state.switchToLive() }
                }
            }
            Divider()
            Button("Disconnect account", role: .destructive) {
                Credentials.clear()
                state.switchToSample()
            }
        } label: {
            cardLabel
        }
        .buttonStyle(.plain)
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }

    private var cardLabel: some View {
        HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(colors: [th.brandMagenta, th.brandBlue],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 28, height: 28)
                    .overlay(Text(String(state.snapshot.account.brand.prefix(1)))
                        .font(jakarta(13, .extra)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 1) {
                    Text(state.snapshot.account.name)
                        .font(jakarta(12.5, .bold))
                        .foregroundStyle(th.fg1)
                        .lineLimit(1)
                    Text(state.mode == .sample ? "Sample data" : state.snapshot.account.accountId)
                        .font(jakarta(10.5))
                        .foregroundStyle(th.fg4)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11))
                    .foregroundStyle(th.fg4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(th.bg1)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(th.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// ── Toolbar ────────────────────────────────────────────────────────────────

struct ToolbarView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.theme) private var th

    var body: some View {
        let account = state.snapshot.account
        let pct = account.budget > 0 ? min(account.daySpend / account.budget, 1) : 0
        HStack(spacing: 14) {
            Text(state.section.rawValue)
                .font(jakarta(14.5, .bold))
                .foregroundStyle(th.fg1)
            if state.isLoading {
                ProgressView().controlSize(.small)
            }
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "wallet.pass")
                    .font(.system(size: 13))
                Text("Today ")
                + Text(Fmt.money(account.daySpend, compact: true)).bold().foregroundStyle(th.fg1)
                + Text(" / \(Fmt.money(account.budget, compact: true))")
                Capsule().fill(th.bg3)
                    .frame(width: 54, height: 6)
                    .overlay(alignment: .leading) {
                        Capsule().fill(th.accent).frame(width: 54 * pct)
                    }
            }
            .font(jakarta(12.5))
            .foregroundStyle(th.fg3)
            .lineLimit(1)

            Rectangle().fill(th.border).frame(width: 1, height: 22)
            IconButton(icon: "bell") {}
        }
        .padding(.horizontal, 24)
        .frame(height: 52)
        .background(th.bg1)
    }
}

// ── Floating staged-changes bar ────────────────────────────────────────────

struct ReviewBar: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.theme) private var th

    var body: some View {
        let count = state.pendingCount
        HStack(spacing: 14) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
            Text("\(count) change\(count == 1 ? "" : "s") staged")
                .font(jakarta(13.5, .semibold))
                .foregroundStyle(th.bg1)
            Button { state.discard() } label: {
                Text("Discard")
                    .font(jakarta(13, .semibold))
                    .foregroundStyle(th.bg4)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            Button { state.reviewOpen = true } label: {
                HStack(spacing: 6) {
                    Text("Review & launch").font(jakarta(13.5, .bold))
                    Image(systemName: "arrow.right").font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Capsule().fill(th.accent))
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 18)
        .padding(.trailing, 12)
        .padding(.vertical, 10)
        .background(Capsule().fill(th.fg1).shadow(color: .black.opacity(0.25), radius: 16, y: 6))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
