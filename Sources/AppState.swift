import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case performance = "Performance"
    case campaigns = "Campaigns"
    case catalog = "Catalog"
    case diagnostics = "Diagnostics"
    case datasets = "Datasets"
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .performance: return "chart.bar.xaxis"
        case .campaigns: return "square.grid.2x2"
        case .catalog: return "shippingbox"
        case .diagnostics: return "stethoscope"
        case .datasets: return "cylinder.split.1x2"
        }
    }
}

enum BackendMode: String { case disconnected, sample, live }

@MainActor
final class AppState: ObservableObject {
    @Published var snapshot: AccountSnapshot
    @Published var campaigns: [Campaign]
    @Published var section: AppSection = .performance

    // staged-changes engine
    @Published var pending: [String: EntityStatus] = [:]
    @Published var draft: DraftCampaign?

    // overlays
    @Published var drawerCampaignID: String?
    @Published var createOpen = false
    @Published var reviewOpen = false
    @Published var connectOpen = false

    // backend
    @Published var mode: BackendMode = .disconnected
    @Published var isLoading = false
    @Published var isApplying = false
    @Published var banner: Banner?
    var backend: AdsBackend

    struct Banner: Identifiable {
        let id = UUID()
        var text: String
        var isError: Bool
    }

    // Start blank: live data if an account is connected, otherwise the connect
    // prompt. Sample data only appears when explicitly chosen.
    init() {
        let snap = EmptyData.snapshot
        snapshot = snap
        campaigns = []
        backend = SampleBackend()
        Fmt.currency = snap.account.currency
        if Credentials.load() != nil {
            switchToLive()
        } else {
            connectOpen = true
        }
    }

    var pendingCount: Int { pendingChanges().count + (draft != nil ? 1 : 0) }

    func effectiveStatus(_ id: String, base: EntityStatus) -> EntityStatus {
        pending[id] ?? base
    }

    func toggle(entityId: String, kind: EntityKind, name: String, base: EntityStatus, to: EntityStatus) {
        if to == base { pending.removeValue(forKey: entityId) }
        else { pending[entityId] = to }
    }

    func pendingChanges() -> [StagedChange] {
        var lookup: [String: (EntityKind, String, EntityStatus)] = [:]
        for c in campaigns {
            lookup[c.id] = (.campaign, c.name, c.status)
            for a in c.adsets {
                lookup[a.id] = (.adset, a.name, a.status)
                for ad in a.ads { lookup[ad.id] = (.ad, ad.name, ad.status) }
            }
        }
        return pending.compactMap { id, to in
            guard let (kind, name, base) = lookup[id], base != to else { return nil }
            return StagedChange(entityId: id, kind: kind, name: name, base: base, to: to)
        }.sorted { $0.name < $1.name }
    }

    func discard() {
        pending = [:]
        draft = nil
    }

    // ── Approve & launch ───────────────────────────────────────────────────
    func approve(launchLive: Bool) async {
        let changes = pendingChanges()
        isApplying = true
        defer { isApplying = false }
        do {
            try await backend.apply(changes: changes, draft: draft, launchLive: launchLive)
            applyLocally(changes: changes, launchLive: launchLive)
            let n = changes.count + (draft != nil ? 1 : 0)
            banner = Banner(text: mode == .live
                ? "\(n) change\(n == 1 ? "" : "s") applied to \(snapshot.account.accountId)"
                : "\(n) change\(n == 1 ? "" : "s") applied (sample mode)", isError: false)
            pending = [:]
            draft = nil
            reviewOpen = false
            section = .campaigns
            if mode == .live { await reload() }
        } catch {
            banner = Banner(text: "Apply failed: \(error.localizedDescription)", isError: true)
        }
    }

    private func applyLocally(changes: [StagedChange], launchLive: Bool) {
        campaigns = campaigns.map { c in
            var c = c
            c.status = pending[c.id] ?? c.status
            c.adsets = c.adsets.map { a in
                var a = a
                a.status = pending[a.id] ?? a.status
                a.ads = a.ads.map { ad in
                    var ad = ad
                    ad.status = pending[ad.id] ?? ad.status
                    return ad
                }
                return a
            }
            return c
        }
        if let d = draft {
            let status: EntityStatus = launchLive ? .active : .paused
            let new = Campaign(
                id: String(Int.random(in: 23900...23990)), name: d.name, objective: d.objective,
                status: status, daily: d.daily, spend: 0, revenue: 0, roas: 0,
                purchases: 0, cpa: 0, ctr: 0, learning: .active,
                adsets: [AdSet(id: "as_\(UUID().uuidString.prefix(6))", name: d.adsetName, status: status,
                               daily: d.daily, spend: 0, revenue: 0, roas: 0, purchases: 0, cpa: 0, ctr: 0,
                               learning: .learning, audience: d.audience, placements: "Advantage+ placements",
                               ads: [Ad(id: "ad_\(UUID().uuidString.prefix(6))", name: d.adName, status: status,
                                        spend: 0, revenue: 0, roas: 0, ctr: 0, format: d.format,
                                        thumb: Color(hex: 0xE91E78))])])
            campaigns.insert(new, at: 0)
        }
    }

    // ── Backend switching ──────────────────────────────────────────────────
    func switchToLive() {
        guard let creds = Credentials.load() else {
            connectOpen = true
            return
        }
        backend = CLIBackend(credentials: creds)
        mode = .live
        Task { await reload() }
    }

    func switchToSample() {
        backend = SampleBackend()
        mode = .sample
        let snap = SampleData.snapshot
        snapshot = snap
        campaigns = snap.campaigns
        Fmt.currency = snap.account.currency
        pending = [:]
        draft = nil
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let snap = try await backend.loadSnapshot()
            snapshot = snap
            campaigns = snap.campaigns
            Fmt.currency = snap.account.currency
        } catch {
            banner = Banner(text: "Couldn't load account: \(error.localizedDescription)", isError: true)
        }
    }
}
