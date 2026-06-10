import SwiftUI

// Live backend on top of Meta's ads-cli, verified against meta-ads 1.0.1:
//   meta --no-input -o json ads <noun> <verb> [args]
// Notes from real runs:
//  - output/interactivity flags are GLOBAL (before `ads`)
//  - empty list commands print the literal text "No results."
//  - write commands print a human line *before* the JSON payload
//  - list commands default to 10 rows → always pass --limit
//  - statuses/objectives are lowercase choices; budgets are in minor units

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

        // Account-level daily series for the dashboard chart.
        let dailyRows = (try? await json(["ads", "insights", "get", "--date-preset", "last_30d",
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

        // Hierarchy (ad set / ad metrics come from their parent's share; the
        // CLI exposes per-entity insights only one call at a time).
        let thumbs: [Color] = [Color(hex: 0xE91E78), Color(hex: 0x2D3DEC), Color(hex: 0x1FB36B),
                               Color(hex: 0xF4A52A), Color(hex: 0x7A5AE0)]
        var adsByAdset: [String: [Ad]] = [:]
        for (i, row) in adRows.enumerated() {
            let ad = Ad(id: str(row["id"]), name: str(row["name"]), status: status(row),
                        spend: 0, revenue: 0, roas: 0, ctr: 0, format: .image,
                        thumb: thumbs[i % thumbs.count])
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

        return AccountSnapshot(
            account: account,
            kpis: kpis(seriesSpend: seriesSpend, seriesRevenue: seriesRevenue, campaigns: campaigns),
            campaigns: campaigns,
            diagnostics: liveDiagnostics(campaigns: campaigns),
            seriesSpend: seriesSpend, seriesRevenue: seriesRevenue, seriesRoas: seriesRoas,
            products: [], events: [])
    }

    // ── Writes (the review sheet's Approve) ────────────────────────────────

    func apply(changes: [StagedChange], draft: DraftCampaign?, launchLive: Bool) async throws {
        for change in changes {
            let noun: String
            switch change.kind {
            case .campaign: noun = "campaign"
            case .adset: noun = "adset"
            case .ad: noun = "ad"
            }
            _ = try await run(["ads", noun, "update", change.entityId,
                               "--status", change.to == .active ? "active" : "paused"])
        }
        if let d = draft {
            // The CLI creates campaigns PAUSED by default. Ad set + ad creation
            // need page/pixel prerequisites, so v1 creates the campaign shell.
            _ = try await run(["ads", "campaign", "create",
                               "--name", d.name,
                               "--objective", d.objective.apiValue,
                               "--daily-budget", String(Int(d.daily * currencyOffset)),
                               "--status", launchLive ? "active" : "paused"])
        }
    }

    // ── Helpers ────────────────────────────────────────────────────────────

    private var currencyOffset: Double {
        // Marketing API budgets are in minor units; these currencies have none.
        ["JPY", "KRW", "TWD", "VND"].contains(Fmt.currency) ? 1 : 100
    }

    private func status(_ row: [String: Any]) -> EntityStatus {
        let s = (str(row["effective_status"]).isEmpty ? str(row["status"]) : str(row["effective_status"])).uppercased()
        return s == "ACTIVE" ? .active : .paused
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

    private func liveDiagnostics(campaigns: [Campaign]) -> [Diagnostic] {
        var out: [Diagnostic] = []
        if campaigns.isEmpty {
            out.append(Diagnostic(id: "empty", level: .info, title: "No campaigns yet",
                                  target: "Account",
                                  detail: "Create your first campaign — it will be saved paused until you approve the launch plan.",
                                  icon: "sparkles"))
            return out
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
        if out.isEmpty {
            out.append(Diagnostic(id: "ok", level: .success, title: "No delivery issues detected",
                                  target: "Account", detail: "All active campaigns are delivering normally.",
                                  icon: "checkmark.circle"))
        }
        return out
    }
}
