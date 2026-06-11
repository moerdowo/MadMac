import SwiftUI

// ── Entity status ──────────────────────────────────────────────────────────

enum EntityStatus: String, Codable {
    case active, paused, archived

    var toggledOn: Bool { self == .active }
}

enum OptimizationGoal: String, CaseIterable, Identifiable {
    case offsiteConversions = "offsite_conversions"
    case linkClicks = "link_clicks"
    case landingPageViews = "landing_page_views"
    case leadGeneration = "lead_generation"
    case reach = "reach"
    case thruplay = "thruplay"
    var id: String { rawValue }

    var label: String {
        switch self {
        case .offsiteConversions: return "Conversions"
        case .linkClicks: return "Link clicks"
        case .landingPageViews: return "Landing page views"
        case .leadGeneration: return "Leads"
        case .reach: return "Reach"
        case .thruplay: return "ThruPlay"
        }
    }
    // billing event accepted with this goal (impressions is valid for all of these)
    var billingEvent: String { "impressions" }

    static func suggested(for objective: Objective) -> OptimizationGoal {
        switch objective {
        case .sales: return .offsiteConversions
        case .leads: return .leadGeneration
        case .traffic: return .linkClicks
        case .awareness: return .reach
        }
    }
}

enum CTAType: String, CaseIterable, Identifiable {
    case shopNow = "shop_now", learnMore = "learn_more", signUp = "sign_up",
         buyNow = "buy_now", contactUs = "contact_us", subscribe = "subscribe",
         getOffer = "get_offer", download = "download"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .shopNow: return "Shop now"
        case .learnMore: return "Learn more"
        case .signUp: return "Sign up"
        case .buyNow: return "Buy now"
        case .contactUs: return "Contact us"
        case .subscribe: return "Subscribe"
        case .getOffer: return "Get offer"
        case .download: return "Download"
        }
    }
}

enum ConversionEvent: String, CaseIterable, Identifiable {
    case purchase, addToCart = "add_to_cart", lead,
         completeRegistration = "complete_registration",
         initiatedCheckout = "initiated_checkout", subscribe
    var id: String { rawValue }
    var label: String {
        switch self {
        case .purchase: return "Purchase"
        case .addToCart: return "Add to cart"
        case .lead: return "Lead"
        case .completeRegistration: return "Registration"
        case .initiatedCheckout: return "Checkout"
        case .subscribe: return "Subscribe"
        }
    }
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
    // ads-cli objective choice (lowercase, verified against meta-ads 1.0.1)
    var apiValue: String {
        switch self {
        case .sales: return "outcome_sales"
        case .leads: return "outcome_leads"
        case .traffic: return "outcome_traffic"
        case .awareness: return "outcome_awareness"
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
    var thumbURL: URL?        // creative thumbnail (small)
    var imageURL: URL?        // full-size creative image, when available
    var previewURL: URL?      // Meta's shareable ad preview link
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

struct StagedBudget: Identifiable {
    var id: String { entityId }
    let entityId: String
    let kind: EntityKind
    let name: String
    let from: Double
    let to: Double
}

struct StagedDelete: Identifiable {
    var id: String { entityId }
    let entityId: String
    let kind: EntityKind
    let name: String
}

struct DraftCampaign {
    var name: String = "Prospecting — New"
    var objective: Objective = .sales
    var daily: Double = 150_000

    // ad set
    var countries: String = "ID"                 // ISO codes, comma-separated
    var optimization: OptimizationGoal = .offsiteConversions
    var bidAmount: Double = 20_000               // bid cap per result (Meta requires one via this API)
    var pixelId: String = ""                     // empty = no conversion tracking
    var conversionEvent: ConversionEvent = .purchase
    var schedule: Bool = false
    var startDate: Date = Date()
    var endDate: Date = Date().addingTimeInterval(14 * 86400)

    // creative
    var adName: String = "Launch — Hook 15s"
    var media: [URL] = []                        // local image/video files
    var headline: String = ""
    var text: String = ""
    var extraHeadlines: String = ""              // one per line → DCO
    var extraTexts: String = ""
    var linkURL: String = ""
    var cta: CTAType = .learnMore
    var pageId: String = ""

    var headlines: [String] {
        ([headline] + extraHeadlines.components(separatedBy: .newlines))
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    var texts: [String] {
        ([text] + extraTexts.components(separatedBy: .newlines))
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    var isDCO: Bool { media.count > 1 || headlines.count > 1 || texts.count > 1 }
    var format: AdFormat {
        let videoExts = ["mp4", "mov", "avi", "mkv", "wmv"]
        if media.contains(where: { videoExts.contains($0.pathExtension.lowercased()) }) { return .video }
        return media.count > 1 ? .carousel : .image
    }
    var hasCreative: Bool { !media.isEmpty && !pageId.isEmpty }

    var adsetName: String {
        "\(optimization.label) · \(countries)"
    }
}

// Everything one Approve can carry.
struct ChangePlan {
    var statusChanges: [StagedChange] = []
    var budgetChanges: [StagedBudget] = []
    var deletes: [StagedDelete] = []
    var draft: DraftCampaign?
    var launchLive: Bool = false

    var count: Int { statusChanges.count + budgetChanges.count + deletes.count + (draft != nil ? 1 : 0) }
}

struct ApplyReport {
    var createdCampaignId: String?
    var warnings: [String] = []
}

// ── Reference data (pickers, switcher) ─────────────────────────────────────

struct PageInfo: Identifiable {
    let id: String
    var name: String
    var category: String
}

struct PixelInfo: Identifiable {
    let id: String
    var name: String
    var lastFired: String   // ISO timestamp or ""
}

struct AccountInfo: Identifiable {
    let id: String          // act_…
    var name: String
    var currency: String
}

// Spend breakdowns for the dashboard.
struct BreakdownSlice: Identifiable {
    var id: String { label }
    var label: String
    var value: Double       // spend
}

struct BreakdownData {
    var placements: [BreakdownSlice] = []
    var ages: [BreakdownSlice] = []
    var genders: [BreakdownSlice] = []
    var countries: [BreakdownSlice] = []
    var isEmpty: Bool { placements.isEmpty && ages.isEmpty && genders.isEmpty && countries.isEmpty }
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
    var pixels: [PixelInfo] = []
    var breakdowns: BreakdownData = BreakdownData()
}
