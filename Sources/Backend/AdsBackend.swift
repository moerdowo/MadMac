import Foundation

protocol AdsBackend {
    var isLive: Bool { get }
    func loadSnapshot() async throws -> AccountSnapshot
    func apply(_ plan: ChangePlan) async throws -> ApplyReport
    func pages() async throws -> [PageInfo]
    func accounts() async throws -> [AccountInfo]
    /// Per-ad 14-day performance for the Analyst (capped for rate limits).
    func adPerformance() async throws -> [AdPerf]
}

// Sample mode: AppState mutates its local copy after a (always-successful) apply.
struct SampleBackend: AdsBackend {
    var isLive: Bool { false }

    func loadSnapshot() async throws -> AccountSnapshot { SampleData.snapshot }

    func apply(_ plan: ChangePlan) async throws -> ApplyReport {
        try await Task.sleep(for: .milliseconds(600))   // feel the launch
        return ApplyReport()
    }

    func pages() async throws -> [PageInfo] {
        [PageInfo(id: "108880123456", name: "Lumio Skincare", category: "Beauty brand")]
    }

    func accounts() async throws -> [AccountInfo] {
        [AccountInfo(id: SampleData.account.accountId, name: SampleData.account.name, currency: "IDR")]
    }

    // Synthesized per-ad series so the Analyst is fully demonstrable in
    // sample mode: a clear winner, a bleeder, and a fatiguing ad.
    func adPerformance() async throws -> [AdPerf] {
        var out: [AdPerf] = []
        for campaign in SampleData.campaigns {
            for adset in campaign.adsets {
                for ad in adset.ads {
                    let roas7 = ad.roas
                    let fatigueFactor: Double = ad.id == "ad_1" ? 0.55 : 1.0   // hero ad is fatiguing
                    let bleed = campaign.objective == .leads                    // quiz campaign bleeds
                    let baseCtr = ad.ctr
                    let dailyCtr = (0..<14).map { day -> Double in
                        let drift = fatigueFactor < 1 ? 1.0 - Double(day) * 0.035 : 1.0 + sin(Double(day)) * 0.04
                        return max(baseCtr * drift, 0.2)
                    }
                    let spend7 = ad.spend * 0.25
                    out.append(AdPerf(
                        adId: ad.id, name: ad.name,
                        campaignId: campaign.id, campaignName: campaign.name,
                        adsetId: adset.id, status: ad.status,
                        spend7: spend7, spendPrev7: ad.spend * 0.22,
                        roas7: bleed ? 0.8 : roas7 * fatigueFactor,
                        roasPrev7: bleed ? 1.1 : roas7,
                        cpa7: bleed ? 95_000 : (roas7 > 0 ? spend7 / max(Double(adset.purchases) * 0.25, 1) : 0),
                        cpaPrev7: bleed ? 70_000 : (roas7 > 0 ? spend7 / max(Double(adset.purchases) * 0.27, 1) : 0),
                        ctr7: dailyCtr.suffix(7).reduce(0, +) / 7,
                        ctrPrev7: dailyCtr.prefix(7).reduce(0, +) / 7,
                        frequency: ad.id == "ad_1" ? 4.8 : Double.random(in: 1.4...2.6),
                        dailyCtr: dailyCtr,
                        dailySpend: (0..<14).map { _ in spend7 / 7 }))
                }
            }
        }
        return out
    }
}
