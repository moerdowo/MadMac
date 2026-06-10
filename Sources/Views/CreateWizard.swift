import SwiftUI

// 3-step create wizard → feeds the review sheet (create.jsx).

struct CreateWizard: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.theme) private var th
    @State private var step = 0
    @State private var draft = DraftCampaign()

    private let steps = ["Objective", "Budget & audience", "Creative"]

    var body: some View {
        ZStack {
            Color(hex: 0x0E0F1A).opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { state.createOpen = false }

            VStack(spacing: 0) {
                // header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("New campaign").font(jakarta(18, .extra)).foregroundStyle(th.fg1)
                        Text("Step \(step + 1) of 3 · \(steps[step])")
                            .font(jakarta(12.5)).foregroundStyle(th.fg3)
                    }
                    Spacer()
                    IconButton(icon: "xmark", size: 32, bordered: false) { state.createOpen = false }
                }
                .padding(.init(top: 20, leading: 24, bottom: 20, trailing: 24))
                .overlay(alignment: .bottom) { Rectangle().fill(th.border).frame(height: 1) }

                // progress
                HStack(spacing: 6) {
                    ForEach(0..<3) { i in
                        Capsule()
                            .fill(i <= step ? th.accent : th.bg4)
                            .frame(height: 4)
                    }
                }
                .padding(.init(top: 14, leading: 24, bottom: 0, trailing: 24))
                .animation(.easeOut(duration: 0.2), value: step)

                let stepBody = VStack(alignment: .leading, spacing: 16) {
                    switch step {
                    case 0: objectiveStep
                    case 1: budgetStep
                    default: creativeStep
                    }
                }
                .padding(24)
                if SnapshotRunner.isActive {
                    stepBody
                } else {
                    ScrollView { stepBody }.frame(maxHeight: 420)
                }

                HStack {
                    Btn(variant: .ghost, label: step > 0 ? "Back" : "Cancel") {
                        if step > 0 { step -= 1 } else { state.createOpen = false }
                    }
                    Spacer()
                    Btn(variant: .primary,
                        icon: step == 2 ? "checklist" : "arrow.right",
                        label: step == 2 ? "Review launch plan" : "Continue") {
                        if step < 2 { step += 1 }
                        else {
                            state.draft = draft
                            state.createOpen = false
                            state.reviewOpen = true
                        }
                    }
                }
                .padding(.init(top: 16, leading: 24, bottom: 16, trailing: 24))
                .overlay(alignment: .top) { Rectangle().fill(th.border).frame(height: 1) }
            }
            .frame(width: 600)
            .background(th.bg1)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.3), radius: 40, y: 16)
        }
    }

    // ── Steps ──────────────────────────────────────────────────────────────

    private var objectiveStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            field("Campaign name") {
                WizardTextField(text: $draft.name)
            }
            Text("Objective").font(jakarta(13, .semibold)).foregroundStyle(th.fg1)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                ForEach(Objective.allCases) { obj in
                    let on = draft.objective == obj
                    Button { draft.objective = obj } label: {
                        HStack(alignment: .top, spacing: 11) {
                            Image(systemName: obj.icon)
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(on ? th.accent : th.fg3)
                                .padding(.top, 1)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(obj.rawValue)
                                    .font(jakarta(14, .bold))
                                    .foregroundStyle(on ? th.accent : th.fg1)
                                Text(obj.blurb)
                                    .font(jakarta(11.5))
                                    .foregroundStyle(th.fg3)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(14)
                        .background(on ? th.accentSoft : th.bg1)
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .stroke(on ? th.accent : th.borderStrong, lineWidth: on ? 1.5 : 1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var budgetStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            field("Daily budget", hint: Fmt.currency) {
                HStack(spacing: 0) {
                    Text(Fmt.currency == "IDR" ? "Rp" : Fmt.currency)
                        .font(jakarta(14))
                        .foregroundStyle(th.fg3)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(th.bg3)
                    TextField("", value: $draft.daily, format: .number)
                        .textFieldStyle(.plain)
                        .font(jakarta(14))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }
                .background(th.bg1)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(th.borderStrong, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            field("Audience") {
                WizardPicker(selection: $draft.audience,
                             options: ["Advantage+ audience", "Lookalike 1% — Purchasers",
                                       "Retargeting — ATC 14d", "Custom — interests"])
            }
            HStack(spacing: 12) {
                field("Location") { WizardTextField(text: $draft.geo) }
                field("Age range") { WizardTextField(text: $draft.age) }
            }
        }
    }

    private var creativeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            field("Ad name") { WizardTextField(text: $draft.adName) }
            field("Format") {
                Segmented(options: [(AdFormat.video, "Video"), (.image, "Image"),
                                    (.carousel, "Carousel"), (.collection, "Collection")],
                          value: $draft.format)
            }
            field("Primary text") {
                TextEditor(text: $draft.text)
                    .font(jakarta(14))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(height: 80)
                    .background(th.bg1)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(th.borderStrong, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func field<C: View>(_ label: String, hint: String? = nil,
                                @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            (Text(label).font(jakarta(13, .semibold)).foregroundStyle(th.fg1)
             + Text(hint.map { "  \($0)" } ?? "").font(jakarta(13)).foregroundStyle(th.fg4))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WizardTextField: View {
    @Binding var text: String
    @Environment(\.theme) private var th

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .font(jakarta(14))
            .foregroundStyle(th.fg1)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(th.bg1)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(th.borderStrong, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct WizardPicker: View {
    @Binding var selection: String
    var options: [String]
    @Environment(\.theme) private var th

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { opt in
                Button(opt) { selection = opt }
            }
        } label: {
            HStack {
                Text(selection).font(jakarta(14)).foregroundStyle(th.fg1)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11))
                    .foregroundStyle(th.fg4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(th.bg1)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(th.borderStrong, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }
}
