import SwiftUI

// Campaign detail drawer sliding from the right (create.jsx).

struct CampaignDrawer: View {
    var campaign: Campaign
    @EnvironmentObject private var state: AppState
    @Environment(\.theme) private var th
    @State private var editingBudget = false
    @State private var budgetValue: Double = 0

    var body: some View {
        let eff = state.effectiveStatus(campaign.id, base: campaign.status)
        ZStack(alignment: .trailing) {
            Color(hex: 0x0E0F1A).opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { state.drawerCampaignID = nil }

            VStack(spacing: 0) {
                // header
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Pill(status: eff == .paused ? .paused : (campaign.learning == .learning ? .learning : .active))
                        Spacer()
                        IconButton(icon: "xmark", size: 30, bordered: false) {
                            state.drawerCampaignID = nil
                        }
                    }
                    Text(campaign.name)
                        .font(jakarta(21, .extra)).kerning(-0.2)
                        .foregroundStyle(th.fg1)
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                    Text("\(campaign.objective.rawValue) · Campaign \(campaign.id)")
                        .font(jakarta(12.5))
                        .foregroundStyle(th.fg3)
                }
                .padding(.init(top: 18, leading: 22, bottom: 18, trailing: 22))
                .background(th.bg1)
                .overlay(alignment: .bottom) { Rectangle().fill(th.border).frame(height: 1) }

                ConditionalScroll {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 10) {
                            statTile("Spend", Fmt.money(campaign.spend, compact: true))
                            statTile("ROAS", Fmt.roas(campaign.roas))
                            statTile(thirdLabel, thirdValue)
                        }
                        Card(pad: 16) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Revenue trend · 30d")
                                    .font(jakarta(13, .bold)).foregroundStyle(th.fg1)
                                AreaChart(data: trend, color: th.accent, showDot: true)
                                    .frame(height: 90)
                            }
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Ad sets").font(jakarta(13, .bold)).foregroundStyle(th.fg1)
                            ForEach(campaign.adsets) { adset in
                                HStack(spacing: 10) {
                                    PacerSwitch(on: state.effectiveStatus(adset.id, base: adset.status) == .active) { on in
                                        state.toggle(entityId: adset.id, kind: .adset, name: adset.name,
                                                     base: adset.status, to: on ? .active : .paused)
                                    }
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(adset.name)
                                            .font(jakarta(13, .semibold))
                                            .foregroundStyle(th.fg1)
                                            .lineLimit(1)
                                        Text(adset.audience)
                                            .font(jakarta(11))
                                            .foregroundStyle(th.fg4)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 1) {
                                        Text(Fmt.roas(adset.roas))
                                            .font(jakarta(13, .bold)).foregroundStyle(th.fg1)
                                        Text(Fmt.money(adset.spend, compact: true))
                                            .font(jakarta(11)).foregroundStyle(th.fg4)
                                    }
                                }
                                .padding(.init(top: 11, leading: 13, bottom: 11, trailing: 13))
                                .background(th.bg1)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(th.border, lineWidth: 1))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                    .padding(22)
                }
                .background(th.bg2)

                VStack(spacing: 10) {
                    if editingBudget {
                        HStack(spacing: 8) {
                            Text(Fmt.currency == "IDR" ? "Rp" : Fmt.currency)
                                .font(jakarta(13)).foregroundStyle(th.fg3)
                            TextField("Daily budget", value: $budgetValue, format: .number)
                                .textFieldStyle(.plain)
                                .font(jakarta(14, .semibold)).monospacedDigit()
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(th.bg2)
                                .overlay(RoundedRectangle(cornerRadius: 9).stroke(th.accent, lineWidth: 1.5))
                                .clipShape(RoundedRectangle(cornerRadius: 9))
                            Text("/day").font(jakarta(12)).foregroundStyle(th.fg4)
                            Spacer()
                            Btn(variant: .ghost, size: .sm, label: "Cancel") { editingBudget = false }
                            Btn(variant: .primary, size: .sm, label: "Stage change") {
                                state.stageBudget(entityId: campaign.id, current: campaign.daily, to: budgetValue)
                                editingBudget = false
                            }
                        }
                    }
                    HStack(spacing: 10) {
                        Btn(variant: .secondary, icon: "doc.on.doc", label: "Duplicate") {
                            state.duplicate(campaign)
                        }
                        .frame(maxWidth: .infinity)
                        Btn(variant: .secondary, icon: "pencil",
                            label: state.pendingBudgets[campaign.id] != nil
                                ? "Budget → \(Fmt.money(state.pendingBudgets[campaign.id], compact: true))"
                                : "Edit budget") {
                            budgetValue = state.pendingBudgets[campaign.id] ?? campaign.daily
                            editingBudget.toggle()
                        }
                        .frame(maxWidth: .infinity)
                        Menu {
                            Button(state.pending[campaign.id] == .archived ? "Undo archive" : "Archive campaign") {
                                state.toggle(entityId: campaign.id, kind: .campaign, name: campaign.name,
                                             base: campaign.status,
                                             to: state.pending[campaign.id] == .archived ? campaign.status : .archived)
                            }
                            Button(state.pendingDeletes.contains(campaign.id) ? "Undo delete" : "Delete campaign…",
                                   role: .destructive) {
                                state.stageDelete(entityId: campaign.id)
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(width: 36, height: 36)
                                .background(th.bg1)
                                .foregroundStyle(th.fg2)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(th.borderStrong, lineWidth: 1))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .menuStyle(.button)
                        .buttonStyle(.plain)
                        .menuIndicator(.hidden)
                        .fixedSize()
                    }
                }
                .padding(16)
                .background(th.bg1)
                .overlay(alignment: .top) { Rectangle().fill(th.border).frame(height: 1) }
            }
            .frame(width: 460)
            .background(th.bg2)
            .shadow(color: .black.opacity(0.25), radius: 30, x: -8)
            .transition(.move(edge: .trailing))
        }
        .transition(.opacity)
    }

    private func statTile(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(jakarta(11)).foregroundStyle(th.fg3)
            Text(value).font(jakarta(18, .extra)).foregroundStyle(th.fg1).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.init(top: 12, leading: 14, bottom: 12, trailing: 14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(th.bg1)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(th.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var thirdLabel: String {
        switch campaign.objective {
        case .leads: return "Leads"
        case .awareness: return "Reach"
        default: return "Purchases"
        }
    }
    private var thirdValue: String {
        switch campaign.objective {
        case .leads: return "\(campaign.leads ?? 0)"
        case .awareness: return Fmt.compactInt(Double(campaign.reach ?? 0))
        default: return "\(campaign.purchases)"
        }
    }
    private var trend: [Double] {
        let factor = campaign.roas > 0 ? campaign.roas / 5 : 0.4
        return state.snapshot.seriesRevenue.suffix(30).map { $0 * factor }
    }
}
