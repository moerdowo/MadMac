import SwiftUI

// Lumio Skincare sample account — a 1:1 port of the prototype's data.jsx so the
// app is fully explorable before a real account is connected.

enum SampleData {
    static let account = AdsAccount(
        brand: "Lumio", name: "Lumio Skincare", accountId: "act_408827145",
        currency: "IDR", region: "Indonesia",
        daySpend: 4_820_000, budget: 6_000_000)

    static let seriesSpend: [Double] = [
        3.1, 2.9, 3.4, 3.8, 3.2, 2.7, 2.9, 3.6, 4.1, 4.4, 3.9, 3.5, 3.0, 3.3,
        4.2, 4.8, 5.1, 4.6, 4.0, 3.7, 4.3, 4.9, 5.4, 5.0, 4.4, 4.1, 4.6, 5.2, 4.8, 4.82
    ].map { ($0 * 1_000_000).rounded() }

    static let seriesRevenue: [Double] = [
        9.2, 8.1, 10.4, 12.1, 9.9, 7.8, 8.6, 11.4, 13.8, 15.1, 12.9, 11.2, 9.4, 10.8,
        14.9, 18.2, 19.8, 16.4, 13.1, 12.0, 15.2, 18.9, 22.4, 19.1, 16.2, 15.0, 17.8, 21.4, 19.9, 21.6
    ].map { ($0 * 1_000_000).rounded() }

    static let seriesRoas: [Double] = zip(seriesRevenue, seriesSpend).map { ($0 / $1 * 100).rounded() / 100 }

    static var kpis: KpiSet {
        let spend = seriesSpend.suffix(7).reduce(0, +)
        let spendPrev = seriesSpend.suffix(14).prefix(7).reduce(0, +)
        let rev = seriesRevenue.suffix(7).reduce(0, +)
        let revPrev = seriesRevenue.suffix(14).prefix(7).reduce(0, +)
        let purch = 412.0, purchPrev = 357.0
        func pct(_ a: Double, _ b: Double) -> Double { ((a - b) / b * 1000).rounded() / 10 }
        return KpiSet(
            spend: Kpi(value: spend, delta: pct(spend, spendPrev), series: Array(seriesSpend.suffix(7)), fmt: .money),
            revenue: Kpi(value: rev, delta: pct(rev, revPrev), series: Array(seriesRevenue.suffix(7)), fmt: .money),
            roas: Kpi(value: (rev / spend * 100).rounded() / 100, delta: pct(rev / spend, revPrev / spendPrev), series: Array(seriesRoas.suffix(7)), fmt: .x),
            purchases: Kpi(value: purch, delta: pct(purch, purchPrev), series: [48, 52, 61, 57, 64, 58, 72], fmt: .int),
            cpa: Kpi(value: (spend / purch).rounded(), delta: pct(spend / purch, spendPrev / purchPrev), series: [12, 11, 10, 11, 9, 10, 9], fmt: .money, invert: true),
            ctr: Kpi(value: 1.92, delta: 13.5, series: [1.7, 1.8, 1.9, 1.85, 2.0, 1.95, 2.1], fmt: .pct),
            reach: Kpi(value: 184_200, delta: 6.2, series: [22, 24, 26, 25, 27, 28, 30], fmt: .int),
            cpm: Kpi(value: 38_800, delta: -3.4, series: [42, 41, 40, 39, 40, 39, 38], fmt: .money, invert: true))
    }

    static let campaigns: [Campaign] = [
        Campaign(id: "23851", name: "Prospecting — Advantage+ Shopping", objective: .sales,
                 status: .active, daily: 2_400_000, spend: 16_800_000, revenue: 78_400_000, roas: 4.67,
                 purchases: 214, cpa: 78_504, ctr: 2.31, learning: .active,
                 adsets: [
                    AdSet(id: "as_1", name: "Broad · 18–45 · ID", status: .active, daily: 1_400_000,
                          spend: 9_800_000, revenue: 47_200_000, roas: 4.82, purchases: 128, cpa: 76_563, ctr: 2.4,
                          learning: .active, audience: "Advantage+ audience", placements: "Advantage+ placements",
                          ads: [
                            Ad(id: "ad_1", name: "UGC — \"Pagi cerah\" 15s", status: .active, spend: 5_200_000, revenue: 26_100_000, roas: 5.02, ctr: 2.6, format: .video, thumb: Color(hex: 0xE91E78)),
                            Ad(id: "ad_2", name: "Carousel — Best sellers", status: .active, spend: 3_100_000, revenue: 13_800_000, roas: 4.45, ctr: 2.2, format: .carousel, thumb: Color(hex: 0x2D3DEC)),
                            Ad(id: "ad_3", name: "Static — Before / after", status: .paused, spend: 1_500_000, revenue: 7_300_000, roas: 4.87, ctr: 2.1, format: .image, thumb: Color(hex: 0x1FB36B)),
                          ]),
                    AdSet(id: "as_2", name: "Lookalike 1% — Purchasers", status: .active, daily: 1_000_000,
                          spend: 7_000_000, revenue: 31_200_000, roas: 4.46, purchases: 86, cpa: 81_395, ctr: 2.18,
                          learning: .learning, audience: "LLA 1% · Purchase 180d", placements: "Manual · Feeds",
                          ads: [
                            Ad(id: "ad_4", name: "UGC — \"Glow check\" 22s", status: .active, spend: 4_400_000, revenue: 20_100_000, roas: 4.57, ctr: 2.3, format: .video, thumb: Color(hex: 0xF4A52A)),
                            Ad(id: "ad_5", name: "Collection — New arrivals", status: .active, spend: 2_600_000, revenue: 11_100_000, roas: 4.27, ctr: 2.0, format: .collection, thumb: Color(hex: 0x2D3DEC)),
                          ]),
                 ]),
        Campaign(id: "23847", name: "Retargeting — Site + IG engagers", objective: .sales,
                 status: .active, daily: 900_000, spend: 6_300_000, revenue: 41_600_000, roas: 6.60,
                 purchases: 142, cpa: 44_366, ctr: 3.12, learning: .active,
                 adsets: [
                    AdSet(id: "as_3", name: "ATC 14d · no purchase", status: .active, daily: 520_000,
                          spend: 3_640_000, revenue: 25_400_000, roas: 6.98, purchases: 88, cpa: 41_364, ctr: 3.4,
                          learning: .active, audience: "AddToCart 14d − Purchase 14d", placements: "Manual · Feeds, Stories",
                          ads: [
                            Ad(id: "ad_6", name: "Dynamic — Catalog retarget", status: .active, spend: 2_400_000, revenue: 17_600_000, roas: 7.33, ctr: 3.6, format: .dynamic, thumb: Color(hex: 0xE91E78)),
                            Ad(id: "ad_7", name: "Testimonial — \"2 minggu\"", status: .active, spend: 1_240_000, revenue: 7_800_000, roas: 6.29, ctr: 3.1, format: .video, thumb: Color(hex: 0x1FB36B)),
                          ]),
                    AdSet(id: "as_4", name: "IG engagers 30d", status: .active, daily: 380_000,
                          spend: 2_660_000, revenue: 16_200_000, roas: 6.09, purchases: 54, cpa: 49_259, ctr: 2.9,
                          learning: .active, audience: "IG engaged 30d", placements: "Manual · Stories, Reels",
                          ads: [
                            Ad(id: "ad_8", name: "Reel — Routine 30s", status: .active, spend: 1_660_000, revenue: 10_600_000, roas: 6.39, ctr: 3.0, format: .video, thumb: Color(hex: 0x2D3DEC)),
                            Ad(id: "ad_9", name: "Promo — Bundle 20%", status: .paused, spend: 1_000_000, revenue: 5_600_000, roas: 5.60, ctr: 2.7, format: .image, thumb: Color(hex: 0xF4A52A)),
                          ]),
                 ]),
        Campaign(id: "23802", name: "Lead gen — Skincare quiz", objective: .leads,
                 status: .paused, daily: 600_000, spend: 4_200_000, revenue: 0, roas: 0,
                 purchases: 0, cpa: 0, ctr: 1.92, learning: .active, leads: 486, cpl: 8_642,
                 adsets: [
                    AdSet(id: "as_5", name: "Quiz — Broad ID 20–40", status: .paused, daily: 600_000,
                          spend: 4_200_000, revenue: 0, roas: 0, purchases: 0, cpa: 0, ctr: 1.92,
                          learning: .active, audience: "Broad · interests: skincare", placements: "Advantage+ placements",
                          leads: 486, cpl: 8_642,
                          ads: [
                            Ad(id: "ad_10", name: "Lead form — \"Tipe kulitmu?\"", status: .paused, spend: 4_200_000, revenue: 0, roas: 0, ctr: 1.9, format: .instantForm, thumb: Color(hex: 0x1FB36B)),
                          ]),
                 ]),
        Campaign(id: "23766", name: "Awareness — Brand video", objective: .awareness,
                 status: .active, daily: 300_000, spend: 2_100_000, revenue: 0, roas: 0,
                 purchases: 0, cpa: 0, ctr: 0.84, learning: .active, reach: 412_000, cpm: 18_200,
                 adsets: [
                    AdSet(id: "as_6", name: "Reach — ID metros", status: .active, daily: 300_000,
                          spend: 2_100_000, revenue: 0, roas: 0, purchases: 0, cpa: 0, ctr: 0.84,
                          learning: .active, audience: "Broad · 18–55 · Jakarta, Bandung, Surabaya", placements: "Advantage+ placements",
                          reach: 412_000,
                          ads: [
                            Ad(id: "ad_11", name: "Brand film — \"Kulit sehat\" 30s", status: .active, spend: 2_100_000, revenue: 0, roas: 0, ctr: 0.84, format: .video, thumb: Color(hex: 0xE91E78)),
                          ]),
                 ]),
    ]

    static let diagnostics: [Diagnostic] = [
        Diagnostic(id: "d1", level: .warning, title: "Ad set in learning phase", target: "Lookalike 1% — Purchasers",
                   detail: "47 of 50 optimization events in the last 7 days. Avoid edits until it exits learning.", icon: "graduationcap"),
        Diagnostic(id: "d2", level: .danger, title: "Creative fatigue detected", target: "UGC — \"Pagi cerah\" 15s",
                   detail: "Frequency 4.8 · first-time impression ratio down 22% over 14 days. Refresh creative.", icon: "flame"),
        Diagnostic(id: "d3", level: .info, title: "Budget pacing under target", target: "Awareness — Brand video",
                   detail: "Spent 71% of daily budget by 6pm on average. Consider raising bid or budget.", icon: "gauge.with.needle"),
        Diagnostic(id: "d4", level: .success, title: "Pixel firing cleanly", target: "Lumio Pixel · 408827145",
                   detail: "Purchase, AddToCart, ViewContent matched at 98.2% over 7 days.", icon: "checkmark.circle"),
    ]

    static let products: [Product] = [
        Product(name: "Lumio Glow Serum 30ml", tint: Color(hex: 0xE91E78), price: 189_000, stock: "In stock", adRoas: 4.6),
        Product(name: "Niacinamide 10% + Zinc", tint: Color(hex: 0x2D3DEC), price: 129_000, stock: "In stock", adRoas: 1.2),
        Product(name: "Gentle Foaming Cleanser", tint: Color(hex: 0x1FB36B), price: 99_000, stock: "Low stock", adRoas: 0.8),
        Product(name: "SPF 50 Daily Sunscreen", tint: Color(hex: 0xF4A52A), price: 149_000, stock: "In stock", adRoas: 2.1),
        Product(name: "Hydrating Toner 200ml", tint: Color(hex: 0x7A5AE0), price: 119_000, stock: "In stock", adRoas: 0.4),
        Product(name: "Retinol Night Cream", tint: Color(hex: 0xE5484D), price: 219_000, stock: "Out of stock", adRoas: 0),
    ]

    static let events: [DatasetEvent] = [
        DatasetEvent(name: "Purchase", count: 8_420, matchRate: 98.2, healthy: true),
        DatasetEvent(name: "AddToCart", count: 24_100, matchRate: 97.1, healthy: true),
        DatasetEvent(name: "ViewContent", count: 186_400, matchRate: 99.4, healthy: true),
        DatasetEvent(name: "InitiateCheckout", count: 11_200, matchRate: 89.6, healthy: false),
        DatasetEvent(name: "Lead", count: 486, matchRate: 94.0, healthy: true),
    ]

    static var breakdowns: BreakdownData {
        BreakdownData(
            placements: [BreakdownSlice(label: "Reels & Stories", value: 14_100_000),
                         BreakdownSlice(label: "Feeds", value: 11_400_000),
                         BreakdownSlice(label: "Advantage+", value: 6_000_000),
                         BreakdownSlice(label: "Audience Network", value: 2_000_000)],
            ages: [BreakdownSlice(label: "18-24", value: 7_400_000),
                   BreakdownSlice(label: "25-34", value: 13_200_000),
                   BreakdownSlice(label: "35-44", value: 8_600_000),
                   BreakdownSlice(label: "45-54", value: 3_300_000),
                   BreakdownSlice(label: "55+", value: 1_000_000)],
            genders: [BreakdownSlice(label: "Female", value: 23_800_000),
                      BreakdownSlice(label: "Male", value: 8_700_000),
                      BreakdownSlice(label: "Unknown", value: 1_000_000)],
            countries: [BreakdownSlice(label: "ID", value: 33_500_000)])
    }

    // Synthesized per-ad series so the Analyst is fully demonstrable in
    // sample mode: clear winners, a bleeder, and a fatiguing hero ad.
    static func adPerf() -> [AdPerf] {
        var out: [AdPerf] = []
        var index = 0
        for campaign in campaigns {
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
                        frequency: ad.id == "ad_1" ? 4.8 : 1.4 + Double(index % 5) * 0.3,
                        dailyCtr: dailyCtr,
                        dailySpend: (0..<14).map { _ in spend7 / 7 }))
                    index += 1
                }
            }
        }
        return out
    }

    static var snapshot: AccountSnapshot {
        AccountSnapshot(account: account, kpis: kpis, campaigns: campaigns,
                        diagnostics: diagnostics,
                        seriesSpend: seriesSpend, seriesRevenue: seriesRevenue, seriesRoas: seriesRoas,
                        products: products, events: events,
                        pixels: [PixelInfo(id: "408827145", name: "Lumio Pixel", lastFired: "2026-06-10T12:00:00+0000")],
                        breakdowns: breakdowns)
    }
}

// Blank state shown before an account is connected (or while live data loads).
enum EmptyData {
    static var snapshot: AccountSnapshot {
        func zero(_ fmt: KpiFormat, invert: Bool = false) -> Kpi {
            Kpi(value: 0, delta: 0, series: [0, 0], fmt: fmt, invert: invert)
        }
        return AccountSnapshot(
            account: AdsAccount(brand: "MadMac", name: "MadMac", accountId: "—",
                                currency: "USD", region: "", daySpend: 0, budget: 0),
            kpis: KpiSet(spend: zero(.money), revenue: zero(.money), roas: zero(.x),
                         purchases: zero(.int), cpa: zero(.money, invert: true), ctr: zero(.pct),
                         reach: zero(.int), cpm: zero(.money, invert: true)),
            campaigns: [], diagnostics: [],
            seriesSpend: [0, 0], seriesRevenue: [0, 0], seriesRoas: [0, 0],
            products: [], events: [])
    }
}
