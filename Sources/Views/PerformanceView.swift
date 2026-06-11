import SwiftUI

// Performance dashboard — Overview / Spotlight / Table layouts from reporting.jsx.

struct PerformanceView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var prefs: Prefs
    @Environment(\.theme) private var th
    @State private var range = 7

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            switch prefs.dashLayout {
            case .overview: overview
            case .spotlight: spotlight
            case .table: tableLayout
            }
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Performance")
                    .font(jakarta(26, .extra)).kerning(-0.4)
                    .foregroundStyle(th.fg1)
                Text("\(state.snapshot.account.name) · \(state.snapshot.account.accountId)")
                    .font(jakarta(13.5))
                    .foregroundStyle(th.fg3)
            }
            Spacer()
            Segmented(options: [(7, "7 days"), (30, "30 days"), (90, "90 days")], value: $range)
        }
    }

    // ── Overview (default) ─────────────────────────────────────────────────

    private var overview: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                KpiCard(key: "spend", label: "Spend")
                KpiCard(key: "revenue", label: "Revenue")
                KpiCard(key: "roas", label: "ROAS")
                KpiCard(key: "purchases", label: "Purchases")
            }
            HStack(alignment: .top, spacing: 14) {
                RevenueSpendCard(range: range).frame(maxWidth: .infinity)
                PlacementDonutCard().frame(width: 340)
            }
            if !state.snapshot.breakdowns.ages.isEmpty || !state.snapshot.breakdowns.genders.isEmpty {
                DemographicsCard()
            }
            HStack(alignment: .top, spacing: 14) {
                Card(pad: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("Top campaigns").font(jakarta(15, .bold)).foregroundStyle(th.fg1)
                            Spacer()
                            Btn(variant: .ghost, size: .sm, label: "View all →") {
                                state.section = .campaigns
                            }
                        }
                        .padding(.init(top: 16, leading: 14, bottom: 8, trailing: 14))
                        CampaignTable(rows: state.campaigns.sorted { $0.spend > $1.spend })
                    }
                }
                .frame(maxWidth: .infinity)
                Card {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Diagnostics").font(jakarta(15, .bold)).foregroundStyle(th.fg1)
                            Spacer()
                            Text("\(state.snapshot.diagnostics.count) signals")
                                .font(jakarta(12)).foregroundStyle(th.fg3)
                        }
                        ForEach(state.snapshot.diagnostics) { d in
                            DiagnosticItem(diag: d)
                        }
                    }
                }
                .frame(width: 340)
            }
        }
    }

    // ── Spotlight ──────────────────────────────────────────────────────────

    private var spotlight: some View {
        let roas = state.snapshot.kpis.roas
        return VStack(spacing: 18) {
            Card(pad: 26) {
                ZStack(alignment: .leading) {
                    AreaChart(data: Array(state.snapshot.seriesRoas.suffix(30)),
                              color: th.accent, strokeWidth: 3)
                        .opacity(0.5)
                        .frame(height: 200)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("BLENDED ROAS · LAST 7 DAYS")
                            .font(jakarta(13, .semibold)).kerning(0.4)
                            .foregroundStyle(th.fg3)
                        HStack(alignment: .lastTextBaseline, spacing: 16) {
                            Text(String(format: "%.2f×", roas.value))
                                .font(jakarta(72, .extra)).kerning(-2)
                                .foregroundStyle(th.fg1)
                            DeltaBadge(value: roas.delta, size: 16)
                        }
                        (Text("You earned ")
                         + Text(Fmt.money(state.snapshot.kpis.revenue.value)).bold()
                         + Text(" on ")
                         + Text(Fmt.money(state.snapshot.kpis.spend.value)).bold()
                         + Text(" of spend."))
                            .font(jakarta(14))
                            .foregroundStyle(th.fg2)
                    }
                }
            }
            HStack(spacing: 14) {
                KpiCard(key: "spend", label: "Spend")
                KpiCard(key: "purchases", label: "Purchases")
                KpiCard(key: "cpa", label: "Cost / purchase")
                KpiCard(key: "ctr", label: "CTR")
            }
            Card(pad: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Campaign leaderboard")
                        .font(jakarta(15, .bold)).foregroundStyle(th.fg1)
                        .padding(.init(top: 16, leading: 14, bottom: 8, trailing: 14))
                    CampaignTable(rows: state.campaigns.sorted { $0.roas > $1.roas })
                }
            }
        }
    }

    // ── Table ──────────────────────────────────────────────────────────────

    private var tableLayout: some View {
        let strip: [(String, String)] = [("spend", "Spend"), ("revenue", "Revenue"), ("roas", "ROAS"),
                                         ("purchases", "Purchases"), ("cpa", "CPA"), ("ctr", "CTR"),
                                         ("reach", "Reach"), ("cpm", "CPM")]
        return VStack(spacing: 18) {
            Card(pad: 0) {
                let cols = Array(repeating: GridItem(.flexible(), spacing: 0), count: 4)
                LazyVGrid(columns: cols, spacing: 0) {
                    ForEach(Array(strip.enumerated()), id: \.offset) { i, item in
                        let kpi = state.snapshot.kpis[item.0]
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(item.1).font(jakarta(12)).foregroundStyle(th.fg3)
                                Spacer()
                                DeltaBadge(value: kpi.delta, invert: kpi.invert, size: 11)
                            }
                            Text(Fmt.metric(kpi.value, kpi.fmt))
                                .font(jakarta(22, .extra)).kerning(-0.2)
                                .foregroundStyle(th.fg1)
                        }
                        .padding(.init(top: 14, leading: 18, bottom: 14, trailing: 18))
                        .overlay(alignment: .trailing) {
                            if i % 4 != 3 { Rectangle().fill(th.border).frame(width: 1) }
                        }
                        .overlay(alignment: .bottom) {
                            if i < 4 { Rectangle().fill(th.border).frame(height: 1) }
                        }
                    }
                }
            }
            Card(pad: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("All campaigns")
                        .font(jakarta(15, .bold)).foregroundStyle(th.fg1)
                        .padding(.init(top: 16, leading: 14, bottom: 8, trailing: 14))
                    CampaignTable(rows: state.campaigns)
                }
            }
        }
    }
}

// ── KPI card ───────────────────────────────────────────────────────────────

private struct KpiCard: View {
    var key: String
    var label: String
    @EnvironmentObject private var state: AppState
    @Environment(\.theme) private var th

    var body: some View {
        let kpi = state.snapshot.kpis[key]
        Card(pad: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(label).font(jakarta(13, .medium)).foregroundStyle(th.fg3)
                    Spacer()
                    DeltaBadge(value: kpi.delta, invert: kpi.invert)
                }
                Text(Fmt.metric(kpi.value, kpi.fmt))
                    .font(jakarta(26, .extra)).kerning(-0.4)
                    .foregroundStyle(th.fg1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Sparkline(data: kpi.series, color: kpi.invert ? th.fg4 : th.accent)
            }
        }
    }
}

// ── Revenue & spend chart card ─────────────────────────────────────────────

private struct RevenueSpendCard: View {
    var range: Int
    @EnvironmentObject private var state: AppState
    @Environment(\.theme) private var th

    var body: some View {
        let n = min(range, state.snapshot.seriesSpend.count)
        let spend = Array(state.snapshot.seriesSpend.suffix(n))
        let revenue = Array(state.snapshot.seriesRevenue.suffix(n))
        Card {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Revenue & spend").font(jakarta(15, .bold)).foregroundStyle(th.fg1)
                        Text("Last \(n) days\(state.snapshot.account.region.isEmpty ? "" : " · \(state.snapshot.account.region)")")
                            .font(jakarta(12.5)).foregroundStyle(th.fg3)
                    }
                    Spacer()
                    HStack(spacing: 16) {
                        LegendItem(color: th.accent, label: "Revenue",
                                   value: Fmt.money(revenue.reduce(0, +), compact: true))
                        LegendItem(color: th.fg4, label: "Spend",
                                   value: Fmt.money(spend.reduce(0, +), compact: true))
                    }
                }
                ZStack {
                    AreaChart(data: revenue, color: th.accent, showDot: true)
                    AreaChart(data: spend, color: th.fg4, fill: false, strokeWidth: 2, showDot: true)
                }
                .frame(height: 200)
            }
        }
    }
}

private struct LegendItem: View {
    var color: Color
    var label: String
    var value: String
    @Environment(\.theme) private var th

    var body: some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(jakarta(11)).foregroundStyle(th.fg3)
                Text(value).font(jakarta(13, .bold)).monospacedDigit().foregroundStyle(th.fg1)
            }
        }
    }
}

// ── Placement donut card ───────────────────────────────────────────────────

private struct PlacementDonutCard: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.theme) private var th

    var body: some View {
        let slices = state.snapshot.breakdowns.placements
        let palette = [th.accent, th.brandMagenta, th.warning, th.success, th.fg4]
        let total = max(slices.reduce(0) { $0 + $1.value }, 1)
        let segments = slices.prefix(5).enumerated().map { i, slice in
            DonutSegment(label: slice.label, value: slice.value, color: palette[i % palette.count])
        }
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Text("Spend by placement").font(jakarta(15, .bold)).foregroundStyle(th.fg1)
                if segments.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "chart.pie")
                            .font(.system(size: 24))
                            .foregroundStyle(th.fg4)
                        Text("Placement breakdown appears once campaigns deliver.")
                            .font(jakarta(12.5))
                            .foregroundStyle(th.fg3)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                } else {
                    HStack(spacing: 18) {
                        ZStack {
                            DonutChart(segments: segments)
                            VStack(spacing: 0) {
                                Text(String(format: "%.1f×", state.snapshot.kpis.roas.value))
                                    .font(jakarta(18, .extra)).foregroundStyle(th.fg1)
                                Text("blended").font(jakarta(10)).foregroundStyle(th.fg3)
                            }
                        }
                        VStack(spacing: 9) {
                            ForEach(segments) { seg in
                                HStack(spacing: 8) {
                                    RoundedRectangle(cornerRadius: 2).fill(seg.color).frame(width: 8, height: 8)
                                    Text(seg.label).font(jakarta(12.5)).foregroundStyle(th.fg2).lineLimit(1)
                                    Spacer()
                                    Text("\(Int((seg.value / total * 100).rounded()))%")
                                        .font(jakarta(12.5, .bold)).monospacedDigit()
                                        .foregroundStyle(th.fg1)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// ── Demographics card (age / gender / geo from insights breakdowns) ────────

private struct DemographicsCard: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.theme) private var th

    var body: some View {
        let b = state.snapshot.breakdowns
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Text("Audience · spend by demographic")
                    .font(jakarta(15, .bold)).foregroundStyle(th.fg1)
                HStack(alignment: .top, spacing: 28) {
                    if !b.ages.isEmpty {
                        breakdownColumn("Age", slices: b.ages, tint: th.accent)
                    }
                    if !b.genders.isEmpty {
                        breakdownColumn("Gender", slices: b.genders, tint: th.brandMagenta)
                    }
                    if !b.countries.isEmpty {
                        breakdownColumn("Country", slices: b.countries, tint: th.warning)
                    }
                }
            }
        }
    }

    private func breakdownColumn(_ title: String, slices: [BreakdownSlice], tint: Color) -> some View {
        let maxV = max(slices.map(\.value).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(jakarta(10.5, .bold)).kerning(0.5)
                .foregroundStyle(th.fg4)
            ForEach(slices) { slice in
                HStack(spacing: 9) {
                    Text(slice.label)
                        .font(jakarta(12))
                        .foregroundStyle(th.fg2)
                        .frame(width: 64, alignment: .leading)
                        .lineLimit(1)
                    Capsule().fill(th.bg3)
                        .frame(width: 110, height: 6)
                        .overlay(alignment: .leading) {
                            Capsule().fill(tint).frame(width: 110 * slice.value / maxV)
                        }
                    Text(Fmt.money(slice.value, compact: true))
                        .font(jakarta(11.5, .semibold)).monospacedDigit()
                        .foregroundStyle(th.fg3)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// ── Campaign mini-table ────────────────────────────────────────────────────

struct CampaignTable: View {
    var rows: [Campaign]
    @EnvironmentObject private var state: AppState
    @Environment(\.theme) private var th

    var body: some View {
        let maxSpend = max(rows.map(\.spend).max() ?? 1, 1)
        VStack(spacing: 0) {
            HStack {
                Text("CAMPAIGN").frame(maxWidth: .infinity, alignment: .leading)
                Text("SPEND").frame(width: 80, alignment: .trailing)
                Text("REVENUE").frame(width: 80, alignment: .trailing)
                Text("ROAS").frame(width: 56, alignment: .trailing)
                Text("SHARE").frame(width: 92, alignment: .leading).padding(.leading, 14)
            }
            .font(jakarta(11, .semibold))
            .kerning(0.5)
            .foregroundStyle(th.fg3)
            .padding(.horizontal, 14)
            .padding(.bottom, 8)

            ForEach(rows) { c in
                Button {
                    state.section = .campaigns
                    state.drawerCampaignID = c.id
                } label: {
                    HStack {
                        HStack(spacing: 10) {
                            Pill(status: c.status == .paused ? .paused : (c.learning == .learning ? .learning : .active))
                            Text(c.name)
                                .font(jakarta(13.5, .semibold))
                                .foregroundStyle(th.fg1)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(Fmt.money(c.spend, compact: true))
                            .font(jakarta(13, .semibold)).monospacedDigit()
                            .foregroundStyle(th.fg1)
                            .frame(width: 80, alignment: .trailing)
                        Text(c.revenue > 0 ? Fmt.money(c.revenue, compact: true) : "—")
                            .font(jakarta(13)).monospacedDigit()
                            .foregroundStyle(th.fg1)
                            .frame(width: 80, alignment: .trailing)
                        Text(Fmt.roas(c.roas))
                            .font(jakarta(13, .bold)).monospacedDigit()
                            .foregroundStyle(c.roas <= 0 ? th.fg1 : c.roas >= 4.5 ? th.success : c.roas >= 3 ? th.fg1 : th.danger)
                            .frame(width: 56, alignment: .trailing)
                        Capsule().fill(th.bg3)
                            .frame(width: 92, height: 6)
                            .overlay(alignment: .leading) {
                                Capsule().fill(th.accent)
                                    .frame(width: 92 * min(c.spend / maxSpend, 1))
                            }
                            .padding(.leading, 14)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverRow()
            }
        }
    }
}

// ── Diagnostics feed item ──────────────────────────────────────────────────

struct DiagnosticItem: View {
    var diag: Diagnostic
    @Environment(\.theme) private var th

    var body: some View {
        let (fg, bg) = colors
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 9)
                .fill(bg)
                .frame(width: 34, height: 34)
                .overlay(Image(systemName: diag.icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(fg))
            VStack(alignment: .leading, spacing: 2) {
                Text(diag.title).font(jakarta(14, .semibold)).foregroundStyle(th.fg1)
                (Text(diag.target).font(jakarta(12.5, .semibold)).foregroundStyle(th.fg2)
                 + Text(" · \(diag.detail)").font(jakarta(12.5)).foregroundStyle(th.fg3))
                    .lineSpacing(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) { Rectangle().fill(th.border).frame(height: 1) }
    }

    var colors: (Color, Color) {
        switch diag.level {
        case .warning: return (th.warning, th.warning100)
        case .danger: return (th.danger, th.danger100)
        case .info: return (th.brandBlue, th.brandBlue100)
        case .success: return (th.success, th.success100)
        }
    }
}
