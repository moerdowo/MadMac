import SwiftUI

// Feature-level AI API. All outputs are drafts/annotations — nothing here can
// write to the ad account.

struct CopySet {
    var headlines: [String]
    var texts: [String]
}

struct PolicyFlag: Identifiable {
    var id: String { text }
    var text: String
    var reason: String
    var suggestion: String
}

struct PolicyReport {
    var risk: String          // none | low | high
    var flags: [PolicyFlag]
}

struct InsightRecommendation: Identifiable {
    let id = UUID()
    var title: String
    var detail: String
    var severity: String      // info | warning | danger
    var actionType: String    // none | pause | activate | set_budget
    var entityId: String
    var entityKind: String    // campaign | adset | ad
    var value: Double         // for set_budget
}

enum AIService {
    private static var client: OpenAIClient { OpenAIClient() }
    private static var model: String { AIPrefs.shared.textModel }

    static var generatedDir: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MadMac/generated", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // Drop generated images older than 30 days.
    static func cleanupGenerated() {
        let cutoff = Date().addingTimeInterval(-30 * 86400)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: generatedDir, includingPropertiesForKeys: [.creationDateKey])) ?? []
        for file in files {
            let created = (try? file.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
            if created < cutoff { try? FileManager.default.removeItem(at: file) }
        }
    }

    private static func saveImage(_ data: Data, prefix: String) throws -> URL {
        let url = generatedDir.appendingPathComponent("\(prefix)-\(UUID().uuidString.prefix(8)).png")
        try data.write(to: url)
        return url
    }

    private static func strings(_ value: Any?) -> [String] {
        (value as? [Any])?.compactMap { $0 as? String } ?? []
    }

    // ── 1a. Copywriter ─────────────────────────────────────────────────────

    static func generateCopy(product: String, tone: String, language: String,
                             objective: String) async throws -> CopySet {
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "headlines": ["type": "array", "items": ["type": "string"]],
                "texts": ["type": "array", "items": ["type": "string"]],
            ],
            "required": ["headlines", "texts"],
            "additionalProperties": false,
        ]
        let system = """
        You are a senior Meta ads copywriter. Write scroll-stopping, policy-safe ad copy. \
        Headlines: max 40 characters, punchy. Primary texts: 1-3 sentences, hook first, \
        no ALL CAPS, no exaggerated claims (no "guaranteed", no unrealistic timeframes), \
        emoji ok sparingly. Return exactly 5 headlines and 5 primary texts.
        """
        let user = """
        Product/offer: \(product)
        Campaign objective: \(objective)
        Tone: \(tone)
        Language: \(language)
        """
        let out = try await client.structured(system: system, user: user,
                                              schemaName: "ad_copy", schema: schema, model: model)
        let set = CopySet(headlines: strings(out["headlines"]), texts: strings(out["texts"]))
        guard !set.headlines.isEmpty else { throw AIError.badResponse("no headlines returned") }
        return set
    }

    // ── 1b/1c. Images ──────────────────────────────────────────────────────

    static func generateImages(prompt: String, size: String, count: Int) async throws -> [URL] {
        let payloads = try await client.generateImages(
            prompt: prompt, size: size, count: count,
            quality: AIPrefs.shared.imageQuality.apiValue)
        return try payloads.map { try saveImage($0, prefix: "gen") }
    }

    static func editImage(_ url: URL, instruction: String) async throws -> URL {
        let payload = try await client.editImage(url, prompt: instruction,
                                                 quality: AIPrefs.shared.imageQuality.apiValue)
        return try saveImage(payload, prefix: "edit")
    }

    // ── 2a. Brief → draft ──────────────────────────────────────────────────

    static func parseBrief(_ brief: String, currency: String,
                           pixels: [PixelInfo], pages: [PageInfo]) async throws -> DraftCampaign {
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "name": ["type": "string"],
                "objective": ["type": "string", "enum": ["Sales", "Leads", "Traffic", "Awareness"]],
                "daily": ["type": "number"],
                "bidAmount": ["type": "number"],
                "countries": ["type": "string"],
                "optimization": ["type": "string",
                                 "enum": OptimizationGoal.allCases.map(\.rawValue)],
                "conversionEvent": ["type": "string",
                                    "enum": ConversionEvent.allCases.map(\.rawValue)],
                "pixelId": ["type": "string"],
                "adName": ["type": "string"],
                "headline": ["type": "string"],
                "text": ["type": "string"],
                "linkURL": ["type": "string"],
                "cta": ["type": "string", "enum": CTAType.allCases.map(\.rawValue)],
            ],
            "required": ["name", "objective", "daily", "bidAmount", "countries", "optimization",
                         "conversionEvent", "pixelId", "adName", "headline", "text", "linkURL", "cta"],
            "additionalProperties": false,
        ]
        let pixelList = pixels.map { "\($0.id) (\($0.name))" }.joined(separator: ", ")
        let system = """
        You turn a marketer's brief into a Meta campaign draft. Currency: \(currency) \
        (amounts as plain numbers in that currency, no minor units). If the brief doesn't \
        give a bid cap, use roughly 15% of the daily budget. Countries as ISO codes. \
        Available pixels: \(pixelList.isEmpty ? "none — use empty string" : pixelList). \
        If the brief implies conversion tracking and a pixel exists, pick the most relevant one; \
        otherwise pixelId is an empty string. Write the headline and primary text in the \
        brief's language. Keep claims policy-safe.
        """
        let out = try await client.structured(system: system, user: brief,
                                              schemaName: "campaign_draft", schema: schema, model: model)
        var d = DraftCampaign()
        d.name = out["name"] as? String ?? d.name
        d.objective = Objective(rawValue: out["objective"] as? String ?? "") ?? .sales
        d.daily = out["daily"] as? Double ?? d.daily
        d.bidAmount = out["bidAmount"] as? Double ?? d.bidAmount
        d.countries = out["countries"] as? String ?? d.countries
        d.optimization = OptimizationGoal(rawValue: out["optimization"] as? String ?? "")
            ?? .suggested(for: d.objective)
        d.conversionEvent = ConversionEvent(rawValue: out["conversionEvent"] as? String ?? "") ?? .purchase
        d.pixelId = out["pixelId"] as? String ?? ""
        d.adName = out["adName"] as? String ?? d.adName
        d.headline = out["headline"] as? String ?? ""
        d.text = out["text"] as? String ?? ""
        d.linkURL = out["linkURL"] as? String ?? ""
        d.cta = CTAType(rawValue: out["cta"] as? String ?? "") ?? .learnMore
        if d.pageId.isEmpty, let page = pages.first { d.pageId = page.id }
        return d
    }

    // ── 2b. Policy pre-check ───────────────────────────────────────────────

    static func policyCheck(headline: String, text: String, objective: String) async throws -> PolicyReport {
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "risk": ["type": "string", "enum": ["none", "low", "high"]],
                "flags": ["type": "array", "items": [
                    "type": "object",
                    "properties": [
                        "text": ["type": "string"],
                        "reason": ["type": "string"],
                        "suggestion": ["type": "string"],
                    ],
                    "required": ["text", "reason", "suggestion"],
                    "additionalProperties": false,
                ]],
            ],
            "required": ["risk", "flags"],
            "additionalProperties": false,
        ]
        let system = """
        You review Meta ad copy for policy-rejection risk. Check for: personal attributes \
        ("do you have acne?"), unrealistic results or timeframes, before/after implications, \
        medical claims, prohibited phrasing, excessive capitalization. Indonesian and English \
        copy both. risk=none with empty flags when clean. Quote the risky fragment in `text`, \
        explain in `reason`, offer a compliant rewrite in `suggestion`. Be precise, not paranoid.
        """
        let user = "Objective: \(objective)\nHeadline: \(headline)\nPrimary text: \(text)"
        let out = try await client.structured(system: system, user: user,
                                              schemaName: "policy_report", schema: schema, model: model)
        let flags = (out["flags"] as? [[String: Any]] ?? []).map {
            PolicyFlag(text: $0["text"] as? String ?? "",
                       reason: $0["reason"] as? String ?? "",
                       suggestion: $0["suggestion"] as? String ?? "")
        }
        return PolicyReport(risk: out["risk"] as? String ?? "none", flags: flags)
    }

    // ── 3a. Account analysis ───────────────────────────────────────────────

    static func analyze(_ snapshot: AccountSnapshot) async throws -> [InsightRecommendation] {
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "insights": ["type": "array", "items": [
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
            "required": ["insights"],
            "additionalProperties": false,
        ]
        // Compact, numbers-only context — no tokens, no PII.
        var context = "Account currency: \(snapshot.account.currency)\n"
        context += "Daily spend series (oldest→newest): \(snapshot.seriesSpend.map { Int($0) })\n"
        context += "Daily revenue series: \(snapshot.seriesRevenue.map { Int($0) })\n"
        context += "Campaigns:\n"
        for c in snapshot.campaigns {
            context += "- id=\(c.id) name=\(c.name) status=\(c.status.rawValue) objective=\(c.objective.rawValue) "
            context += "daily=\(Int(c.daily)) spend30d=\(Int(c.spend)) revenue30d=\(Int(c.revenue)) "
            context += "roas=\(String(format: "%.2f", c.roas)) purchases=\(c.purchases) ctr=\(c.ctr)\n"
        }
        if !snapshot.breakdowns.placements.isEmpty {
            context += "Spend by placement: \(snapshot.breakdowns.placements.map { "\($0.label)=\(Int($0.value))" }.joined(separator: ", "))\n"
        }
        let system = """
        You are a Meta ads performance analyst. Given account data, produce 3-5 concise, \
        specific insights a performance marketer can act on. Where an action is clear, \
        attach it: pause/activate an entity, or set_budget with `value` as the new daily \
        budget in account currency. Use entityId/entityKind from the data; use actionType \
        "none" with entityKind "none" and empty entityId for observations. Never invent IDs. \
        Be honest when there is too little data — say so in an insight.
        """
        let out = try await client.structured(system: system, user: context,
                                              schemaName: "account_insights", schema: schema, model: model)
        return (out["insights"] as? [[String: Any]] ?? []).map {
            InsightRecommendation(
                title: $0["title"] as? String ?? "",
                detail: $0["detail"] as? String ?? "",
                severity: $0["severity"] as? String ?? "info",
                actionType: $0["actionType"] as? String ?? "none",
                entityId: $0["entityId"] as? String ?? "",
                entityKind: $0["entityKind"] as? String ?? "none",
                value: $0["value"] as? Double ?? 0)
        }
    }
}
