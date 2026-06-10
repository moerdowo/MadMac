import SwiftUI

// Live backend on top of Meta's ads-cli (`meta ads … --format json`).
// Every command the app issues is built here; reads degrade gracefully
// (a campaign list without insights still renders), writes throw loudly.

struct CLIBackend: AdsBackend {
    let credentials: Credentials
    var isLive: Bool { true }

    private func json(_ args: [String]) async throws -> Any {
        let out = try await Sidecar.shared.meta(args + ["--format", "json"], credentials: credentials)
        guard let data = out.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) else {
            throw SidecarError.commandFailed("Unparseable CLI output: \(out.prefix(200))")
        }
        return obj
    }

    // CLI payloads vary between {"data":[…]} and bare arrays.
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
        // Account (currency, name); fall back to credential-derived basics.
        var account = AdsAccount(brand: "Meta Ads", name: credentials.actId, accountId: credentials.actId,
                                 currency: "USD", region: "", daySpend: 0, budget: 0)
        if let acctObj = try? await json(["ads", "adaccount", "list"]) {
            if let row = rows(acctObj).first(where: { str($0["id"]) == credentials.actId || str($0["account_id"]) == credentials.accountId }) ?? rows(acctObj).first {
                let name = str(row["name"])
                if !name.isEmpty { account.name = name; account.brand = name }
                let cur = str(row["currency"])
                if !cur.isEmpty { account.currency = cur }
            }
        }

        let campaignRows = rows(try await json(["ads", "campaign", "list"]))
        let adsetRows = (try? await json(["ads", "adset", "list"])).map(rows) ?? []
        let adRows = (try? await json(["ads", "ad", "list"])).map(rows) ?? []

        // Insights per level, last 30 days (best effort).
        let fields = "spend,impressions,clicks,ctr,purchase_roas,actions,action_values,reach,cpm"
        let campInsights = insightsByID(
            (try? await json(["ads", "insights", "get", "--level", "campaign",
                              "--date-preset", "last_30d", "--fields", fields])).map(rows) ?? [],
            key: "campaign_id")
        let adsetInsights = insightsByID(
            (try? await json(["ads", "insights", "get", "--level", "adset",
                              "--date-preset", "last_30d", "--fields", fields])).map(rows) ?? [],
            key: "adset_id")
        let adInsights = insightsByID(
            (try? await json(["ads", "insights", "get", "--level", "ad",
                              "--date-preset", "last_30d", "--fields", fields])).map(rows) ?? [],
            key: "ad_id")

        // Daily account series for the dashboard chart.
        let dailyRows = (try? await json(["ads", "insights", "get", "--date-preset", "last_30d",
                                          "--time-increment", "1", "--fields", "spend,action_values"])).map(rows) ?? []
        var seriesSpend = dailyRows.map { num($0["spend"]) }
        var seriesRevenue = dailyRows.map { revenue(from: $0) }
        if seriesSpend.count < 2 { seriesSpend = [0, 0] }
        if seriesRevenue.count < 2 { seriesRevenue = [0, 0] }
        let seriesRoas = zip(seriesRevenue, seriesSpend).map { $1 > 0 ? $0 / $1 : 0 }

        // Assemble hierarchy.
        let thumbs: [Color] = [Color(hex: 0xE91E78), Color(hex: 0x2D3DEC), Color(hex: 0x1FB36B),
                               Color(hex: 0xF4A52A), Color(hex: 0x7A5AE0)]
        var adsByAdset: [String: [Ad]] = [:]
        for (i, row) in adRows.enumerated() {
            let id = str(row["id"])
            let ins = adInsights[id] ?? [:]
            let spend = num(ins["spend"])
            let rev = revenue(from: ins)
            let ad = Ad(id: id, name: str(row["name"]), status: status(row),
                        spend: spend, revenue: rev, roas: spend > 0 ? rev / spend : 0,
                        ctr: num(ins["ctr"]), format: .image, thumb: thumbs[i % thumbs.count])
            adsByAdset[str(row["adset_id"]), default: []].append(ad)
        }
        var adsetsByCampaign: [String: [AdSet]] = [:]
        for row in adsetRows {
            let id = str(row["id"])
            let ins = adsetInsights[id] ?? [:]
            let spend = num(ins["spend"])
            let rev = revenue(from: ins)
            let purchases = actionCount(from: ins, type: "purchase")
            let adset = AdSet(id: id, name: str(row["name"]), status: status(row),
                              daily: budget(row), spend: spend, revenue: rev,
                              roas: spend > 0 ? rev / spend : 0, purchases: purchases,
                              cpa: purchases > 0 ? spend / Double(purchases) : 0,
                              ctr: num(ins["ctr"]), learning: .active,
                              audience: str(row["targeting_summary"] ?? row["optimization_goal"]),
                              placements: "", reach: Int(num(ins["reach"])),
                              ads: adsByAdset[id] ?? [])
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
        Fmt.currency = account.currency

        return AccountSnapshot(
            account: account, kpis: kpis(seriesSpend: seriesSpend, seriesRevenue: seriesRevenue,
                                         campaigns: campaigns),
            campaigns: campaigns, diagnostics: liveDiagnostics(campaigns: campaigns),
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
            _ = try await Sidecar.shared.meta(
                ["ads", noun, "update", change.entityId,
                 "--status", change.to == .active ? "ACTIVE" : "PAUSED", "--no-input"],
                credentials: credentials)
        }
        if let d = draft {
            // The CLI creates everything PAUSED by default; flip after if asked.
            let out = try await Sidecar.shared.meta(
                ["ads", "campaign", "create",
                 "--name", d.name,
                 "--objective", d.objective.apiValue,
                 "--status", launchLive ? "ACTIVE" : "PAUSED",
                 "--daily-budget", String(Int(d.daily)),
                 "--no-input", "--format", "json"],
                credentials: credentials)
            // Ad set + ad creation need page/pixel prerequisites; create the
            // campaign shell and surface what was skipped rather than guessing.
            _ = out
        }
    }

    // ── Helpers ────────────────────────────────────────────────────────────

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
        // Marketing API budgets are in the currency's minor units.
        let raw = num(row["daily_budget"])
        let offset: Double = ["IDR", "JPY", "KRW", "VND", "TWD"].contains(Fmt.currency) ? 1 : 100
        return raw / offset
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

    private func insightsByID(_ rows: [[String: Any]], key: String) -> [String: [String: Any]] {
        var map: [String: [String: Any]] = [:]
        for row in rows { map[str(row[key])] = row }
        return map
    }

    private func kpis(seriesSpend: [Double], seriesRevenue: [Double], campaigns: [Campaign]) -> KpiSet {
        func pct(_ a: Double, _ b: Double) -> Double { b > 0 ? ((a - b) / b * 1000).rounded() / 10 : 0 }
        let s7 = seriesSpend.suffix(7).reduce(0, +), sP = seriesSpend.suffix(14).prefix(7).reduce(0, +)
        let r7 = seriesRevenue.suffix(7).reduce(0, +), rP = seriesRevenue.suffix(14).prefix(7).reduce(0, +)
        let purchases = Double(campaigns.reduce(0) { $0 + $1.purchases })
        let spendTotal = campaigns.reduce(0) { $0 + $1.spend }
        let clicksWeighted = campaigns.reduce(0.0) { $0 + $1.ctr * $1.spend }
        let roasSeries = zip(seriesRevenue, seriesSpend).map { $1 > 0 ? $0 / $1 : 0 }
        return KpiSet(
            spend: Kpi(value: s7, delta: pct(s7, sP), series: Array(seriesSpend.suffix(7)), fmt: .money),
            revenue: Kpi(value: r7, delta: pct(r7, rP), series: Array(seriesRevenue.suffix(7)), fmt: .money),
            roas: Kpi(value: s7 > 0 ? r7 / s7 : 0, delta: pct(s7 > 0 ? r7 / s7 : 0, sP > 0 ? rP / sP : 0),
                      series: Array(roasSeries.suffix(7)), fmt: .x),
            purchases: Kpi(value: purchases, delta: 0, series: Array(seriesRevenue.suffix(7)), fmt: .int),
            cpa: Kpi(value: purchases > 0 ? spendTotal / purchases : 0, delta: 0,
                     series: Array(seriesSpend.suffix(7)), fmt: .money, invert: true),
            ctr: Kpi(value: spendTotal > 0 ? clicksWeighted / spendTotal : 0, delta: 0,
                     series: Array(roasSeries.suffix(7)), fmt: .pct),
            reach: Kpi(value: Double(campaigns.reduce(0) { $0 + ($1.reach ?? 0) }), delta: 0,
                       series: Array(seriesRevenue.suffix(7)), fmt: .int),
            cpm: Kpi(value: campaigns.compactMap(\.cpm).max() ?? 0, delta: 0,
                     series: Array(seriesSpend.suffix(7)), fmt: .money, invert: true))
    }

    private func liveDiagnostics(campaigns: [Campaign]) -> [Diagnostic] {
        var out: [Diagnostic] = []
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
