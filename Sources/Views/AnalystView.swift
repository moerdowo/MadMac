import SwiftUI

// AI Analyst: daily brief, winners/bleeders/fatigue boards (signals computed
// locally from per-ad insights), stageable recommendations, and
// copy-from-winners. Only reachable when AI is enabled.

struct AnalystView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.theme) private var th
    @State private var perf: [AdPerf] = []
    @State private var result: AnalystResult?
    @State private var savedBrief: AnalystBrief?
    @State private var loading = false
    @State private var error: String?
    @State private var copySheetOpen = false

    // ImageRenderer can't run .task, so snapshots inject data statically.
    static var snapshotData: ([AdPerf], AnalystResult)?

    init() {
        if let (perf, result) = Self.snapshotData {
            _perf = State(initialValue: perf)
            _result = State(initialValue: result)
        }
    }

    var body: some View {
        let winners = perf.filter(\.isWinner)
        let bleeders = perf.filter(\.isBleeder)
        let watchlist = perf.filter { ($0.isDying || $0.isFatigued) && !$0.isBleeder }

        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Analyst").font(jakarta(26, .extra)).kerning(-0.4).foregroundStyle(th.fg1)
                    Text(subtitle)
                        .font(jakarta(13.5)).foregroundStyle(th.fg3)
                }
                Spacer()
                if !winners.isEmpty {
                    Btn(variant: .soft, icon: "square.and.pencil", label: "Write copy from winners") {
                        copySheetOpen = true
                    }
                }
                Btn(variant: .primary, icon: "sparkles",
                    label: loading ? "Analyzing…" : "Refresh analysis", disabled: loading) {
                    Task { await run(force: true) }
                }
            }

            if let error {
                Text(error).font(jakarta(12.5, .medium)).foregroundStyle(th.danger)
            }

            // ── Daily brief ────────────────────────────────────────────────
            Card(pad: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "sun.max")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(th.warning)
                        Text("DAILY BRIEF")
                            .font(jakarta(11, .bold)).kerning(0.6)
                            .foregroundStyle(th.fg3)
                        Spacer()
                        if loading { ProgressView().controlSize(.small) }
                    }
                    if let text = result?.brief ?? savedBrief?.text {
                        Text(text)
                            .font(jakarta(14))
                            .foregroundStyle(th.fg1)
                            .lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(loading ? "Reading the account…" : "No brief yet — Refresh analysis generates one. It updates automatically once a day.")
                            .font(jakarta(13)).foregroundStyle(th.fg3)
                    }
                }
            }

            // ── Boards ─────────────────────────────────────────────────────
            if perf.isEmpty && !loading {
                Card(pad: 36) {
                    VStack(spacing: 10) {
                        Image(systemName: "chart.line.downtrend.xyaxis")
                            .font(.system(size: 28)).foregroundStyle(th.fg4)
                        Text("No per-ad delivery data yet. Once ads run, winners, bleeders, and fatigue signals appear here.")
                            .font(jakarta(13)).foregroundStyle(th.fg3)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else if !perf.isEmpty {
                HStack(alignment: .top, spacing: 14) {
                    board("Winners", icon: "trophy", tint: th.success, ads: winners,
                          empty: "No clear winners yet.")
                    board("Bleeders", icon: "drop.degreesign", tint: th.danger, ads: bleeders,
                          empty: "Nothing bleeding. Good.")
                    board("Watchlist · fatigue & decay", icon: "binoculars", tint: th.warning, ads: watchlist,
                          empty: "No fatigue or decay signals.")
                }
            }

            // ── Recommendations ────────────────────────────────────────────
            if let recommendations = result?.recommendations, !recommendations.isEmpty {
                Card(pad: 0) {
                    VStack(spacing: 0) {
                        HStack(spacing: 7) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 13, weight: .semibold)).foregroundStyle(th.accent)
                            Text("Recommended actions").font(jakarta(15, .bold)).foregroundStyle(th.fg1)
                            Spacer()
                            Text("staged changes still need Approve")
                                .font(jakarta(11)).foregroundStyle(th.fg4)
                        }
                        .padding(.init(top: 16, leading: 20, bottom: 16, trailing: 20))
                        .overlay(alignment: .bottom) { Rectangle().fill(th.border).frame(height: 1) }
                        ForEach(recommendations) { rec in
                            RecommendationRow(rec: rec)
                        }
                    }
                }
            }
        }
        .task(id: state.snapshot.account.accountId) {
            savedBrief = Analyst.loadSavedBrief(accountId: state.snapshot.account.accountId)
            if AIPrefs.shared.isActive {
                await run(force: !Analyst.savedBriefIsToday(accountId: state.snapshot.account.accountId))
            }
        }
        .sheet(isPresented: $copySheetOpen) {
            WinnerCopySheet(winners: winners) { copySheetOpen = false }
                .environmentObject(state)
                .environment(\.theme, th)
        }
    }

    private var subtitle: String {
        if let result {
            return "Updated \(result.generatedAt.formatted(date: .abbreviated, time: .shortened)) · signals computed from per-ad insights"
        }
        if let savedBrief { return "Brief from \(savedBrief.date) · refresh for current signals" }
        return "Daily brief · winners · bleeders · fatigue, computed from per-ad insights"
    }

    private func run(force: Bool) async {
        loading = true
        error = nil
        do {
            perf = try await state.backend.adPerformance()
            if force || result == nil {
                result = try await Analyst.run(perf: perf, snapshot: state.snapshot)
                savedBrief = Analyst.loadSavedBrief(accountId: state.snapshot.account.accountId)
            }
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    // ── Board card ─────────────────────────────────────────────────────────

    private func board(_ title: String, icon: String, tint: Color, ads: [AdPerf], empty: String) -> some View {
        Card(pad: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 7) {
                    Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(tint)
                    Text(title).font(jakarta(13.5, .bold)).foregroundStyle(th.fg1)
                    Spacer()
                    Text("\(ads.count)").font(jakarta(12, .bold)).foregroundStyle(tint)
                }
                .padding(.init(top: 14, leading: 16, bottom: 12, trailing: 16))
                .overlay(alignment: .bottom) { Rectangle().fill(th.border).frame(height: 1) }
                if ads.isEmpty {
                    Text(empty)
                        .font(jakarta(12)).foregroundStyle(th.fg4)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 22)
                } else {
                    ForEach(ads) { ad in
                        AnalystAdRow(ad: ad, tint: tint)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// ── Ad row inside a board ──────────────────────────────────────────────────

private struct AnalystAdRow: View {
    var ad: AdPerf
    var tint: Color
    @EnvironmentObject private var state: AppState
    @Environment(\.theme) private var th

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(ad.name).font(jakarta(13, .semibold)).foregroundStyle(th.fg1).lineLimit(1)
                    Text(ad.campaignName).font(jakarta(10.5)).foregroundStyle(th.fg4).lineLimit(1)
                }
                Spacer()
                Sparkline(data: ad.dailyCtr, color: tint, width: 56, height: 20)
            }
            HStack(spacing: 6) {
                chip("ROAS \(Fmt.roas(ad.roas7))")
                if ad.cpa7 > 0 {
                    chip("CPA \(Fmt.money(ad.cpa7, compact: true))" + (ad.cpaPrev7 > 0 && ad.cpa7 > ad.cpaPrev7 * 1.2 ? " ↑" : ""))
                }
                chip(String(format: "CTR %.2f%%", ad.ctr7) + (ad.ctrSlope < -4 ? " ↓" : ""))
                if ad.frequency >= 3.5 { chip(String(format: "freq %.1f", ad.frequency)) }
                Spacer()
                if ad.isBleeder && ad.status == .active {
                    Btn(variant: .danger, size: .sm,
                        label: state.pending[ad.adId] == .paused ? "Pause staged ✓" : "Stage pause",
                        disabled: state.pending[ad.adId] == .paused) {
                        state.toggle(entityId: ad.adId, kind: .ad, name: ad.name, base: ad.status, to: .paused)
                    }
                }
            }
        }
        .padding(.init(top: 10, leading: 16, bottom: 10, trailing: 16))
        .overlay(alignment: .bottom) { Rectangle().fill(th.border).frame(height: 1) }
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(jakarta(10.5, .semibold)).monospacedDigit()
            .foregroundStyle(th.fg2)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(th.bg3))
    }
}

// ── Recommendation row with Stage this ─────────────────────────────────────

private struct RecommendationRow: View {
    var rec: InsightRecommendation
    @EnvironmentObject private var state: AppState
    @Environment(\.theme) private var th

    var body: some View {
        let (fg, bg): (Color, Color) = {
            switch rec.severity {
            case "danger": return (th.danger, th.danger100)
            case "warning": return (th.warning, th.warning100)
            default: return (th.brandBlue, th.brandBlue100)
            }
        }()
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 9)
                .fill(bg)
                .frame(width: 36, height: 36)
                .overlay(Image(systemName: iconName)
                    .font(.system(size: 15, weight: .medium)).foregroundStyle(fg))
            VStack(alignment: .leading, spacing: 3) {
                Text(rec.title).font(jakarta(14, .bold)).foregroundStyle(th.fg1)
                Text(rec.detail).font(jakarta(12.5)).foregroundStyle(th.fg3).lineSpacing(3)
            }
            Spacer()
            if let label = actionLabel {
                Btn(variant: .soft, size: .sm, label: staged ? "Staged ✓" : label, disabled: staged) {
                    stage()
                }
            }
        }
        .padding(.init(top: 14, leading: 20, bottom: 14, trailing: 20))
        .overlay(alignment: .bottom) { Rectangle().fill(th.border).frame(height: 1) }
    }

    private var iconName: String {
        switch rec.actionType {
        case "pause": return "pause.circle"
        case "activate": return "play.circle"
        case "set_budget": return "wallet.pass"
        default: return "lightbulb"
        }
    }

    private var entity: (EntityKind, String, EntityStatus, Double)? {
        for c in state.campaigns {
            if c.id == rec.entityId { return (.campaign, c.name, c.status, c.daily) }
            for a in c.adsets {
                if a.id == rec.entityId { return (.adset, a.name, a.status, a.daily) }
                for ad in a.ads where ad.id == rec.entityId { return (.ad, ad.name, ad.status, 0) }
            }
        }
        return nil
    }

    private var actionLabel: String? {
        guard entity != nil else { return nil }
        switch rec.actionType {
        case "pause": return "Stage pause"
        case "activate": return "Stage activate"
        case "set_budget": return "Stage \(Fmt.money(rec.value, compact: true))/d"
        default: return nil
        }
    }

    private var staged: Bool {
        state.pending[rec.entityId] != nil || state.pendingBudgets[rec.entityId] != nil
    }

    private func stage() {
        guard let (kind, name, base, daily) = entity else { return }
        switch rec.actionType {
        case "pause": state.toggle(entityId: rec.entityId, kind: kind, name: name, base: base, to: .paused)
        case "activate": state.toggle(entityId: rec.entityId, kind: kind, name: name, base: base, to: .active)
        case "set_budget": state.stageBudget(entityId: rec.entityId, current: daily, to: rec.value)
        default: break
        }
    }
}

// ── Copy-from-winners sheet ────────────────────────────────────────────────

private struct WinnerCopySheet: View {
    var winners: [AdPerf]
    var onClose: () -> Void
    @EnvironmentObject private var state: AppState
    @Environment(\.theme) private var th
    @State private var busy = false
    @State private var error: String?
    @State private var result: CopySet?

    var body: some View {
        AISheetChrome(title: "Write copy from winners",
                      subtitle: winners.map(\.name).prefix(3).joined(separator: " · "),
                      onClose: onClose) {
            VStack(alignment: .leading, spacing: 12) {
                if let result {
                    aiField("New headlines (from winning angles)") {
                        copyList(result.headlines)
                    }
                    aiField("New primary texts") {
                        copyList(result.texts)
                    }
                } else {
                    Text("Analyzes what your winning ads have in common and writes 5 fresh headlines + 5 primary texts that iterate on those angles.")
                        .font(jakarta(13)).foregroundStyle(th.fg3).lineSpacing(3)
                }
                if let error {
                    Text(error).font(jakarta(12, .medium)).foregroundStyle(th.danger)
                }
            }
        } footer: {
            if busy { ProgressView().controlSize(.small) }
            Btn(variant: result == nil ? .primary : .secondary, icon: "sparkles",
                label: result == nil ? "Generate" : "Regenerate", disabled: busy) {
                run()
            }
            if let result {
                Btn(variant: .primary, icon: "plus", label: "Use in new campaign") {
                    var d = DraftCampaign()
                    d.name = "Winners iteration — \(Date().formatted(date: .abbreviated, time: .omitted))"
                    d.headline = result.headlines.first ?? ""
                    d.text = result.texts.first ?? ""
                    d.extraHeadlines = result.headlines.dropFirst().joined(separator: "\n")
                    d.extraTexts = result.texts.dropFirst().joined(separator: "\n")
                    state.createPrefill = d
                    onClose()
                    state.createOpen = true
                }
            }
        }
    }

    private func run() {
        busy = true
        error = nil
        Task {
            do {
                result = try await Analyst.copyFromWinners(
                    winners, objective: state.campaigns.first?.objective.rawValue ?? "Sales")
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }

    private func copyList(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(jakarta(12.5))
                    .foregroundStyle(th.fg1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(th.bg1)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(th.border, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}
