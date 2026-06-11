import SwiftUI

// Debug helper: `Pacer.app/Contents/MacOS/Pacer --snapshot /tmp/dir` renders
// the key screens to PNG and exits. Used to verify the UI against the design
// without a live window capture.

@MainActor
enum SnapshotRunner {
    static private(set) var isActive = false

    static func runIfRequested() {
        connectIfRequested()
        connectOpenAIIfRequested()
        liveCheckIfRequested()
        testCreateIfRequested()
        testAIIfRequested()
        testAnalystIfRequested()
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

    // `MadMac --test-analyst` — exercises the Analyst end to end on sample
    // data: signal math, AI daily brief + recommendations, copy-from-winners.
    private static func testAnalystIfRequested() {
        guard CommandLine.arguments.contains("--test-analyst") else { return }
        Task {
            do {
                let perf = try await SampleBackend().adPerformance()
                let winners = perf.filter(\.isWinner)
                let bleeders = perf.filter(\.isBleeder)
                let fatigued = perf.filter(\.isFatigued)
                let dying = perf.filter(\.isDying)
                print("signals: \(perf.count) ads → winners=\(winners.map(\.name)) bleeders=\(bleeders.map(\.name)) fatigued=\(fatigued.map(\.name)) dying=\(dying.map(\.name))")
                guard !winners.isEmpty, !bleeders.isEmpty else { print("FAIL: signal math found no winners/bleeders in sample data"); exit(1) }

                let result = try await Analyst.run(perf: perf, snapshot: SampleData.snapshot)
                print("brief (\(result.brief.count) chars): \(result.brief.prefix(220))…")
                print("recommendations: \(result.recommendations.count)")
                for rec in result.recommendations {
                    print("  - [\(rec.severity)] \(rec.title) → \(rec.actionType) \(rec.entityKind) \(rec.entityId) \(rec.actionType == "set_budget" ? "to \(Int(rec.value))" : "")")
                }
                guard !result.brief.isEmpty else { print("FAIL: empty brief"); exit(1) }

                let copy = try await Analyst.copyFromWinners(winners, objective: "Sales")
                print("winner copy: \(copy.headlines.count) headlines · e.g. \u{201C}\(copy.headlines.first ?? "")\u{201D}")
                print("saved brief is today: \(Analyst.savedBriefIsToday(accountId: SampleData.account.accountId))")
                print("PASS (analyst)")
                exit(0)
            } catch {
                print("FAIL: \(error.localizedDescription)")
                exit(1)
            }
        }
        RunLoop.main.run()
    }

    // `MadMac --connect-openai <key>` — store the OpenAI key in the Keychain.
    private static func connectOpenAIIfRequested() {
        guard let idx = CommandLine.arguments.firstIndex(of: "--connect-openai"),
              CommandLine.arguments.count > idx + 1 else { return }
        do {
            try AIPrefs.saveKey(CommandLine.arguments[idx + 1])
            UserDefaults.standard.set(true, forKey: "aiEnabled")
            print("openai key stored, AI enabled")
            exit(0)
        } catch {
            print("failed: \(error.localizedDescription)")
            exit(1)
        }
    }

    // `MadMac --test-ai <image>` — exercises every AI feature with real API
    // calls: connection, copywriter, brief parse, policy check, image
    // generation (1 low-quality), image edit, and account analysis.
    private static func testAIIfRequested() {
        guard let idx = CommandLine.arguments.firstIndex(of: "--test-ai"),
              CommandLine.arguments.count > idx + 1 else { return }
        let imagePath = CommandLine.arguments[idx + 1]
        UserDefaults.standard.set("low", forKey: "_ignored")  // keep image cost minimal below
        Task {
            var failures = 0
            func check(_ name: String, _ run: () async throws -> String) async {
                do { print("✓ \(name): \(try await run())") }
                catch { print("✗ \(name): \(error.localizedDescription)"); failures += 1 }
            }

            await check("connection") {
                "\(try await OpenAIClient().listModels().count) models"
            }
            await check("copywriter") {
                let set = try await AIService.generateCopy(
                    product: "Mayar — platform pembayaran online untuk UMKM Indonesia, terima pembayaran lewat link",
                    tone: "Casual", language: "Indonesian", objective: "Sales")
                return "\(set.headlines.count) headlines, \(set.texts.count) texts · e.g. \u{201C}\(set.headlines.first ?? "")\u{201D}"
            }
            await check("brief parse") {
                let d = try await AIService.parseBrief(
                    "jualan produk pembayaran digital Mayar, budget 250rb per hari, target seluruh indonesia, optimize purchase, link ke mayar.id",
                    currency: "IDR",
                    pixels: [PixelInfo(id: "1032483741271279", name: "ADASSD", lastFired: "2026-06-05")],
                    pages: [PageInfo(id: "110149734238796", name: "Mayar", category: "Internet company")])
                return "name=\(d.name) daily=\(Int(d.daily)) bid=\(Int(d.bidAmount)) opt=\(d.optimization.rawValue) pixel=\(d.pixelId) link=\(d.linkURL)"
            }
            await check("policy check (risky copy)") {
                let report = try await AIService.policyCheck(
                    headline: "Kulit putih dalam 3 hari, dijamin!",
                    text: "Punya jerawat membandel? Krim ini menghilangkan jerawat kamu selamanya, hasil terlihat sebelum dan sesudah!",
                    objective: "Sales")
                return "risk=\(report.risk), \(report.flags.count) flags"
            }
            let savedQuality = UserDefaults.standard.string(forKey: "aiImageQuality")
            UserDefaults.standard.set(ImageQuality.low.rawValue, forKey: "aiImageQuality")
            var generated: URL?
            await check("image generation (1× low)") {
                let urls = try await AIService.generateImages(
                    prompt: "Minimalist product ad photo: smartphone showing a payment success screen, pastel background, soft studio light",
                    size: "1024x1024", count: 1)
                generated = urls.first
                return urls.map(\.lastPathComponent).joined(separator: ", ")
            }
            await check("image edit") {
                let source = generated ?? URL(fileURLWithPath: imagePath)
                let url = try await AIService.editImage(source, instruction: "make the background a warm sunset gradient")
                return url.lastPathComponent
            }
            UserDefaults.standard.set(savedQuality, forKey: "aiImageQuality")
            await check("account analysis (sample data)") {
                let insights = try await AIService.analyze(SampleData.snapshot)
                let actionable = insights.filter { $0.actionType != "none" }.count
                return "\(insights.count) insights (\(actionable) actionable) · e.g. \u{201C}\(insights.first?.title ?? "")\u{201D}"
            }
            print(failures == 0 ? "PASS (all AI features)" : "FAIL (\(failures) failures)")
            exit(failures == 0 ? 0 : 1)
        }
        RunLoop.main.run()
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
