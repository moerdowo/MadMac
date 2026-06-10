import SwiftUI

// ── Entity status ──────────────────────────────────────────────────────────

enum EntityStatus: String, Codable {
    case active, paused

    var toggledOn: Bool { self == .active }
}

enum LearningPhase: String, Codable {
    case active, learning
}

enum Objective: String, CaseIterable, Codable, Identifiable {
    case sales = "Sales", leads = "Leads", traffic = "Traffic", awareness = "Awareness"
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .sales: return "cart"
        case .leads: return "person.badge.plus"
        case .traffic: return "cursorarrow.click"
        case .awareness: return "megaphone"
        }
    }
    var blurb: String {
        switch self {
        case .sales: return "Find people likely to purchase"
        case .leads: return "Collect leads with an instant form"
        case .traffic: return "Send people to your site"
        case .awareness: return "Reach the most people"
        }
    }
    // Marketing API ODAX objective for CLI writes
    var apiValue: String {
        switch self {
        case .sales: return "OUTCOME_SALES"
        case .leads: return "OUTCOME_LEADS"
        case .traffic: return "OUTCOME_TRAFFIC"
        case .awareness: return "OUTCOME_AWARENESS"
        }
    }
}

enum AdFormat: String, CaseIterable, Codable, Identifiable {
    case video = "Video", image = "Image", carousel = "Carousel",
         collection = "Collection", dynamic = "Dynamic", instantForm = "Instant form"
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .video, .dynamic: return "play.fill"
        case .carousel: return "photo.on.rectangle"
        case .instantForm: return "list.clipboard"
        default: return "photo"
        }
    }
}

// ── Campaign hierarchy ─────────────────────────────────────────────────────

struct Ad: Identifiable {
    let id: String
    var name: String
    var status: EntityStatus
    var spend: Double
    var revenue: Double
    var roas: Double
    var ctr: Double
    var format: AdFormat
    var thumb: Color
}

struct AdSet: Identifiable {
    let id: String
    var name: String
    var status: EntityStatus
    var daily: Double
    var spend: Double
    var revenue: Double
    var roas: Double
    var purchases: Int
    var cpa: Double
    var ctr: Double
    var learning: LearningPhase
    var audience: String
    var placements: String
    var leads: Int?
    var cpl: Double?
    var reach: Int?
    var ads: [Ad]
}

struct Campaign: Identifiable {
    let id: String
    var name: String
    var objective: Objective
    var status: EntityStatus
    var daily: Double
    var spend: Double
    var revenue: Double
    var roas: Double
    var purchases: Int
    var cpa: Double
    var ctr: Double
    var learning: LearningPhase
    var leads: Int?
    var cpl: Double?
    var reach: Int?
    var cpm: Double?
    var adsets: [AdSet]
}

// ── Account / KPIs ─────────────────────────────────────────────────────────

struct AdsAccount {
    var brand: String
    var name: String
    var accountId: String
    var currency: String     // "IDR", "USD"…
    var region: String
    var daySpend: Double
    var budget: Double
}

enum KpiFormat { case money, x, pct, int }

struct Kpi {
    var value: Double
    var delta: Double
    var series: [Double]
    var fmt: KpiFormat
    var invert: Bool = false   // lower is better (CPA, CPM)
}

struct KpiSet {
    var spend: Kpi
    var revenue: Kpi
    var roas: Kpi
    var purchases: Kpi
    var cpa: Kpi
    var ctr: Kpi
    var reach: Kpi
    var cpm: Kpi

    subscript(key: String) -> Kpi {
        switch key {
        case "spend": return spend
        case "revenue": return revenue
        case "roas": return roas
        case "purchases": return purchases
        case "cpa": return cpa
        case "ctr": return ctr
        case "reach": return reach
        default: return cpm
        }
    }
}

// ── Diagnostics / catalog / datasets ───────────────────────────────────────

enum DiagLevel { case warning, danger, info, success }

struct Diagnostic: Identifiable {
    let id: String
    var level: DiagLevel
    var title: String
    var target: String
    var detail: String
    var icon: String
}

struct Product: Identifiable {
    var id: String { name }
    var name: String
    var tint: Color
    var price: Double
    var stock: String      // "In stock" | "Low stock" | "Out of stock"
    var adRoas: Double
}

struct DatasetEvent: Identifiable {
    var id: String { name }
    var name: String
    var count: Int
    var matchRate: Double
    var healthy: Bool
}

// ── Staged changes / draft (the review flow) ───────────────────────────────

enum EntityKind: String { case campaign = "Campaign", adset = "Ad set", ad = "Ad" }

struct StagedChange: Identifiable {
    var id: String { entityId }
    let entityId: String
    let kind: EntityKind
    let name: String
    let base: EntityStatus
    let to: EntityStatus
}

struct DraftCampaign {
    var name: String = "Prospecting — New"
    var objective: Objective = .sales
    var daily: Double = 1_500_000
    var audience: String = "Advantage+ audience"
    var geo: String = "Indonesia"
    var age: String = "18–45"
    var adName: String = "UGC — Hook 15s"
    var format: AdFormat = .video
    var text: String = "Kulit lebih cerah dalam 2 minggu ✨ Coba Lumio hari ini."

    var adsetName: String {
        "\(audience.components(separatedBy: " —").first ?? audience) · \(age) · \(geo)"
    }
}

// Snapshot a backend hands the app.
struct AccountSnapshot {
    var account: AdsAccount
    var kpis: KpiSet
    var campaigns: [Campaign]
    var diagnostics: [Diagnostic]
    var seriesSpend: [Double]
    var seriesRevenue: [Double]
    var seriesRoas: [Double]
    var products: [Product]
    var events: [DatasetEvent]
}
