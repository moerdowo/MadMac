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
        testCreateIfRequested()
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
            if state.campaigns.count > 1 {
                state.pendingBudgets[state.campaigns[1].id] = state.campaigns[1].daily * 1.5
            }
            if state.campaigns.count > 2 {
                state.pendingDeletes.insert(state.campaigns[2].id)
            }
            var d = DraftCampaign()
            d.media = [URL(fileURLWithPath: "/tmp/ugc-hook-15s.mp4")]
            d.headline = "Glow in 2 weeks"
            d.text = "Kulit lebih cerah dalam 2 minggu ✨"
            d.linkURL = "https://lumio.id"
            d.pixelId = "408827145"
            state.draft = d
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

    // `MadMac --test-create <image>` — end-to-end test of the apply pipeline
    // against the real account: full create chain (campaign → ad set →
    // creative upload → ad), then budget edit, archive, and delete, leaving
    // the account exactly as it was. Everything is created PAUSED.
    private static func testCreateIfRequested() {
        guard let idx = CommandLine.arguments.firstIndex(of: "--test-create"),
              CommandLine.arguments.count > idx + 1 else { return }
        let imagePath = CommandLine.arguments[idx + 1]
        guard let creds = Credentials.load() else { print("no credentials"); exit(1) }
        let backend = CLIBackend(credentials: creds)

        Task {
            do {
                // reference data through the real code paths
                let snap = try await backend.loadSnapshot()
                let pages = try await backend.pages()
                guard let page = pages.first else { print("FAIL: no page available"); exit(1) }
                let pixel = snap.pixels.first
                print("using page \(page.name) (\(page.id)), pixel \(pixel?.id ?? "none")")

                var d = DraftCampaign()
                d.name = "MadMac full-chain test (safe to delete)"
                d.objective = .sales
                d.daily = 150_000
                d.countries = "ID"
                d.optimization = .offsiteConversions
                d.pixelId = pixel?.id ?? ""
                d.adName = "MadMac test ad"
                d.media = [URL(fileURLWithPath: imagePath)]
                d.headline = "MadMac test headline"
                d.text = "Created by MadMac's automated test. Paused, never delivers."
                d.linkURL = "https://mayar.id"
                d.cta = .learnMore
                d.pageId = page.id

                // 1 — full create chain
                let report = try await backend.apply(ChangePlan(draft: d, launchLive: false))
                guard let cid = report.createdCampaignId else { print("FAIL: no campaign id"); exit(1) }
                print("created campaign \(cid); warnings: \(report.warnings.isEmpty ? "none" : report.warnings.joined(separator: " · "))")

                let snap2 = try await backend.loadSnapshot()
                guard let created = snap2.campaigns.first(where: { $0.id == cid }) else {
                    print("FAIL: campaign not in snapshot"); exit(1)
                }
                print("verify: status=\(created.status.rawValue) daily=\(Int(created.daily)) adsets=\(created.adsets.count) ads=\(created.adsets.first?.ads.count ?? 0)")

                // 2 — budget edit through the same pipeline
                _ = try await backend.apply(ChangePlan(budgetChanges: [
                    StagedBudget(entityId: cid, kind: .campaign, name: d.name, from: 150_000, to: 225_000)
                ]))
                print("budget edit applied (150000 → 225000)")

                // 3 — archive
                _ = try await backend.apply(ChangePlan(statusChanges: [
                    StagedChange(entityId: cid, kind: .campaign, name: d.name, base: .paused, to: .archived)
                ]))
                print("archived")

                // 4 — delete (cascades to ad set and ad), plus the creative
                _ = try await backend.apply(ChangePlan(deletes: [
                    StagedDelete(entityId: cid, kind: .campaign, name: d.name)
                ]))
                let creativesOut = try await Sidecar.shared.meta(
                    ["--no-input", "-o", "json", "ads", "creative", "list", "--limit", "50"], credentials: creds)
                if let arr = try? CLIBackend.parse(creativesOut) as? [[String: Any]] {
                    for c in arr where (c["name"] as? String ?? "").contains("MadMac test ad") {
                        if let id = c["id"] as? String {
                            _ = try? await Sidecar.shared.meta(
                                ["--no-input", "ads", "creative", "delete", id, "--force"], credentials: creds)
                            print("cleaned creative \(id)")
                        }
                    }
                }
                let snap3 = try await backend.loadSnapshot()
                print("final campaigns: \(snap3.campaigns.map(\.name))")
                print(snap3.campaigns.contains(where: { $0.id == cid }) ? "FAIL: test campaign still present" : "PASS")
                exit(0)
            } catch {
                print("FAIL: \(error.localizedDescription)")
                exit(1)
            }
        }
        RunLoop.main.run()
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
