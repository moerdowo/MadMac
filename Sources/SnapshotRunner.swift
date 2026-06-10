import SwiftUI

// Debug helper: `Pacer.app/Contents/MacOS/Pacer --snapshot /tmp/dir` renders
// the key screens to PNG and exits. Used to verify the UI against the design
// without a live window capture.

@MainActor
enum SnapshotRunner {
    static private(set) var isActive = false

    static func runIfRequested() {
        connectIfRequested()
        liveCheckIfRequested()
        guard let idx = CommandLine.arguments.firstIndex(of: "--snapshot") else { return }
        isActive = true
        let dir = CommandLine.arguments.count > idx + 1 ? CommandLine.arguments[idx + 1] : "/tmp/pacer_shots"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let prefs = Prefs()

        func shot(_ name: String, dark: Bool = false, configure: (AppState) -> Void) {
            let state = AppState()
            state.switchToSample()
            state.connectOpen = false
            configure(state)
            let view = RootView()
                .environmentObject(state)
                .environmentObject(prefs)
                .environment(\.colorScheme, dark ? .dark : .light)
                .frame(width: 1320, height: 840)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            if let img = renderer.nsImage, let tiff = img.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
            }
        }

        shot("00-onboarding") { state in
            state.snapshot = EmptyData.snapshot
            state.campaigns = []
            state.mode = .disconnected
        }
        prefs.dashLayout = .overview
        shot("01-performance-overview") { $0.section = .performance }
        prefs.dashLayout = .spotlight
        shot("02-performance-spotlight") { $0.section = .performance }
        prefs.dashLayout = .table
        shot("03-performance-table") { $0.section = .performance }
        prefs.dashLayout = .overview
        shot("04-campaigns") { $0.section = .campaigns }
        shot("05-review-sheet") { state in
            state.section = .campaigns
            if let c = state.campaigns.first {
                state.pending[c.id] = .paused
                if let ad = c.adsets.first?.ads.last {
                    state.pending[ad.id] = .active
                }
            }
            state.draft = DraftCampaign()
            state.reviewOpen = true
        }
        shot("06-create-wizard") { state in
            state.section = .campaigns
            state.createOpen = true
        }
        shot("07-drawer") { state in
            state.section = .campaigns
            state.drawerCampaignID = state.campaigns.first?.id
        }
        shot("08-diagnostics") { $0.section = .diagnostics }
        shot("09-catalog") { $0.section = .catalog }
        shot("10-datasets") { $0.section = .datasets }
        shot("11-dark-overview", dark: true) { $0.section = .performance }
        shot("12-dark-campaigns", dark: true) { $0.section = .campaigns }
        shot("13-connect", ) { state in
            state.section = .performance
            state.connectOpen = true
        }
        exit(0)
    }

    // `Pacer --connect <token> <account_id> [page_id]` — store credentials in
    // the Keychain from the app's own code signature, then exit.
    private static func connectIfRequested() {
        guard let idx = CommandLine.arguments.firstIndex(of: "--connect"),
              CommandLine.arguments.count > idx + 2 else { return }
        let args = CommandLine.arguments
        let creds = Credentials(accessToken: args[idx + 1], accountId: args[idx + 2],
                                pageId: args.count > idx + 3 ? args[idx + 3] : "")
        do {
            try creds.save()
            print("connected: \(creds.actId)")
            exit(0)
        } catch {
            print("connect failed: \(error.localizedDescription)")
            exit(1)
        }
    }

    // `Pacer --live-check` — load a snapshot through the CLI backend with the
    // stored credentials and print a summary. Exercises the whole live path.
    private static func liveCheckIfRequested() {
        guard CommandLine.arguments.contains("--live-check") else { return }
        guard let creds = Credentials.load() else {
            print("live-check: no credentials in Keychain")
            exit(1)
        }
        Task {
            do {
                let snap = try await CLIBackend(credentials: creds).loadSnapshot()
                print("account: \(snap.account.name) (\(snap.account.accountId)) \(snap.account.currency)")
                print("campaigns: \(snap.campaigns.count)")
                for c in snap.campaigns.prefix(5) {
                    print("  - [\(c.status.rawValue)] \(c.name) · \(c.objective.rawValue) · daily \(Fmt.money(c.daily, compact: true)) · \(c.adsets.count) adsets")
                }
                print("series points: \(snap.seriesSpend.count), diagnostics: \(snap.diagnostics.count)")
                exit(0)
            } catch {
                print("live-check failed: \(error.localizedDescription)")
                exit(1)
            }
        }
        RunLoop.main.run()
    }
}
