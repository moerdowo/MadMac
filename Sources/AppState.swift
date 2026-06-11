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
    @Published var pending: [String: EntityStatus] = [:]        // status / archive
    @Published var pendingBudgets: [String: Double] = [:]       // entityId → new daily
    @Published var pendingDeletes: Set<String> = []
    @Published var draft: DraftCampaign?

    // overlays
    @Published var drawerCampaignID: String?
    @Published var createOpen = false
    @Published var createPrefill: DraftCampaign?
    @Published var reviewOpen = false
    @Published var connectOpen = false

    // backend
    @Published var mode: BackendMode = .disconnected
    @Published var isLoading = false
    @Published var isApplying = false
    @Published var banner: Banner?
    @Published var accounts: [AccountInfo] = []
    var backend: AdsBackend

    struct Banner: Identifiable {
        let id = UUID()
        var text: String
        var isError: Bool
    }

    // Start blank: live data if an account is connected, otherwise the
    // onboarding screen. Sample data only when explicitly chosen.
    init() {
        let snap = EmptyData.snapshot
        snapshot = snap
        campaigns = []
        backend = SampleBackend()
        Fmt.currency = snap.account.currency
        if Credentials.load() != nil {
            switchToLive()
        }
    }

    // ── Staging ────────────────────────────────────────────────────────────

    var pendingCount: Int { buildPlan(launchLive: false).count }

    func effectiveStatus(_ id: String, base: EntityStatus) -> EntityStatus {
        pending[id] ?? base
    }

    func toggle(entityId: String, kind: EntityKind, name: String, base: EntityStatus, to: EntityStatus) {
        if to == base { pending.removeValue(forKey: entityId) }
        else { pending[entityId] = to }
    }

    func stageBudget(entityId: String, current: Double, to: Double?) {
        if let to, to > 0, to != current { pendingBudgets[entityId] = to }
        else { pendingBudgets.removeValue(forKey: entityId) }
    }

    func stageDelete(entityId: String) {
        if pendingDeletes.contains(entityId) { pendingDeletes.remove(entityId) }
        else { pendingDeletes.insert(entityId) }
    }

    func discard() {
        pending = [:]
        pendingBudgets = [:]
        pendingDeletes = []
        draft = nil
    }

    // Name/kind/base lookup across the tree.
    private func entityIndex() -> [String: (EntityKind, String, EntityStatus, Double)] {
        var index: [String: (EntityKind, String, EntityStatus, Double)] = [:]
        for c in campaigns {
            index[c.id] = (.campaign, c.name, c.status, c.daily)
            for a in c.adsets {
                index[a.id] = (.adset, a.name, a.status, a.daily)
                for ad in a.ads { index[ad.id] = (.ad, ad.name, ad.status, 0) }
            }
        }
        return index
    }

    func buildPlan(launchLive: Bool) -> ChangePlan {
        let index = entityIndex()
        var plan = ChangePlan(draft: draft, launchLive: launchLive)
        plan.statusChanges = pending.compactMap { id, to in
            guard let (kind, name, base, _) = index[id], base != to,
                  !pendingDeletes.contains(id) else { return nil }
            return StagedChange(entityId: id, kind: kind, name: name, base: base, to: to)
        }.sorted { $0.name < $1.name }
        plan.budgetChanges = pendingBudgets.compactMap { id, to in
            guard let (kind, name, _, from) = index[id], from != to,
                  !pendingDeletes.contains(id) else { return nil }
            return StagedBudget(entityId: id, kind: kind, name: name, from: from, to: to)
        }.sorted { $0.name < $1.name }
        plan.deletes = pendingDeletes.compactMap { id in
            guard let (kind, name, _, _) = index[id] else { return nil }
            return StagedDelete(entityId: id, kind: kind, name: name)
        }.sorted { $0.name < $1.name }
        return plan
    }

    // ── Approve & launch ───────────────────────────────────────────────────

    func approve(launchLive: Bool) async {
        let plan = buildPlan(launchLive: launchLive)
        isApplying = true
        defer { isApplying = false }
        do {
            let report = try await backend.apply(plan)
            applyLocally(plan: plan, createdId: report.createdCampaignId)
            var text = "\(plan.count) change\(plan.count == 1 ? "" : "s") applied"
            if mode == .live { text += " to \(snapshot.account.accountId)" }
            banner = Banner(text: report.warnings.isEmpty ? text
                            : text + " · " + report.warnings.joined(separator: " · "),
                            isError: false)
            discard()
            reviewOpen = false
            section = .campaigns
            if mode == .live { await reload() }
        } catch {
            banner = Banner(text: "Apply failed: \(error.localizedDescription)", isError: true)
        }
    }

    private func applyLocally(plan: ChangePlan, createdId: String?) {
        campaigns = campaigns.compactMap { c in
            if pendingDeletes.contains(c.id) { return nil }
            var c = c
            c.status = pending[c.id] ?? c.status
            c.daily = pendingBudgets[c.id] ?? c.daily
            c.adsets = c.adsets.compactMap { a in
                if pendingDeletes.contains(a.id) { return nil }
                var a = a
                a.status = pending[a.id] ?? a.status
                a.daily = pendingBudgets[a.id] ?? a.daily
                a.ads = a.ads.compactMap { ad in
                    if pendingDeletes.contains(ad.id) { return nil }
                    var ad = ad
                    ad.status = pending[ad.id] ?? ad.status
                    return ad
                }
                return a
            }
            return c
        }.filter { $0.status != .archived }

        if let d = plan.draft {
            let status: EntityStatus = plan.launchLive ? .active : .paused
            let new = Campaign(
                id: createdId ?? "new_\(UUID().uuidString.prefix(6))",
                name: d.name, objective: d.objective,
                status: status, daily: d.daily, spend: 0, revenue: 0, roas: 0,
                purchases: 0, cpa: 0, ctr: 0, learning: .active,
                adsets: [AdSet(id: "as_\(UUID().uuidString.prefix(6))", name: d.adsetName, status: status,
                               daily: d.daily, spend: 0, revenue: 0, roas: 0, purchases: 0, cpa: 0, ctr: 0,
                               learning: .learning, audience: d.optimization.label,
                               placements: "Advantage+ placements",
                               ads: d.hasCreative ? [Ad(id: "ad_\(UUID().uuidString.prefix(6))", name: d.adName,
                                                        status: status, spend: 0, revenue: 0, roas: 0, ctr: 0,
                                                        format: d.format, thumb: Color(hex: 0xE91E78))] : [])])
            campaigns.insert(new, at: 0)
        }
    }

    // ── Duplicate ──────────────────────────────────────────────────────────

    func duplicate(_ campaign: Campaign) {
        var d = DraftCampaign()
        d.name = campaign.name + " — copy"
        d.objective = campaign.objective
        d.daily = campaign.daily > 0 ? campaign.daily : d.daily
        d.optimization = .suggested(for: campaign.objective)
        if let firstAd = campaign.adsets.first?.ads.first {
            d.adName = firstAd.name
        }
        createPrefill = d
        drawerCampaignID = nil
        createOpen = true
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
        accounts = []
        Fmt.currency = snap.account.currency
        discard()
    }

    func switchAccount(_ account: AccountInfo) {
        guard var creds = Credentials.load(), creds.actId != account.id else { return }
        creds.accountId = account.id
        try? creds.save()
        discard()
        switchToLive()
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let snap = try await backend.loadSnapshot()
            snapshot = snap
            campaigns = snap.campaigns.filter { $0.status != .archived }
            Fmt.currency = snap.account.currency
            if mode == .live {
                accounts = (try? await backend.accounts()) ?? []
            }
        } catch {
            banner = Banner(text: "Couldn't load account: \(error.localizedDescription)", isError: true)
        }
    }
}
