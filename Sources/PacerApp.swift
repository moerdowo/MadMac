import SwiftUI

final class Prefs: ObservableObject {
    @AppStorage("appearance") var appearance: AppearanceChoice = .system
    @AppStorage("accent") var accent: AccentChoice = .blue
    @AppStorage("dashLayout") var dashLayout: DashLayout = .overview
    @AppStorage("density") var density: Density = .regular
}

@main
struct PacerApp: App {
    @StateObject private var state = AppState()
    @StateObject private var prefs = Prefs()

    init() {
        SnapshotRunner.runIfRequested()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .environmentObject(prefs)
                .preferredColorScheme(prefs.appearance.colorScheme)
                .frame(minWidth: 1080, minHeight: 660)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1320, height: 840)
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Campaign…") { state.createOpen = true }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("Review Launch Plan…") { if state.pendingCount > 0 { state.reviewOpen = true } }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(state)
                .environmentObject(prefs)
                .preferredColorScheme(prefs.appearance.colorScheme)
        }

        // Today's pacing at a glance, always in the menu bar.
        MenuBarExtra {
            MenuBarPacing()
                .environmentObject(state)
                .environmentObject(prefs)
        } label: {
            Image(systemName: "bolt.fill")
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarPacing: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var prefs: Prefs
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let th = Theme(dark: scheme == .dark, accent: prefs.accent.color)
        let account = state.snapshot.account
        let pct = account.budget > 0 ? min(account.daySpend / account.budget, 1) : 0
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(account.name).font(jakarta(13, .bold)).foregroundStyle(th.fg1)
                Spacer()
                Text(state.mode == .live ? "Live" : state.mode == .sample ? "Sample" : "Not connected")
                    .font(jakarta(10.5, .semibold))
                    .foregroundStyle(state.mode == .live ? th.success : th.fg3)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Today").font(jakarta(11.5)).foregroundStyle(th.fg3)
                    Spacer()
                    (Text(Fmt.money(account.daySpend, compact: true)).bold()
                     + Text(" / \(Fmt.money(account.budget, compact: true))"))
                        .font(jakarta(11.5))
                        .foregroundStyle(th.fg2)
                }
                Capsule().fill(th.bg3)
                    .frame(height: 6)
                    .overlay(alignment: .leading) {
                        GeometryReader { geo in
                            Capsule().fill(pct > 0.9 ? th.warning : th.accent)
                                .frame(width: geo.size.width * pct)
                        }
                    }
            }
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("ROAS · 7d").font(jakarta(10)).foregroundStyle(th.fg4)
                    Text(Fmt.roas(state.snapshot.kpis.roas.value))
                        .font(jakarta(15, .extra)).foregroundStyle(th.fg1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("Staged").font(jakarta(10)).foregroundStyle(th.fg4)
                    Text("\(state.pendingCount)")
                        .font(jakarta(15, .extra))
                        .foregroundStyle(state.pendingCount > 0 ? th.accent : th.fg1)
                }
            }
            Divider()
            HStack {
                Button("Refresh") { Task { await state.reload() } }
                    .disabled(state.mode != .live)
                Spacer()
                Button("Open MadMac") {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
                }
            }
            .font(jakarta(12))
        }
        .padding(14)
        .frame(width: 240)
    }
}

struct RootView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var prefs: Prefs
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = Theme(dark: scheme == .dark, accent: prefs.accent.color)
        ZStack {
            theme.bg2.ignoresSafeArea()
            HStack(spacing: 0) {
                SidebarView()
                Rectangle().fill(theme.border).frame(width: 1)
                VStack(spacing: 0) {
                    ToolbarView()
                    Rectangle().fill(theme.border).frame(height: 1)
                    sectionView
                }
                .background(theme.bg2)
            }

            // overlays
            if let id = state.drawerCampaignID,
               let campaign = state.campaigns.first(where: { $0.id == id }) {
                CampaignDrawer(campaign: campaign)
            }
            if state.createOpen { CreateWizard() }
            if state.reviewOpen { ReviewSheet() }
            if state.connectOpen { ConnectSheet() }

            VStack {
                if let banner = state.banner { BannerView(banner: banner) }
                Spacer()
                if state.pendingCount > 0 && !state.reviewOpen { ReviewBar() }
            }
            .padding(.bottom, 22)
            .padding(.top, 12)
        }
        .environment(\.theme, theme)
        .focusEffectDisabled()   // no focus rings anywhere in the window
        .animation(.easeOut(duration: 0.18), value: state.pendingCount > 0)
        .animation(.easeOut(duration: 0.18), value: state.banner?.id)
    }

    @ViewBuilder private var sectionView: some View {
        if state.mode == .disconnected {
            OnboardingView()
        } else {
            sectionContent
        }
    }

    @ViewBuilder private var sectionContent: some View {
        let content = Group {
            switch state.section {
            case .performance: PerformanceView()
            case .campaigns: CampaignsListView()
            case .catalog: CatalogView()
            case .diagnostics: DiagnosticsView()
            case .datasets: DatasetsView()
            }
        }
        .padding(.vertical, prefs.density.padV)
        .padding(.horizontal, prefs.density.padH)

        // ImageRenderer (snapshot mode) can't rasterize ScrollView content.
        if SnapshotRunner.isActive {
            VStack { content; Spacer(minLength: 0) }
        } else {
            ScrollView { content }.id(state.section)
        }
    }
}

struct BannerView: View {
    var banner: AppState.Banner
    @EnvironmentObject private var state: AppState
    @Environment(\.theme) private var th

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: banner.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(banner.isError ? th.danger : th.success)
            Text(banner.text).font(jakarta(13, .semibold)).foregroundStyle(th.fg1)
            Button { state.banner = nil } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(th.fg3)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Capsule().fill(th.bg1).shadow(color: .black.opacity(0.18), radius: 12, y: 4))
        .overlay(Capsule().stroke(th.border, lineWidth: 1))
        .task(id: banner.id) {
            try? await Task.sleep(for: .seconds(5))
            if state.banner?.id == banner.id { state.banner = nil }
        }
    }
}
