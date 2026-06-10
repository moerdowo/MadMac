import SwiftUI

// Diagnostics, Catalog, Datasets sections (more.jsx).

struct DiagnosticsView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.theme) private var th

    var body: some View {
        let diags = state.snapshot.diagnostics
        let issues = diags.filter { $0.level == .danger }.count
        let learning = state.campaigns.flatMap(\.adsets).filter { $0.learning == .learning }.count
        let score = max(0, 100 - issues * 18 - learning * 6)

        VStack(alignment: .leading, spacing: 18) {
            sectionHeader("Diagnostics", "Account health, learning phase, and delivery signals")

            HStack(spacing: 14) {
                Card {
                    HStack(spacing: 16) {
                        HealthRing(score: score)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Account health").font(jakarta(13)).foregroundStyle(th.fg3)
                            Text(score >= 80 ? "Good" : score >= 60 ? "Fair" : "Poor")
                                .font(jakarta(18, .extra)).foregroundStyle(th.fg1)
                            Text(issues == 0 ? "No urgent issues" : "\(issues) issue\(issues == 1 ? "" : "s") need\(issues == 1 ? "s" : "") attention")
                                .font(jakarta(12)).foregroundStyle(th.fg4)
                        }
                    }
                }
                statCard(icon: "flame", tint: th.danger, value: "\(issues)", label: "Active issues")
                statCard(icon: "graduationcap", tint: th.warning,
                         value: learning == 1 ? "1 ad set" : "\(learning) ad sets", label: "In learning")
            }

            Card(pad: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Signals")
                        .font(jakarta(15, .bold)).foregroundStyle(th.fg1)
                        .padding(.init(top: 16, leading: 20, bottom: 16, trailing: 20))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .bottom) { Rectangle().fill(th.border).frame(height: 1) }
                    ForEach(diags) { d in
                        SignalRow(diag: d)
                    }
                }
            }
        }
    }

    private func statCard(icon: String, tint: Color, value: String, label: String) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(tint)
                Text(value).font(jakarta(24, .extra)).foregroundStyle(th.fg1)
                Text(label).font(jakarta(12.5)).foregroundStyle(th.fg3)
            }
        }
    }
}

private struct SignalRow: View {
    var diag: Diagnostic
    @Environment(\.theme) private var th

    var body: some View {
        let (fg, bg): (Color, Color) = {
            switch diag.level {
            case .warning: return (th.warning, th.warning100)
            case .danger: return (th.danger, th.danger100)
            case .info: return (th.brandBlue, th.brandBlue100)
            case .success: return (th.success, th.success100)
            }
        }()
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 9)
                .fill(bg)
                .frame(width: 38, height: 38)
                .overlay(Image(systemName: diag.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(fg))
            VStack(alignment: .leading, spacing: 3) {
                Text(diag.title).font(jakarta(14.5, .bold)).foregroundStyle(th.fg1)
                Text(diag.target).font(jakarta(12.5, .semibold)).foregroundStyle(th.fg2)
                Text(diag.detail)
                    .font(jakarta(13)).foregroundStyle(th.fg3)
                    .lineSpacing(3)
            }
            Spacer()
            if diag.level != .success {
                Btn(variant: .soft, size: .sm, label: "Resolve") {}
            }
        }
        .padding(.init(top: 16, leading: 20, bottom: 16, trailing: 20))
        .overlay(alignment: .bottom) { Rectangle().fill(th.border).frame(height: 1) }
    }
}

// ── Catalog ────────────────────────────────────────────────────────────────

struct CatalogView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.theme) private var th

    var body: some View {
        let products = state.snapshot.products
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .bottom) {
                sectionHeader("Catalog",
                              products.isEmpty
                              ? "No catalog connected to this account"
                              : "\(state.snapshot.account.brand) Store · 142 products · synced 12 min ago")
                Spacer()
                Btn(variant: .secondary, icon: "arrow.clockwise", label: "Sync feed") {}
            }

            if products.isEmpty {
                emptyState("shippingbox", "Catalog operations appear here once your account has a product catalog.")
            } else {
                HStack(spacing: 14) {
                    catStat("shippingbox", "142", "Products")
                    catStat("checkmark.circle", "138", "Approved")
                    catStat("exclamationmark.triangle", "4", "Issues")
                    catStat("megaphone", "61", "In active ads")
                }
                Card(pad: 0) {
                    VStack(spacing: 0) {
                        HStack {
                            Text("Top products by ad revenue")
                                .font(jakarta(15, .bold)).foregroundStyle(th.fg1)
                            Spacer()
                            Text("Product set: Best sellers")
                                .font(jakarta(12)).foregroundStyle(th.fg3)
                        }
                        .padding(.init(top: 16, leading: 20, bottom: 16, trailing: 20))
                        .overlay(alignment: .bottom) { Rectangle().fill(th.border).frame(height: 1) }
                        ForEach(products) { p in
                            ProductRow(product: p)
                        }
                    }
                }
            }
        }
    }

    private func catStat(_ icon: String, _ value: String, _ label: String) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 17))
                    .foregroundStyle(th.fg3)
                Text(value).font(jakarta(24, .extra)).foregroundStyle(th.fg1)
                Text(label).font(jakarta(12.5)).foregroundStyle(th.fg3)
            }
        }
    }
}

private struct ProductRow: View {
    var product: Product
    @Environment(\.theme) private var th

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 9)
                .fill(LinearGradient(colors: [product.tint, product.tint.opacity(0.55)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 1) {
                Text(product.name).font(jakarta(14, .semibold)).foregroundStyle(th.fg1)
                Text(Fmt.money(product.price)).font(jakarta(12)).foregroundStyle(th.fg4)
            }
            Spacer()
            Pill(status: product.stock == "In stock" ? .active : product.stock == "Out of stock" ? .error : .learning,
                 dot: false, text: product.stock)
            VStack(alignment: .trailing, spacing: 1) {
                Text("AD ROAS").font(jakarta(9.5)).kerning(0.4).foregroundStyle(th.fg4)
                Text(product.adRoas > 0 ? String(format: "%.1f×", product.adRoas) : "—")
                    .font(jakarta(14, .bold))
                    .foregroundStyle(product.adRoas >= 2 ? th.success : product.adRoas > 0 ? th.fg1 : th.fg4)
            }
            .frame(width: 80, alignment: .trailing)
        }
        .padding(.init(top: 13, leading: 20, bottom: 13, trailing: 20))
        .overlay(alignment: .bottom) { Rectangle().fill(th.border).frame(height: 1) }
        .hoverRow()
    }
}

// ── Datasets ───────────────────────────────────────────────────────────────

struct DatasetsView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.theme) private var th

    var body: some View {
        let events = state.snapshot.events
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .bottom) {
                sectionHeader("Datasets",
                              events.isEmpty
                              ? "No pixel events available for this account"
                              : "\(state.snapshot.account.brand) Pixel · \(state.snapshot.account.accountId.replacingOccurrences(of: "act_", with: "")) · receiving events")
                Spacer()
                if !events.isEmpty { Pill(status: .active, text: "Connected") }
            }

            if events.isEmpty {
                emptyState("cylinder.split.1x2", "Conversion datasets and pixel health appear here once events flow.")
            } else {
                HStack(spacing: 14) {
                    dataStat("waveform.path.ecg", "231 rb", "Events / 7d")
                    dataStat("checkmark.seal", "8.4 / 10", "Event match quality")
                    dataStat("person.2", "12", "Custom audiences")
                }
                Card(pad: 0) {
                    VStack(spacing: 0) {
                        Text("Conversion events · last 7 days")
                            .font(jakarta(15, .bold)).foregroundStyle(th.fg1)
                            .padding(.init(top: 16, leading: 20, bottom: 16, trailing: 20))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .overlay(alignment: .bottom) { Rectangle().fill(th.border).frame(height: 1) }
                        ForEach(events) { e in
                            EventRow(event: e)
                        }
                    }
                }
            }
        }
    }

    private func dataStat(_ icon: String, _ value: String, _ label: String) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 17))
                    .foregroundStyle(th.fg3)
                Text(value).font(jakarta(24, .extra)).foregroundStyle(th.fg1)
                Text(label).font(jakarta(12.5)).foregroundStyle(th.fg3)
            }
        }
    }
}

private struct EventRow: View {
    var event: DatasetEvent
    @Environment(\.theme) private var th

    var body: some View {
        let color = event.healthy ? th.success : th.warning
        HStack(spacing: 16) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(event.name).font(jakarta(14, .semibold)).foregroundStyle(th.fg1)
            Spacer()
            Text(Fmt.int(event.count))
                .font(jakarta(13.5, .semibold)).monospacedDigit()
                .foregroundStyle(th.fg1)
                .frame(width: 90, alignment: .trailing)
            HStack(spacing: 8) {
                Capsule().fill(th.bg3)
                    .frame(width: 110, height: 6)
                    .overlay(alignment: .leading) {
                        Capsule().fill(color).frame(width: 110 * event.matchRate / 100)
                    }
                Text(String(format: "%.1f%%", event.matchRate))
                    .font(jakarta(12, .semibold)).monospacedDigit()
                    .foregroundStyle(th.fg3)
                    .frame(width: 44, alignment: .trailing)
            }
        }
        .padding(.init(top: 15, leading: 20, bottom: 15, trailing: 20))
        .overlay(alignment: .bottom) { Rectangle().fill(th.border).frame(height: 1) }
        .hoverRow()
    }
}

// ── Shared helpers ─────────────────────────────────────────────────────────

private func sectionHeader(_ title: String, _ sub: String) -> some View {
    SectionHeaderView(title: title, sub: sub)
}

private struct SectionHeaderView: View {
    var title: String
    var sub: String
    @Environment(\.theme) private var th

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(jakarta(26, .extra)).kerning(-0.4).foregroundStyle(th.fg1)
            Text(sub).font(jakarta(13.5)).foregroundStyle(th.fg3)
        }
    }
}

private func emptyState(_ icon: String, _ text: String) -> some View {
    EmptyStateView(icon: icon, text: text)
}

private struct EmptyStateView: View {
    var icon: String
    var text: String
    @Environment(\.theme) private var th

    var body: some View {
        Card(pad: 40) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 30))
                    .foregroundStyle(th.fg4)
                Text(text)
                    .font(jakarta(13.5))
                    .foregroundStyle(th.fg3)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
