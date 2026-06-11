import SwiftUI

// Live backend on top of Meta's ads-cli, verified against meta-ads 1.0.1:
//   meta --no-input -o json ads <noun> <verb> [args]
// Notes from real runs:
//  - output/interactivity flags are GLOBAL (before `ads`)
//  - empty list commands print the literal text "No results."
//  - write commands print a human line *before* the JSON payload
//  - list commands default to 10 rows → always pass --limit
//  - statuses/objectives are lowercase choices; budgets are in minor units
//  - adset create takes CAMPAIGN_ID positionally; ad create takes ADSET_ID

struct CLIBackend: AdsBackend {
    let credentials: Credentials
    var isLive: Bool { true }

    /// Campaigns beyond this count skip per-campaign insight calls
    /// (the Marketing API allows ~200 calls/hour).
    private static let insightsCap = 12

    private func run(_ args: [String]) async throws -> String {
        try await Sidecar.shared.meta(["--no-input", "-o", "json"] + args,
                                      credentials: credentials)
    }

    // Tolerant JSON extraction: skip human-readable lines before the payload,
    // treat "No results." as an empty list.
    private func json(_ args: [String]) async throws -> Any {
        let out = try await run(args)
        return try Self.parse(out)
    }

    static func parse(_ out: String) throws -> Any {
        let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.contains("No results") { return [[String: Any]]() }
        if let start = trimmed.firstIndex(where: { $0 == "[" || $0 == "{" }),
           let data = String(trimmed[start...]).data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) {
            return obj
        }
        throw SidecarError.commandFailed("Unparseable CLI output: \(trimmed.prefix(200))")
    }

    private func rows(_ obj: Any) -> [[String: Any]] {
        if let arr = obj as? [[String: Any]] { return arr }
        if let dict = obj as? [String: Any], let arr = dict["data"] as? [[String: Any]] { return arr }
        return []
    }

    private func num(_ v: Any?) -> Double {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        if let s = v as? String { return Double(s) ?? 0 }
        return 0
    }

    private func str(_ v: Any?) -> String { v as? String ?? "" }

    private func createdId(_ out: String) -> String? {
        guard let obj = try? Self.parse(out) else { return nil }
        return rows(obj).first.map { str($0["id"]) }
    }

    // ── Reference data ─────────────────────────────────────────────────────

    func pages() async throws -> [PageInfo] {
        rows(try await json(["ads", "page", "list", "--limit", "50"])).map {
            PageInfo(id: str($0["id"]), name: str($0["name"]), category: str($0["category"]))
        }
    }

    func accounts() async throws -> [AccountInfo] {
        rows(try await json(["ads", "adaccount", "list"])).map {
            AccountInfo(id: str($0["id"]), name: str($0["name"]), currency: str($0["currency"]))
        }
    }

    // ── Snapshot ───────────────────────────────────────────────────────────

    func loadSnapshot() async throws -> AccountSnapshot {
        var account = AdsAccount(brand: "Meta Ads", name: credentials.actId, accountId: credentials.actId,
                                 currency: "USD", region: "", daySpend: 0, budget: 0)
        if let acctObj = try? await json(["ads", "adaccount", "list"]) {
            if let row = rows(acctObj).first(where: { str($0["id"]) == credentials.actId }) ?? rows(acctObj).first {
                let name = str(row["name"])
                if !name.isEmpty { account.name = name; account.brand = name }
                let cur = str(row["currency"])
                if !cur.isEmpty { account.currency = cur }
                let tz = str(row["timezone_name"])
                if let region = tz.components(separatedBy: "/").last {
                    account.region = region.replacingOccurrences(of: "_", with: " ")
                }
            }
        }
        Fmt.currency = account.currency

        let campaignRows = rows(try await json(["ads", "campaign", "list", "--limit", "200"]))
        let adsetRows = (try? await json(["ads", "adset", "list", "--limit", "500"])).map(rows) ?? []
        let adRows = (try? await json(["ads", "ad", "list", "--limit", "500"])).map(rows) ?? []

        // 90 days of account-level daily data — the dashboard's range picker
        // slices this client-side, so 7/30/90 are all real.
        let dailyRows = (try? await json(["ads", "insights", "get", "--date-preset", "last_90d",
                                          "--time-increment", "daily",
                                          "--fields", "spend,actions,action_values"])).map(rows) ?? []
        var seriesSpend = dailyRows.map { num($0["spend"]) }
        var seriesRevenue = dailyRows.map { revenue(from: $0) }
        if seriesSpend.count < 2 { seriesSpend = [0, 0] }
        if seriesRevenue.count < 2 { seriesRevenue = [0, 0] }
        let seriesRoas = zip(seriesRevenue, seriesSpend).map { $1 > 0 ? $0 / $1 : 0 }

        // Per-campaign insights — one CLI call each, capped to respect rate limits.
        let fields = "spend,impressions,clicks,ctr,reach,cpm,actions,action_values"
        var campInsights: [String: [String: Any]] = [:]
        for row in campaignRows.prefix(Self.insightsCap) {
            let id = str(row["id"])
            if let obj = try? await json(["ads", "insights", "get", "--campaign-id", id,
                                          "--date-preset", "last_30d", "--fields", fields]),
               let first = rows(obj).first {
                campInsights[id] = first
            }
        }

        let thumbs: [Color] = [Color(hex: 0xE91E78), Color(hex: 0x2D3DEC), Color(hex: 0x1FB36B),
                               Color(hex: 0xF4A52A), Color(hex: 0x7A5AE0)]
        // Creative previews: the CLI's fixed output may not carry URLs, so a
        // single batched (read-only) Graph API call fills the gaps.
        let creativeInfo = await creativePreviews(adRows: adRows)
        var adsByAdset: [String: [Ad]] = [:]
        for (i, row) in adRows.enumerated() {
            let id = str(row["id"])
            let info = creativeInfo[id]
            let format: AdFormat = info?.isVideo == true ? .video : .image
            let ad = Ad(id: id, name: str(row["name"]), status: status(row),
                        spend: 0, revenue: 0, roas: 0, ctr: 0, format: format,
                        thumb: thumbs[i % thumbs.count],
                        thumbURL: info?.thumb, imageURL: info?.image, previewURL: info?.preview)
            adsByAdset[str(row["adset_id"]), default: []].append(ad)
        }
        var adsetsByCampaign: [String: [AdSet]] = [:]
        for row in adsetRows {
            let id = str(row["id"])
            let adset = AdSet(id: id, name: str(row["name"]), status: status(row),
                              daily: budget(row), spend: 0, revenue: 0, roas: 0, purchases: 0,
                              cpa: 0, ctr: 0, learning: .active,
                              audience: str(row["optimization_goal"]).replacingOccurrences(of: "_", with: " ").lowercased(),
                              placements: "", ads: adsByAdset[id] ?? [])
            adsetsByCampaign[str(row["campaign_id"]), default: []].append(adset)
        }
        var campaigns: [Campaign] = campaignRows.map { row in
            let id = str(row["id"])
            let ins = campInsights[id] ?? [:]
            let spend = num(ins["spend"])
            let rev = revenue(from: ins)
            let purchases = actionCount(from: ins, type: "purchase")
            return Campaign(id: id, name: str(row["name"]), objective: objective(row),
                            status: status(row), daily: budget(row), spend: spend, revenue: rev,
                            roas: spend > 0 ? rev / spend : 0, purchases: purchases,
                            cpa: purchases > 0 ? spend / Double(purchases) : 0,
                            ctr: num(ins["ctr"]), learning: .active,
                            reach: Int(num(ins["reach"])), cpm: num(ins["cpm"]),
                            adsets: adsetsByCampaign[id] ?? [])
        }
        campaigns.sort { $0.spend > $1.spend }

        account.budget = campaigns.filter { $0.status == .active }.reduce(0) { $0 + $1.daily }
        account.daySpend = seriesSpend.last ?? 0

        // Spend breakdowns (placement, demographics, geo) — skipped when the
        // account has no spend at all to save rate budget.
        var breakdowns = BreakdownData()
        if seriesSpend.reduce(0, +) > 0 {
            breakdowns.placements = await breakdown("platform_position")
            breakdowns.ages = await breakdown("age")
            breakdowns.genders = await breakdown("gender")
            breakdowns.countries = Array(await breakdown("country").prefix(5))
        }

        // Pixels (datasets) for the Datasets section and the wizard's picker.
        let pixels = ((try? await json(["ads", "dataset", "list", "--limit", "50"])).map(rows) ?? []).map {
            PixelInfo(id: str($0["id"]), name: str($0["name"]), lastFired: str($0["last_fired_time"]))
        }

        return AccountSnapshot(
            account: account,
            kpis: kpis(seriesSpend: seriesSpend, seriesRevenue: seriesRevenue, campaigns: campaigns),
            campaigns: campaigns,
            diagnostics: liveDiagnostics(campaigns: campaigns, pixels: pixels),
            seriesSpend: seriesSpend, seriesRevenue: seriesRevenue, seriesRoas: seriesRoas,
            products: [], events: [],
            pixels: pixels, breakdowns: breakdowns)
    }

    // ── Creative previews ──────────────────────────────────────────────────

    struct CreativePreview {
        var thumb: URL?
        var image: URL?
        var preview: URL?
        var isVideo: Bool
    }

    /// Thumbnail/image/preview URLs per ad id. Tries any URLs the CLI rows
    /// already carry, then fills the rest with one batched Graph API read
    /// (same token, read-only): /?ids=…&fields=preview_shareable_link,
    /// creative{thumbnail_url,image_url,video_id}.
    private func creativePreviews(adRows: [[String: Any]]) async -> [String: CreativePreview] {
        var out: [String: CreativePreview] = [:]
        var missing: [String] = []
        for row in adRows {
            let id = str(row["id"])
            guard !id.isEmpty else { continue }
            let creative = row["creative"] as? [String: Any] ?? [:]
            let thumb = URL(string: str(creative["thumbnail_url"]))
            let image = URL(string: str(creative["image_url"]))
            if thumb != nil || image != nil {
                out[id] = CreativePreview(thumb: thumb, image: image,
                                          preview: URL(string: str(row["preview_shareable_link"])),
                                          isVideo: !str(creative["video_id"]).isEmpty)
            } else {
                missing.append(id)
            }
        }
        guard !missing.isEmpty, !credentials.accessToken.isEmpty else { return out }
        let token = credentials.accessToken
        // Graph batches up to 50 ids per request.
        for chunk in stride(from: 0, to: missing.count, by: 50).map({ Array(missing[$0..<min($0 + 50, missing.count)]) }) {
            var comps = URLComponents(string: "https://graph.facebook.com/v21.0/")!
            comps.queryItems = [
                URLQueryItem(name: "ids", value: chunk.joined(separator: ",")),
                URLQueryItem(name: "fields", value: "preview_shareable_link,creative{thumbnail_url,image_url,video_id}"),
                URLQueryItem(name: "access_token", value: token),
            ]
            guard let url = comps.url,
                  let (data, _) = try? await URLSession.shared.data(from: url),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            for (adId, value) in obj {
                guard let row = value as? [String: Any] else { continue }
                let creative = row["creative"] as? [String: Any] ?? [:]
                out[adId] = CreativePreview(
                    thumb: URL(string: str(creative["thumbnail_url"])),
                    image: URL(string: str(creative["image_url"])),
                    preview: URL(string: str(row["preview_shareable_link"])),
                    isVideo: !str(creative["video_id"]).isEmpty)
            }
        }
        return out
    }

    private func breakdown(_ dimension: String) async -> [BreakdownSlice] {
        guard let obj = try? await json(["ads", "insights", "get", "--date-preset", "last_30d",
                                         "--breakdown", dimension, "--fields", "spend"]) else { return [] }
        return rows(obj).compactMap { row in
            let spend = num(row["spend"])
            guard spend > 0 else { return nil }
            let raw = str(row[dimension])
            let label = raw.isEmpty ? "Unknown"
                : raw.replacingOccurrences(of: "_", with: " ").capitalized
            return BreakdownSlice(label: label, value: spend)
        }.sorted { $0.value > $1.value }
    }

    // ── Writes (the review sheet's Approve) ────────────────────────────────

    func apply(_ plan: ChangePlan) async throws -> ApplyReport {
        var report = ApplyReport()

        for change in plan.statusChanges {
            _ = try await run(["ads", noun(change.kind), "update", change.entityId,
                               "--status", change.to.rawValue])
        }
        for change in plan.budgetChanges {
            _ = try await run(["ads", noun(change.kind), "update", change.entityId,
                               "--daily-budget", minorUnits(change.to)])
        }
        for del in plan.deletes {
            _ = try await Sidecar.shared.meta(
                ["--no-input", "ads", noun(del.kind), "delete", del.entityId, "--force"],
                credentials: credentials)
        }

        if let d = plan.draft {
            report = try await create(d, launchLive: plan.launchLive, report: report)
        }
        return report
    }

    // Full chain: campaign (CBO budget) → ad set → creative → ad.
    // Everything is created paused unless launchLive.
    private func create(_ d: DraftCampaign, launchLive: Bool, report: ApplyReport) async throws -> ApplyReport {
        var report = report
        let status = launchLive ? "active" : "paused"

        let campaignOut = try await run(["ads", "campaign", "create",
                                         "--name", d.name,
                                         "--objective", d.objective.apiValue,
                                         "--daily-budget", minorUnits(d.daily),
                                         "--status", status])
        guard let campaignId = createdId(campaignOut), !campaignId.isEmpty else {
            throw SidecarError.commandFailed("Campaign created but its ID was not returned")
        }
        report.createdCampaignId = campaignId

        var adsetArgs = ["ads", "adset", "create", campaignId,
                         "--name", d.adsetName,
                         "--optimization-goal", d.optimization.rawValue,
                         "--billing-event", d.optimization.billingEvent,
                         // the API rejects ad sets without a bid cap on this path
                         "--bid-amount", minorUnits(max(d.bidAmount, 1)),
                         "--status", status,
                         "--targeting-countries", d.countries.replacingOccurrences(of: " ", with: "")]
        if !d.pixelId.isEmpty {
            adsetArgs += ["--pixel-id", d.pixelId, "--custom-event-type", d.conversionEvent.rawValue]
        }
        if d.schedule {
            let iso = ISO8601DateFormatter()
            adsetArgs += ["--start-time", iso.string(from: d.startDate),
                          "--end-time", iso.string(from: d.endDate)]
        }
        let adsetOut: String
        do {
            adsetOut = try await run(adsetArgs)
        } catch {
            report.warnings.append("ad set failed: \(error.localizedDescription)")
            return report
        }
        guard let adsetId = createdId(adsetOut), !adsetId.isEmpty else {
            report.warnings.append("ad set created but ID missing — ad skipped")
            return report
        }

        guard d.hasCreative else {
            report.warnings.append(d.media.isEmpty ? "no creative media — ad skipped"
                                                   : "no Facebook Page — ad skipped")
            return report
        }

        var creativeArgs = ["ads", "creative", "create",
                            "--name", "\(d.adName) — creative",
                            "--page-id", d.pageId]
        let videoExts = ["mp4", "mov", "avi", "mkv", "wmv"]
        if d.isDCO {
            for url in d.media.prefix(10) {
                creativeArgs += [videoExts.contains(url.pathExtension.lowercased()) ? "--videos" : "--images", url.path]
            }
            for t in d.headlines.prefix(5) { creativeArgs += ["--titles", t] }
            for b in d.texts.prefix(5) { creativeArgs += ["--bodies", b] }
            creativeArgs += ["--call-to-actions", d.cta.rawValue]
        } else {
            if let url = d.media.first {
                creativeArgs += [videoExts.contains(url.pathExtension.lowercased()) ? "--video" : "--image", url.path]
            }
            if let t = d.headlines.first { creativeArgs += ["--title", t] }
            if let b = d.texts.first { creativeArgs += ["--body", b] }
            creativeArgs += ["--call-to-action", d.cta.rawValue]
        }
        if !d.linkURL.isEmpty { creativeArgs += ["--link-url", d.linkURL] }

        let creativeOut: String
        do {
            creativeOut = try await run(creativeArgs)
        } catch {
            let msg = error.localizedDescription
            if msg.contains("development mode") {
                report.warnings.append("Ad skipped: your Meta app is in Development Mode — switch it to Live at developers.facebook.com/apps, then create the ad again")
            } else {
                report.warnings.append("creative failed: \(String(msg.suffix(160)))")
            }
            return report
        }
        guard let creativeId = createdId(creativeOut), !creativeId.isEmpty else {
            report.warnings.append("creative created but ID missing — ad skipped")
            return report
        }

        var adArgs = ["ads", "ad", "create", adsetId,
                      "--name", d.adName,
                      "--creative-id", creativeId,
                      "--status", status]
        if !d.pixelId.isEmpty { adArgs += ["--pixel-id", d.pixelId] }
        do {
            _ = try await run(adArgs)
        } catch {
            report.warnings.append("ad failed: \(error.localizedDescription)")
        }
        return report
    }

    private func noun(_ kind: EntityKind) -> String {
        switch kind {
        case .campaign: return "campaign"
        case .adset: return "adset"
        case .ad: return "ad"
        }
    }

    // ── Helpers ────────────────────────────────────────────────────────────

    private var currencyOffset: Double {
        // Marketing API budgets are in minor units, except these currencies
        // (Meta's documented offset-1 list — verified live for IDR).
        ["CLP", "COP", "CRC", "HUF", "IDR", "ISK", "JPY", "KRW",
         "MWK", "PYG", "TWD", "UGX", "VND", "XAF", "XOF"].contains(Fmt.currency) ? 1 : 100
    }

    private func minorUnits(_ v: Double) -> String { String(Int(v * currencyOffset)) }

    private func status(_ row: [String: Any]) -> EntityStatus {
        let s = (str(row["effective_status"]).isEmpty ? str(row["status"]) : str(row["effective_status"])).uppercased()
        if s == "ACTIVE" { return .active }
        if s == "ARCHIVED" { return .archived }
        return .paused
    }

    private func objective(_ row: [String: Any]) -> Objective {
        let s = str(row["objective"]).uppercased()
        if s.contains("SALES") || s.contains("CONVERSIONS") { return .sales }
        if s.contains("LEAD") { return .leads }
        if s.contains("TRAFFIC") || s.contains("LINK") { return .traffic }
        return .awareness
    }

    private func budget(_ row: [String: Any]) -> Double {
        num(row["daily_budget"]) / currencyOffset
    }

    private func revenue(from ins: [String: Any]) -> Double {
        if let values = ins["action_values"] as? [[String: Any]] {
            for v in values where str(v["action_type"]).contains("purchase") {
                return num(v["value"])
            }
        }
        if let roas = ins["purchase_roas"] as? [[String: Any]], let first = roas.first {
            return num(first["value"]) * num(ins["spend"])
        }
        return 0
    }

    private func actionCount(from ins: [String: Any], type: String) -> Int {
        if let actions = ins["actions"] as? [[String: Any]] {
            for a in actions where str(a["action_type"]).contains(type) {
                return Int(num(a["value"]))
            }
        }
        return 0
    }

    private func kpis(seriesSpend: [Double], seriesRevenue: [Double], campaigns: [Campaign]) -> KpiSet {
        func pct(_ a: Double, _ b: Double) -> Double { b > 0 ? ((a - b) / b * 1000).rounded() / 10 : 0 }
        let s7 = seriesSpend.suffix(7).reduce(0, +), sP = seriesSpend.suffix(14).prefix(7).reduce(0, +)
        let r7 = seriesRevenue.suffix(7).reduce(0, +), rP = seriesRevenue.suffix(14).prefix(7).reduce(0, +)
        let purchases = Double(campaigns.reduce(0) { $0 + $1.purchases })
        let spendTotal = campaigns.reduce(0) { $0 + $1.spend }
        let ctrWeighted = campaigns.reduce(0.0) { $0 + $1.ctr * $1.spend }
        let roasSeries = zip(seriesRevenue, seriesSpend).map { $1 > 0 ? $0 / $1 : 0 }
        return KpiSet(
            spend: Kpi(value: s7, delta: pct(s7, sP), series: Array(seriesSpend.suffix(7)), fmt: .money),
            revenue: Kpi(value: r7, delta: pct(r7, rP), series: Array(seriesRevenue.suffix(7)), fmt: .money),
            roas: Kpi(value: s7 > 0 ? r7 / s7 : 0, delta: pct(s7 > 0 ? r7 / s7 : 0, sP > 0 ? rP / sP : 0),
                      series: Array(roasSeries.suffix(7)), fmt: .x),
            purchases: Kpi(value: purchases, delta: 0, series: Array(seriesRevenue.suffix(7)), fmt: .int),
            cpa: Kpi(value: purchases > 0 ? spendTotal / purchases : 0, delta: 0,
                     series: Array(seriesSpend.suffix(7)), fmt: .money, invert: true),
            ctr: Kpi(value: spendTotal > 0 ? ctrWeighted / spendTotal : 0, delta: 0,
                     series: Array(roasSeries.suffix(7)), fmt: .pct),
            reach: Kpi(value: Double(campaigns.reduce(0) { $0 + ($1.reach ?? 0) }), delta: 0,
                       series: Array(seriesRevenue.suffix(7)), fmt: .int),
            cpm: Kpi(value: campaigns.compactMap(\.cpm).max() ?? 0, delta: 0,
                     series: Array(seriesSpend.suffix(7)), fmt: .money, invert: true))
    }

    private func liveDiagnostics(campaigns: [Campaign], pixels: [PixelInfo]) -> [Diagnostic] {
        var out: [Diagnostic] = []
        if campaigns.isEmpty {
            out.append(Diagnostic(id: "empty", level: .info, title: "No campaigns yet",
                                  target: "Account",
                                  detail: "Create your first campaign — it will be saved paused until you approve the launch plan.",
                                  icon: "sparkles"))
        }
        for c in campaigns where c.status == .active && c.roas > 0 && c.roas < 1.5 {
            out.append(Diagnostic(id: "lo_\(c.id)", level: .danger, title: "ROAS below breakeven",
                                  target: c.name,
                                  detail: String(format: "%.2f× over the last 30 days. Review creative or audience.", c.roas),
                                  icon: "flame"))
        }
        let paused = campaigns.filter { $0.status == .paused }.count
        if paused > 0 {
            out.append(Diagnostic(id: "paused", level: .info, title: "Paused campaigns",
                                  target: "\(paused) campaign\(paused == 1 ? "" : "s")",
                                  detail: "Saved but not delivering. Resume them from Campaigns when ready.",
                                  icon: "pause.circle"))
        }
        let emptyAdsets = campaigns.flatMap(\.adsets).filter { $0.ads.isEmpty }
        if !emptyAdsets.isEmpty {
            out.append(Diagnostic(id: "noads", level: .warning, title: "Ad set\(emptyAdsets.count == 1 ? "" : "s") without ads",
                                  target: emptyAdsets.map(\.name).prefix(2).joined(separator: ", "),
                                  detail: "These can't deliver. If ad creation was skipped, your Meta app may be in Development Mode — switch it to Live at developers.facebook.com/apps, then create the ad again.",
                                  icon: "rectangle.dashed"))
        }
        if let pixel = pixels.first(where: { !$0.lastFired.isEmpty }) {
            out.append(Diagnostic(id: "px_\(pixel.id)", level: .success, title: "Pixel receiving events",
                                  target: pixel.name,
                                  detail: "Last event \(pixel.lastFired.prefix(10)). Use it in the create wizard for conversion tracking.",
                                  icon: "checkmark.circle"))
        }
        if out.isEmpty {
            out.append(Diagnostic(id: "ok", level: .success, title: "No delivery issues detected",
                                  target: "Account", detail: "All active campaigns are delivering normally.",
                                  icon: "checkmark.circle"))
        }
        return out
    }
}
