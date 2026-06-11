import SwiftUI

// Campaign management — the expandable campaign → ad set → ad tree with
// staged status switches (campaigns.jsx).

struct CampaignsListView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.theme) private var th
    @State private var query = ""
    @State private var filter = "all"

    var body: some View {
        let rows = state.campaigns.filter { c in
            if !query.isEmpty && !c.name.localizedCaseInsensitiveContains(query) { return false }
            let eff = state.effectiveStatus(c.id, base: c.status)
            if filter == "active" && eff != .active { return false }
            if filter == "paused" && eff != .paused { return false }
            return true
        }
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Campaigns")
                        .font(jakarta(26, .extra)).kerning(-0.4)
                        .foregroundStyle(th.fg1)
                    Text("\(state.campaigns.count) campaigns · expand to manage ad sets and ads")
                        .font(jakarta(13.5)).foregroundStyle(th.fg3)
                }
                Spacer()
                Btn(variant: .primary, icon: "plus", label: "New campaign") {
                    state.createOpen = true
                }
            }

            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13))
                        .foregroundStyle(th.fg4)
                    TextField("Search campaigns", text: $query)
                        .textFieldStyle(.plain)
                        .font(jakarta(13.5))
                        .foregroundStyle(th.fg1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(th.bg1)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(th.borderStrong, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .frame(maxWidth: 360)

                Segmented(options: [("all", "All"), ("active", "Active"), ("paused", "Paused")], value: $filter)
                Spacer()
            }

            VStack(spacing: 10) {
                ForEach(rows) { campaign in
                    CampaignBlock(campaign: campaign)
                }
                if rows.isEmpty {
                    Text("No campaigns match.")
                        .font(jakarta(14)).foregroundStyle(th.fg4)
                        .frame(maxWidth: .infinity)
                        .padding(40)
                }
            }
        }
    }
}

// ── Status switch + staged chip ────────────────────────────────────────────

struct StatusSwitch: View {
    var entityId: String
    var kind: EntityKind
    var name: String
    var base: EntityStatus
    @EnvironmentObject private var state: AppState
    @Environment(\.theme) private var th

    var body: some View {
        let desired = state.effectiveStatus(entityId, base: base)
        let isPending = state.pending[entityId] != nil && state.pending[entityId] != base
        HStack(spacing: 8) {
            PacerSwitch(on: desired == .active) { on in
                state.toggle(entityId: entityId, kind: kind, name: name,
                             base: base, to: on ? .active : .paused)
            }
            if isPending {
                Text(desired == .active ? "→ go live" : desired == .archived ? "→ archive" : "→ pause")
                    .font(jakarta(10.5, .bold))
                    .foregroundStyle(th.accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(th.accentSoft))
                    .fixedSize()
            }
        }
    }
}

// ── Campaign block (expandable) ────────────────────────────────────────────

private struct CampaignBlock: View {
    var campaign: Campaign
    @EnvironmentObject private var state: AppState
    @Environment(\.theme) private var th
    @State private var open = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                StatusSwitch(entityId: campaign.id, kind: .campaign,
                             name: campaign.name, base: campaign.status)
                Button { withAnimation(.easeOut(duration: 0.15)) { open.toggle() } } label: {
                    Image(systemName: open ? "chevron.down" : "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(th.fg3)
                        .frame(width: 18)
                }
                .buttonStyle(.plain)

                Button { state.drawerCampaignID = campaign.id } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Image(systemName: campaign.objective.icon)
                                .font(.system(size: 13))
                                .foregroundStyle(th.fg3)
                            Text(campaign.name)
                                .font(jakarta(14.5, .bold))
                                .foregroundStyle(th.fg1)
                                .lineLimit(1)
                        }
                        Text("\(campaign.objective.rawValue) · \(campaign.adsets.count) ad set\(campaign.adsets.count == 1 ? "" : "s") · Campaign \(campaign.id)")
                            .font(jakarta(11.5))
                            .foregroundStyle(th.fg4)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if state.pendingDeletes.contains(campaign.id) {
                    Text("→ delete")
                        .font(jakarta(10.5, .bold))
                        .foregroundStyle(th.danger)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(th.danger100))
                        .fixedSize()
                }
                if let staged = state.pendingBudgets[campaign.id] {
                    Text("→ \(Fmt.money(staged, compact: true))/d")
                        .font(jakarta(10.5, .bold))
                        .foregroundStyle(th.accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(th.accentSoft))
                        .fixedSize()
                }
                MetricCol(label: "Spend", value: Fmt.money(campaign.spend, compact: true), width: 76)
                MetricCol(label: secondMetricLabel,
                          value: secondMetricValue, width: 84)
                MetricCol(label: "ROAS", value: Fmt.roas(campaign.roas), width: 54,
                          accent: campaign.roas >= 4.5 ? th.success : nil)
                IconButton(icon: "arrow.up.right", size: 30) {
                    state.drawerCampaignID = campaign.id
                }
            }
            .padding(14)
            .hoverRow()
            .contextMenu {
                Button("Open details") { state.drawerCampaignID = campaign.id }
                Button("Duplicate") { state.duplicate(campaign) }
                Divider()
                Button(state.pending[campaign.id] == .archived ? "Undo archive" : "Archive") {
                    state.toggle(entityId: campaign.id, kind: .campaign, name: campaign.name,
                                 base: campaign.status,
                                 to: state.pending[campaign.id] == .archived ? campaign.status : .archived)
                }
                Button(state.pendingDeletes.contains(campaign.id) ? "Undo delete" : "Delete…",
                       role: .destructive) {
                    state.stageDelete(entityId: campaign.id)
                }
            }

            if open {
                ForEach(campaign.adsets) { adset in
                    AdSetRow(adset: adset)
                }
            }
        }
        .background(th.bg1)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(th.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: th.shadowColor, radius: 2, y: 1)
    }

    private var secondMetricLabel: String {
        switch campaign.objective {
        case .leads: return "CPL"
        case .awareness: return "CPM"
        default: return "Revenue"
        }
    }
    private var secondMetricValue: String {
        switch campaign.objective {
        case .leads: return Fmt.money(campaign.cpl, compact: true)
        case .awareness: return Fmt.money(campaign.cpm, compact: true)
        default: return Fmt.money(campaign.revenue, compact: true)
        }
    }
}

// ── Ad set row ─────────────────────────────────────────────────────────────

private struct AdSetRow: View {
    var adset: AdSet
    @EnvironmentObject private var state: AppState
    @Environment(\.theme) private var th
    @State private var open = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                StatusSwitch(entityId: adset.id, kind: .adset, name: adset.name, base: adset.status)
                Button { withAnimation(.easeOut(duration: 0.15)) { open.toggle() } } label: {
                    Image(systemName: open ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(th.fg3)
                        .frame(width: 16)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 1) {
                    Text(adset.name)
                        .font(jakarta(13.5, .semibold))
                        .foregroundStyle(th.fg1)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(adset.audience)
                            .font(jakarta(11.5))
                            .foregroundStyle(th.fg4)
                            .lineLimit(1)
                        if adset.learning == .learning {
                            Text("· learning")
                                .font(jakarta(11.5, .semibold))
                                .foregroundStyle(th.warning)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                MetricCol(label: "Spend", value: Fmt.money(adset.spend, compact: true), width: 72)
                MetricCol(label: "Results", value: results, width: 84)
                MetricCol(label: "ROAS", value: Fmt.roas(adset.roas), width: 54,
                          accent: adset.roas >= 4.5 ? th.success : nil)
            }
            .padding(.vertical, 11)
            .padding(.leading, 38)
            .padding(.trailing, 14)
            .background(th.bg1)
            .overlay(alignment: .top) { Rectangle().fill(th.border).frame(height: 1) }
            .hoverRow()

            if open {
                ForEach(adset.ads) { ad in
                    AdRow(ad: ad)
                }
            }
        }
    }

    private var results: String {
        if let leads = adset.leads { return "\(leads) leads" }
        if adset.purchases > 0 { return "\(adset.purchases) purch" }
        return Fmt.compactInt(Double(adset.reach ?? 0))
    }
}

// ── Ad row ─────────────────────────────────────────────────────────────────

private struct AdRow: View {
    var ad: Ad
    @EnvironmentObject private var state: AppState
    @Environment(\.theme) private var th

    var body: some View {
        HStack(spacing: 10) {
            StatusSwitch(entityId: ad.id, kind: .ad, name: ad.name, base: ad.status)
            RoundedRectangle(cornerRadius: 7)
                .fill(ad.thumb)
                .frame(width: 30, height: 30)
                .overlay(Image(systemName: ad.format.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 1) {
                Text(ad.name)
                    .font(jakarta(13, .medium))
                    .foregroundStyle(th.fg1)
                    .lineLimit(1)
                Text(ad.format.rawValue)
                    .font(jakarta(11))
                    .foregroundStyle(th.fg4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            MetricCol(label: "Spend", value: Fmt.money(ad.spend, compact: true), width: 72)
            MetricCol(label: "ROAS", value: Fmt.roas(ad.roas), width: 54,
                      accent: ad.roas >= 4.5 ? th.success : nil)
            MetricCol(label: "CTR", value: String(format: "%.1f%%", ad.ctr), width: 48)
        }
        .padding(.vertical, 10)
        .padding(.leading, 62)
        .padding(.trailing, 14)
        .background(th.bg2)
        .overlay(alignment: .top) { Rectangle().fill(th.border).frame(height: 1) }
        .hoverRow()
    }
}
