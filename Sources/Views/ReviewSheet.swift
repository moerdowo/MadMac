import SwiftUI

// The hero: spec-review / approve-to-launch sheet.
// Nothing touches the account until Approve.

struct ReviewSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.theme) private var th
    @State private var launchLive = false
    @State private var policyReport: PolicyReport?
    @State private var policyChecking = false

    var body: some View {
        let plan = state.buildPlan(launchLive: launchLive)
        let goLive = plan.statusChanges.filter { $0.to == .active }.count

        ZStack {
            Color(hex: 0x0E0F1A).opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { if !state.isApplying { state.reviewOpen = false } }

            VStack(spacing: 0) {
                // header
                HStack(spacing: 11) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(th.accentSoft)
                        .frame(width: 38, height: 38)
                        .overlay(Image(systemName: "checklist")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(th.accent))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Review launch plan")
                            .font(jakarta(19, .extra)).kerning(-0.2)
                            .foregroundStyle(th.fg1)
                        Text("\(plan.count) change\(plan.count == 1 ? "" : "s") staged · nothing is live until you approve")
                            .font(jakarta(12.5)).foregroundStyle(th.fg3)
                    }
                    Spacer()
                    IconButton(icon: "xmark", size: 32, bordered: false) { state.reviewOpen = false }
                }
                .padding(.init(top: 22, leading: 26, bottom: 22, trailing: 26))
                .background(th.bg1)
                .overlay(alignment: .bottom) { Rectangle().fill(th.border).frame(height: 1) }

                let body = VStack(alignment: .leading, spacing: 16) {
                    if let draft = state.draft {
                        createSpec(draft)
                        policySection(draft)
                    }
                    if !plan.statusChanges.isEmpty {
                        statusSection(plan.statusChanges)
                    }
                    if !plan.budgetChanges.isEmpty {
                        budgetSection(plan.budgetChanges)
                    }
                    if !plan.deletes.isEmpty {
                        deleteSection(plan.deletes)
                    }
                    if goLive > 0 || state.draft != nil {
                        warning
                    }
                }
                .padding(.init(top: 18, leading: 26, bottom: 18, trailing: 26))
                if SnapshotRunner.isActive {
                    body.background(th.bg2)
                } else {
                    ScrollView { body }
                        .frame(maxHeight: 460)
                        .background(th.bg2)
                }

                // footer
                HStack(spacing: 16) {
                    if state.draft != nil {
                        HStack(spacing: 9) {
                            PacerSwitch(on: launchLive) { launchLive = $0 }
                            (Text("Launch active now").font(jakarta(13, .bold)).foregroundStyle(th.fg1)
                             + Text(" · otherwise saved paused").font(jakarta(13)).foregroundStyle(th.fg3))
                        }
                    } else {
                        Text(footerSummary(plan, goLive: goLive))
                            .font(jakarta(12.5)).foregroundStyle(th.fg3)
                    }
                    Spacer()
                    Btn(variant: .ghost, label: "Cancel") { state.reviewOpen = false }
                    if state.isApplying {
                        ProgressView().controlSize(.small)
                    }
                    Btn(variant: .primary, icon: "paperplane.fill",
                        label: state.draft != nil && !launchLive ? "Approve & save paused" : "Approve & launch",
                        disabled: plan.count == 0 || state.isApplying) {
                        Task { await state.approve(launchLive: launchLive) }
                    }
                }
                .padding(.init(top: 16, leading: 26, bottom: 16, trailing: 26))
                .background(th.bg1)
                .overlay(alignment: .top) { Rectangle().fill(th.border).frame(height: 1) }
            }
            .frame(width: 680)
            .background(th.bg2)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.3), radius: 40, y: 16)
        }
    }

    private func footerSummary(_ plan: ChangePlan, goLive: Int) -> String {
        var parts: [String] = []
        if !plan.statusChanges.isEmpty {
            parts.append("\(goLive) going live · \(plan.statusChanges.count - goLive) pausing")
        }
        if !plan.budgetChanges.isEmpty { parts.append("\(plan.budgetChanges.count) budget edit\(plan.budgetChanges.count == 1 ? "" : "s")") }
        if !plan.deletes.isEmpty { parts.append("\(plan.deletes.count) deletion\(plan.deletes.count == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }

    // ── Create spec tree ───────────────────────────────────────────────────

    private func createSpec(_ draft: DraftCampaign) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Create")
            VStack(spacing: 0) {
                SpecNode(level: "Campaign", icon: "folder", name: draft.name,
                         pill: .draft, indent: 0, last: false) {
                    SpecLine(icon: "target", label: "Objective", value: draft.objective.rawValue)
                    SpecLine(icon: "wallet.pass", label: "Daily budget", value: Fmt.money(draft.daily))
                }
                SpecNode(level: "Ad set", icon: "person.2", name: draft.adsetName,
                         indent: 1, last: false) {
                    SpecLine(icon: "scope", label: "Optimize for", value: draft.optimization.label)
                    SpecLine(icon: "gauge.with.needle", label: "Bid cap", value: Fmt.money(draft.bidAmount) + " / result")
                    SpecLine(icon: "mappin.and.ellipse", label: "Countries", value: draft.countries)
                    if !draft.pixelId.isEmpty {
                        SpecLine(icon: "dot.radiowaves.up.forward", label: "Pixel",
                                 value: "\(draft.pixelId) · \(draft.conversionEvent.label)")
                    }
                    if draft.schedule {
                        SpecLine(icon: "calendar", label: "Schedule",
                                 value: "\(draft.startDate.formatted(date: .abbreviated, time: .shortened)) → \(draft.endDate.formatted(date: .abbreviated, time: .shortened))")
                    }
                }
                SpecNode(level: "Ad", icon: "photo", name: draft.adName,
                         indent: 2, last: true) {
                    if draft.media.isEmpty {
                        SpecLine(icon: "exclamationmark.triangle", label: "Media",
                                 value: "none — ad will be skipped")
                    } else {
                        SpecLine(icon: "photo.on.rectangle", label: "Media",
                                 value: draft.media.map(\.lastPathComponent).joined(separator: ", "))
                    }
                    if draft.isDCO {
                        SpecLine(icon: "sparkles", label: "Dynamic",
                                 value: "\(draft.media.count) assets · \(draft.headlines.count) headlines · \(draft.texts.count) texts")
                    }
                    if let headline = draft.headlines.first, !headline.isEmpty {
                        SpecLine(icon: "textformat.size", label: "Headline", value: headline)
                    }
                    if !draft.linkURL.isEmpty {
                        SpecLine(icon: "link", label: "Link", value: draft.linkURL)
                    }
                    SpecLine(icon: "hand.tap", label: "CTA", value: draft.cta.label)
                    if let text = draft.texts.first, !text.isEmpty {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "textformat")
                                .font(.system(size: 12))
                                .foregroundStyle(th.fg4)
                                .frame(width: 16)
                            Text("Primary text")
                                .font(jakarta(12.5)).foregroundStyle(th.fg3)
                                .frame(width: 96, alignment: .leading)
                            Text("\u{201C}\(text)\u{201D}")
                                .font(jakarta(12.5)).italic()
                                .foregroundStyle(th.fg2)
                                .lineSpacing(2)
                        }
                        .padding(.vertical, 7)
                    }
                }
            }
            .background(th.bg1)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(th.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    // ── Policy pre-check (AI, advisory only) ───────────────────────────────

    @ViewBuilder private func policySection(_ draft: DraftCampaign) -> some View {
        let hasCopy = !(draft.headlines.first ?? "").isEmpty || !(draft.texts.first ?? "").isEmpty
        if AIPrefs.shared.isActive && hasCopy {
            VStack(alignment: .leading, spacing: 8) {
                if policyChecking {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.mini)
                        Text("Checking copy against Meta ad policies…")
                            .font(jakarta(12)).foregroundStyle(th.fg3)
                    }
                } else if let report = policyReport {
                    if report.flags.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.shield")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(th.success)
                            Text("Policy check passed — no rejection risks found in the copy.")
                                .font(jakarta(12.5)).foregroundStyle(th.fg2)
                        }
                    } else {
                        sectionLabel("Policy risks (\(report.risk))")
                        ForEach(report.flags) { flag in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "exclamationmark.bubble")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(report.risk == "high" ? th.danger : th.warning)
                                        .padding(.top, 1)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("\u{201C}\(flag.text)\u{201D} — \(flag.reason)")
                                            .font(jakarta(12.5, .semibold)).foregroundStyle(th.fg1)
                                        (Text("Try: ").font(jakarta(12)).foregroundStyle(th.fg3)
                                         + Text(flag.suggestion).font(jakarta(12)).italic().foregroundStyle(th.fg2))
                                    }
                                }
                            }
                            .padding(.init(top: 10, leading: 12, bottom: 10, trailing: 12))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(report.risk == "high" ? th.danger100 : th.warning100)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                } else if !AIPrefs.shared.autoPolicyCheck {
                    Btn(variant: .ghost, size: .sm, icon: "checkmark.shield", label: "Check policy risks") {
                        runPolicyCheck(draft)
                    }
                }
            }
            .task(id: draft.headline + draft.text) {
                if AIPrefs.shared.autoPolicyCheck && policyReport == nil && !policyChecking {
                    runPolicyCheck(draft)
                }
            }
        }
    }

    private func runPolicyCheck(_ draft: DraftCampaign) {
        policyChecking = true
        Task {
            policyReport = try? await AIService.policyCheck(
                headline: draft.headlines.first ?? "",
                text: draft.texts.first ?? "",
                objective: draft.objective.rawValue)
            policyChecking = false
        }
    }

    // ── Status / budget / delete sections ──────────────────────────────────

    private func statusSection(_ changes: [StagedChange]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Status changes")
            ForEach(changes) { change in
                changeRow(kind: change.kind, name: change.name) {
                    Pill(status: PillStatus(change.base), dot: false)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(th.fg4)
                    Pill(status: PillStatus(change.to), dot: false)
                }
            }
        }
    }

    private func budgetSection(_ changes: [StagedBudget]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Budget changes")
            ForEach(changes) { change in
                changeRow(kind: change.kind, name: change.name) {
                    Text(Fmt.money(change.from, compact: true))
                        .font(jakarta(12.5, .semibold)).monospacedDigit()
                        .foregroundStyle(th.fg3)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(th.fg4)
                    Text(Fmt.money(change.to, compact: true) + "/day")
                        .font(jakarta(12.5, .bold)).monospacedDigit()
                        .foregroundStyle(change.to > change.from ? th.warning : th.fg1)
                }
            }
        }
    }

    private func deleteSection(_ deletes: [StagedDelete]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Delete")
            ForEach(deletes) { del in
                changeRow(kind: del.kind, name: del.name) {
                    Text("Deleted permanently")
                        .font(jakarta(12, .bold))
                        .foregroundStyle(th.danger)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(th.danger100))
                }
            }
        }
    }

    private func changeRow<Trailing: View>(kind: EntityKind, name: String,
                                           @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            Text(kind.rawValue.uppercased())
                .font(jakarta(10.5, .bold)).kerning(0.3)
                .foregroundStyle(th.fg4)
                .frame(width: 64, alignment: .leading)
            Text(name)
                .font(jakarta(13.5, .semibold))
                .foregroundStyle(th.fg1)
                .lineLimit(1)
            Spacer()
            trailing()
        }
        .padding(.init(top: 12, leading: 14, bottom: 12, trailing: 14))
        .background(th.bg1)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(th.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(jakarta(11.5, .bold)).kerning(0.6)
            .foregroundStyle(th.fg3)
    }

    private var warning: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "exclamationmark.shield")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(th.warning)
            (Text("Going live will start spending real budget. Keep volume light — Meta's systems flag bursts of rapid automated edits. Items left as ")
             + Text("paused").bold()
             + Text(" are saved but won't deliver."))
                .font(jakarta(12.5))
                .foregroundStyle(th.fg2)
                .lineSpacing(3)
        }
        .padding(.init(top: 13, leading: 15, bottom: 13, trailing: 15))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(th.warning100)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(th.warning.opacity(0.25), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// ── Spec node / line ───────────────────────────────────────────────────────

private struct SpecNode<Content: View>: View {
    var level: String
    var icon: String
    var name: String
    var pill: PillStatus?
    var indent: Int
    var last: Bool
    @ViewBuilder var content: Content
    @Environment(\.theme) private var th

    init(level: String, icon: String, name: String, pill: PillStatus? = nil,
         indent: Int, last: Bool, @ViewBuilder content: () -> Content) {
        self.level = level
        self.icon = icon
        self.name = name
        self.pill = pill
        self.indent = indent
        self.last = last
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(th.accentSoft)
                .frame(width: 30, height: 30)
                .overlay(Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(th.accent))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(level.uppercased())
                        .font(jakarta(10, .bold)).kerning(0.4)
                        .foregroundStyle(th.fg4)
                    if let pill { Pill(status: pill, dot: false) }
                }
                Text(name).font(jakarta(14, .bold)).foregroundStyle(th.fg1)
                VStack(alignment: .leading, spacing: 0) { content }
                    .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(.init(top: 14, leading: 16 + CGFloat(indent) * 22, bottom: 14, trailing: 16))
        .overlay(alignment: .bottom) {
            if !last { Rectangle().fill(th.border).frame(height: 1) }
        }
    }
}

private struct SpecLine: View {
    var icon: String
    var label: String
    var value: String
    @Environment(\.theme) private var th

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(th.fg4)
                .frame(width: 16)
            Text(label)
                .font(jakarta(12.5)).foregroundStyle(th.fg3)
                .frame(width: 96, alignment: .leading)
            Text(value)
                .font(jakarta(13, .semibold)).foregroundStyle(th.fg1)
                .lineLimit(2)
        }
        .padding(.vertical, 7)
    }
}
