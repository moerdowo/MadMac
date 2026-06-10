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
        .animation(.easeOut(duration: 0.18), value: state.pendingCount > 0)
        .animation(.easeOut(duration: 0.18), value: state.banner?.id)
    }

    @ViewBuilder private var sectionView: some View {
        if state.mode == .disconnected {
            DisconnectedView()
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

// Blank-slate prompt shown until an account is connected.
struct DisconnectedView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.theme) private var th

    var body: some View {
        VStack(spacing: 18) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(th.accent)
                    .frame(width: 56, height: 56)
                    .overlay(Image(systemName: "bolt.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white))
                Circle()
                    .fill(th.brandMagenta)
                    .frame(width: 16, height: 16)
                    .overlay(Circle().stroke(th.bg2, lineWidth: 2.5))
                    .offset(x: 5, y: -5)
            }
            VStack(spacing: 6) {
                Text("Connect your Meta account")
                    .font(jakarta(20, .extra)).kerning(-0.2)
                    .foregroundStyle(th.fg1)
                Text("MadMac manages campaigns through Meta's ads-cli.\nNothing goes live without your approval.")
                    .font(jakarta(13))
                    .foregroundStyle(th.fg3)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            HStack(spacing: 10) {
                Btn(variant: .primary, icon: "link", label: "Connect Meta account…") {
                    state.connectOpen = true
                }
                Btn(variant: .secondary, label: "Explore sample data") {
                    state.switchToSample()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
