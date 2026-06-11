import Foundation

// The Analyst: winners/bleeders/fatigue/decay are computed deterministically
// from per-ad insight series (AdPerf signals). The AI writes the daily brief,
// prioritizes recommendations, and drafts copy from winners — it never does
// the math itself.

struct AnalystResult {
    var brief: String
    var recommendations: [InsightRecommendation]
    var generatedAt: Date
}

enum Analyst {
    private static var briefFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MadMac/analyst-brief.json")
    }

    static func loadSavedBrief(accountId: String) -> AnalystBrief? {
        guard let data = try? Data(contentsOf: briefFile),
              let brief = try? JSONDecoder().decode(AnalystBrief.self, from: data),
              brief.accountId == accountId else { return nil }
        return brief
    }

    static func saveBrief(_ text: String, accountId: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let brief = AnalystBrief(date: formatter.string(from: Date()), text: text, accountId: accountId)
        if let data = try? JSONEncoder().encode(brief) {
            try? data.write(to: briefFile)
        }
    }

    static func savedBriefIsToday(accountId: String) -> Bool {
        guard let saved = loadSavedBrief(accountId: accountId) else { return false }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return saved.date == formatter.string(from: Date())
    }

    // ── Daily brief + prioritized recommendations ──────────────────────────

    static func run(perf: [AdPerf], snapshot: AccountSnapshot) async throws -> AnalystResult {
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "brief": ["type": "string"],
                "recommendations": ["type": "array", "items": [
                    "type": "object",
                    "properties": [
                        "title": ["type": "string"],
                        "detail": ["type": "string"],
                        "severity": ["type": "string", "enum": ["info", "warning", "danger"]],
                        "actionType": ["type": "string", "enum": ["none", "pause", "activate", "set_budget"]],
                        "entityId": ["type": "string"],
                        "entityKind": ["type": "string", "enum": ["campaign", "adset", "ad", "none"]],
                        "value": ["type": "number"],
                    ],
                    "required": ["title", "detail", "severity", "actionType", "entityId", "entityKind", "value"],
                    "additionalProperties": false,
                ]],
            ],
            "required": ["brief", "recommendations"],
            "additionalProperties": false,
        ]

        let context = buildContext(perf: perf, snapshot: snapshot)
        let system = """
        You are a Meta ads performance analyst writing a daily brief for a performance \
        marketer. The signals (winner/bleeder/fatigued/dying) were computed from real \
        numbers — trust them, do not recompute. Currency: \(snapshot.account.currency).

        Write `brief` as a tight morning read (max ~120 words): what's running, who's \
        winning, who's bleeding, fatigue/decay warnings, and the single most important \
        action today. Plain language, specific names and numbers.

        Then 2-5 `recommendations`: pause bleeders (actionType=pause on the ad or its \
        campaign), shift budget toward winners (set_budget on the WINNER's campaign or \
        ad set with the new daily value — increase moderately, ~20-50%), refresh fatigued \
        creative (actionType=none, advise in detail). Use only entity IDs present in the \
        data. If there is little or no delivery data, say so honestly in the brief and \
        return fewer or no recommendations.
        """
        let out = try await OpenAIClient().structured(
            system: system, user: context,
            schemaName: "analyst_daily", schema: schema, model: AIPrefs.shared.textModel)

        let recommendations = (out["recommendations"] as? [[String: Any]] ?? []).map {
            InsightRecommendation(
                title: $0["title"] as? String ?? "",
                detail: $0["detail"] as? String ?? "",
                severity: $0["severity"] as? String ?? "info",
                actionType: $0["actionType"] as? String ?? "none",
                entityId: $0["entityId"] as? String ?? "",
                entityKind: $0["entityKind"] as? String ?? "none",
                value: $0["value"] as? Double ?? 0)
        }
        let brief = out["brief"] as? String ?? ""
        saveBrief(brief, accountId: snapshot.account.accountId)
        return AnalystResult(brief: brief, recommendations: recommendations, generatedAt: Date())
    }

    private static func buildContext(perf: [AdPerf], snapshot: AccountSnapshot) -> String {
        var context = "Today's account spend so far: \(Int(snapshot.account.daySpend)) of \(Int(snapshot.account.budget)) budget.\n"
        context += "Active campaigns: \(snapshot.campaigns.filter { $0.status == .active }.count), paused: \(snapshot.campaigns.filter { $0.status == .paused }.count).\n\n"
        if perf.isEmpty {
            context += "No per-ad delivery data yet (no ads running)."
            return context
        }
        context += "Per-ad data, last 7 days vs previous 7 (signals precomputed):\n"
        for p in perf {
            context += "- ad id=\(p.adId) \"\(p.name)\" (campaign id=\(p.campaignId) \"\(p.campaignName)\", adset id=\(p.adsetId), \(p.status.rawValue))"
            context += " spend7=\(Int(p.spend7)) roas7=\(String(format: "%.2f", p.roas7)) roasPrev=\(String(format: "%.2f", p.roasPrev7))"
            context += " cpa7=\(Int(p.cpa7)) cpaPrev=\(Int(p.cpaPrev7)) ctr7=\(String(format: "%.2f", p.ctr7)) ctrPrev=\(String(format: "%.2f", p.ctrPrev7))"
            context += " freq=\(String(format: "%.1f", p.frequency)) ctrSlope=\(String(format: "%.1f", p.ctrSlope))%/day"
            var signals: [String] = []
            if p.isWinner { signals.append("WINNER") }
            if p.isBleeder { signals.append("BLEEDER") }
            if p.isFatigued { signals.append("FATIGUED") }
            if p.isDying { signals.append("DYING (CTR decay before CPA spike)") }
            context += signals.isEmpty ? "\n" : " signals=[\(signals.joined(separator: ","))]\n"
        }
        context += "\nCampaign daily budgets: "
        context += snapshot.campaigns.map { "\($0.id)=\(Int($0.daily))" }.joined(separator: ", ")
        return context
    }

    // ── Copy from winners ──────────────────────────────────────────────────

    static func copyFromWinners(_ winners: [AdPerf], objective: String) async throws -> CopySet {
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "headlines": ["type": "array", "items": ["type": "string"]],
                "texts": ["type": "array", "items": ["type": "string"]],
            ],
            "required": ["headlines", "texts"],
            "additionalProperties": false,
        ]
        let winnerDesc = winners.map {
            "\"\($0.name)\" (ROAS \(String(format: "%.1f", $0.roas7))×, CTR \(String(format: "%.2f", $0.ctr7))%, campaign \"\($0.campaignName)\")"
        }.joined(separator: "; ")
        let system = """
        You are a senior Meta ads copywriter. The ads below are proven winners — infer \
        what makes them work (hook style, angle, language, format hints in their names) \
        and write 5 NEW headlines + 5 NEW primary texts that iterate on those winning \
        angles without copying them verbatim. Same language as the winner names \
        (Indonesian if they're Indonesian). Policy-safe: no unrealistic claims. \
        Headlines max 40 chars.
        """
        let user = "Objective: \(objective)\nWinning ads: \(winnerDesc)"
        let out = try await OpenAIClient().structured(
            system: system, user: user,
            schemaName: "winner_copy", schema: schema, model: AIPrefs.shared.textModel)
        let headlines = (out["headlines"] as? [Any])?.compactMap { $0 as? String } ?? []
        let texts = (out["texts"] as? [Any])?.compactMap { $0 as? String } ?? []
        guard !headlines.isEmpty else { throw AIError.badResponse("no headlines returned") }
        return CopySet(headlines: headlines, texts: texts)
    }
}
