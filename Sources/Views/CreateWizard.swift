import SwiftUI
import UniformTypeIdentifiers

// 3-step create wizard → feeds the review sheet. Builds the full chain:
// campaign (budget) → ad set (optimization, countries, pixel, schedule)
// → creative (media upload, copy, CTA) → ad. Multiple assets/copy = DCO.

struct CreateWizard: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.theme) private var th
    @State private var step = 0
    @State private var draft = DraftCampaign()
    @State private var pages: [PageInfo] = []
    @State private var importerOpen = false
    @State private var aiSheet: AISheetMode?
    @ObservedObject private var ai = AIPrefs.shared

    private let steps = ["Objective", "Budget & audience", "Creative"]

    var body: some View {
        ZStack {
            Color(hex: 0x0E0F1A).opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { state.createOpen = false }

            VStack(spacing: 0) {
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

                HStack(spacing: 6) {
                    ForEach(0..<3) { i in
                        Capsule().fill(i <= step ? th.accent : th.bg4).frame(height: 4)
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
                    ScrollView { stepBody }.frame(maxHeight: 460)
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
            .frame(width: 640)
            .background(th.bg1)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.3), radius: 40, y: 16)
        }
        .onAppear {
            if let prefill = state.createPrefill {
                draft = prefill
                state.createPrefill = nil
            }
            Task {
                pages = (try? await state.backend.pages()) ?? []
                if draft.pageId.isEmpty, let first = pages.first { draft.pageId = first.id }
            }
        }
        .fileImporter(isPresented: $importerOpen,
                      allowedContentTypes: [.image, .movie],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                draft.media.append(contentsOf: urls)
            }
        }
        .sheet(item: $aiSheet) { mode in
            Group {
                switch mode {
                case .copy:
                    CopyGenSheet(draft: $draft) { aiSheet = nil }
                case .imageGen:
                    ImageGenSheet(draft: $draft) { aiSheet = nil }
                case .imageEdit(let url):
                    ImageEditSheet(source: url, draft: $draft) { aiSheet = nil }
                }
            }
            .environment(\.theme, th)
        }
    }

    // ── Step 1: objective ──────────────────────────────────────────────────

    private var objectiveStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            field("Campaign name") { WizardTextField(text: $draft.name) }
            Text("Objective").font(jakarta(13, .semibold)).foregroundStyle(th.fg1)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                ForEach(Objective.allCases) { obj in
                    let on = draft.objective == obj
                    Button {
                        draft.objective = obj
                        draft.optimization = .suggested(for: obj)
                    } label: {
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

    // ── Step 2: budget & audience ──────────────────────────────────────────

    private var budgetStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
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
                field("Countries", hint: "ISO codes, comma-separated") {
                    WizardTextField(text: $draft.countries)
                }
            }
            HStack(spacing: 12) {
                field("Optimization goal") {
                    WizardMenu(label: draft.optimization.label) {
                        ForEach(OptimizationGoal.allCases) { goal in
                            Button(goal.label) { draft.optimization = goal }
                        }
                    }
                }
                field("Conversion event") {
                    WizardMenu(label: draft.conversionEvent.label) {
                        ForEach(ConversionEvent.allCases) { event in
                            Button(event.label) { draft.conversionEvent = event }
                        }
                    }
                }
            }
            field("Bid cap", hint: "max cost per result · required by Meta") {
                HStack(spacing: 0) {
                    Text(Fmt.currency == "IDR" ? "Rp" : Fmt.currency)
                        .font(jakarta(14))
                        .foregroundStyle(th.fg3)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(th.bg3)
                    TextField("", value: $draft.bidAmount, format: .number)
                        .textFieldStyle(.plain)
                        .font(jakarta(14))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }
                .background(th.bg1)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(th.borderStrong, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            field("Pixel", hint: "conversion tracking") {
                WizardMenu(label: pixelLabel) {
                    Button("None") { draft.pixelId = "" }
                    ForEach(state.snapshot.pixels) { pixel in
                        Button("\(pixel.name) · \(pixel.id)") { draft.pixelId = pixel.id }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 9) {
                    PacerSwitch(on: draft.schedule) { draft.schedule = $0 }
                    Text("Schedule").font(jakarta(13, .semibold)).foregroundStyle(th.fg1)
                    Text("· start and end the ad set automatically")
                        .font(jakarta(12.5)).foregroundStyle(th.fg3)
                }
                if draft.schedule {
                    HStack(spacing: 12) {
                        DatePicker("Start", selection: $draft.startDate, displayedComponents: [.date, .hourAndMinute])
                        DatePicker("End", selection: $draft.endDate, in: draft.startDate..., displayedComponents: [.date, .hourAndMinute])
                    }
                    .font(jakarta(12.5))
                    .datePickerStyle(.compact)
                }
            }
        }
    }

    private var pixelLabel: String {
        if draft.pixelId.isEmpty { return "None" }
        return state.snapshot.pixels.first(where: { $0.id == draft.pixelId })
            .map { "\($0.name) · \($0.id)" } ?? draft.pixelId
    }

    // ── Step 3: creative ───────────────────────────────────────────────────

    private var creativeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                field("Ad name") { WizardTextField(text: $draft.adName) }
                field("Facebook Page", hint: "the ad's identity") {
                    WizardMenu(label: pageLabel) {
                        ForEach(pages) { page in
                            Button("\(page.name) · \(page.id)") { draft.pageId = page.id }
                        }
                        if pages.isEmpty {
                            Button("No pages found for this token") {}
                        }
                    }
                }
            }

            field("Media", hint: "images or videos · 2+ enables dynamic creative") {
                VStack(alignment: .leading, spacing: 8) {
                    MediaDropZone(media: $draft.media,
                                  onEdit: ai.isActive ? { url in aiSheet = .imageEdit(url) } : nil) {
                        importerOpen = true
                    }
                    if ai.isActive {
                        Btn(variant: .soft, size: .sm, icon: "sparkles", label: "Generate image…") {
                            aiSheet = .imageGen
                        }
                    }
                }
            }

            field("Headline") {
                HStack(spacing: 8) {
                    WizardTextField(text: $draft.headline)
                    if ai.isActive {
                        Btn(variant: .soft, size: .sm, icon: "sparkles", label: "Generate copy…") {
                            aiSheet = .copy
                        }
                    }
                }
            }
            field("Primary text") {
                TextEditor(text: $draft.text)
                    .font(jakarta(14))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(height: 64)
                    .background(th.bg1)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(th.borderStrong, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            HStack(spacing: 12) {
                field("Destination URL") { WizardTextField(text: $draft.linkURL) }
                field("Call to action") {
                    WizardMenu(label: draft.cta.label) {
                        ForEach(CTAType.allCases) { cta in
                            Button(cta.label) { draft.cta = cta }
                        }
                    }
                }
            }

            if draft.media.count > 1 || !draft.extraHeadlines.isEmpty || !draft.extraTexts.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 7) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(th.accent)
                        Text("Dynamic creative variants")
                            .font(jakarta(13, .bold)).foregroundStyle(th.fg1)
                        Text("· Meta tests combinations automatically")
                            .font(jakarta(12)).foregroundStyle(th.fg3)
                    }
                    HStack(alignment: .top, spacing: 12) {
                        field("Extra headlines", hint: "one per line") {
                            variantEditor($draft.extraHeadlines)
                        }
                        field("Extra primary texts", hint: "one per line") {
                            variantEditor($draft.extraTexts)
                        }
                    }
                }
                .padding(14)
                .background(th.accentSoft.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                Btn(variant: .ghost, size: .sm, icon: "sparkles", label: "Add copy variants (dynamic creative)") {
                    draft.extraHeadlines = " "
                }
            }
        }
    }

    private func variantEditor(_ text: Binding<String>) -> some View {
        TextEditor(text: text)
            .font(jakarta(13))
            .scrollContentBackground(.hidden)
            .padding(6)
            .frame(height: 58)
            .background(th.bg1)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(th.borderStrong, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var pageLabel: String {
        if draft.pageId.isEmpty { return pages.isEmpty ? "Loading pages…" : "Choose a page" }
        return pages.first(where: { $0.id == draft.pageId })?.name ?? draft.pageId
    }

    private func field<C: View>(_ label: String, hint: String? = nil,
                                @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            (Text(label).font(jakarta(13, .semibold)).foregroundStyle(th.fg1)
             + Text(hint.map { "  \($0)" } ?? "").font(jakarta(12)).foregroundStyle(th.fg4))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// ── Media drop zone ────────────────────────────────────────────────────────

struct MediaDropZone: View {
    @Binding var media: [URL]
    var onEdit: ((URL) -> Void)?
    var browse: () -> Void
    @Environment(\.theme) private var th
    @State private var hovering = false

    private let videoExts = ["mp4", "mov", "avi", "mkv", "wmv"]
    private let imageExts = ["jpg", "jpeg", "png", "gif", "bmp", "webp"]

    var body: some View {
        VStack(spacing: 10) {
            if media.isEmpty {
                VStack(spacing: 7) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 24))
                        .foregroundStyle(hovering ? th.accent : th.fg4)
                    Text("Drop images or videos here, or")
                        .font(jakarta(12.5)).foregroundStyle(th.fg3)
                    Btn(variant: .secondary, size: .sm, label: "Browse…", action: browse)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(media.enumerated()), id: \.offset) { i, url in
                        HStack(spacing: 10) {
                            Image(systemName: videoExts.contains(url.pathExtension.lowercased()) ? "play.rectangle" : "photo")
                                .font(.system(size: 13))
                                .foregroundStyle(th.accent)
                                .frame(width: 18)
                            Text(url.lastPathComponent)
                                .font(jakarta(12.5, .medium))
                                .foregroundStyle(th.fg1)
                                .lineLimit(1)
                            Spacer()
                            if let onEdit, imageExts.contains(url.pathExtension.lowercased()) {
                                Button {
                                    onEdit(url)
                                } label: {
                                    HStack(spacing: 3) {
                                        Image(systemName: "sparkles").font(.system(size: 10, weight: .semibold))
                                        Text("Edit").font(jakarta(11, .semibold))
                                    }
                                    .foregroundStyle(th.accent)
                                }
                                .buttonStyle(.plain)
                            }
                            Button {
                                media.remove(at: i)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(th.fg4)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(th.bg1)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    Btn(variant: .ghost, size: .sm, icon: "plus", label: "Add more", action: browse)
                }
                .padding(10)
            }
        }
        .frame(maxWidth: .infinity)
        .background(hovering ? th.accentSoft : th.bg2)
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(hovering ? th.accent : th.borderStrong,
                          style: StrokeStyle(lineWidth: 1.5, dash: media.isEmpty ? [6, 5] : []))
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .dropDestination(for: URL.self) { urls, _ in
            let exts = ["jpg", "jpeg", "png", "gif", "bmp", "webp"] + videoExts
            let valid = urls.filter { exts.contains($0.pathExtension.lowercased()) }
            media.append(contentsOf: valid)
            return !valid.isEmpty
        } isTargeted: { hovering = $0 }
    }
}

// ── Shared field chrome ────────────────────────────────────────────────────

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

struct WizardMenu<Content: View>: View {
    var label: String
    @ViewBuilder var content: Content
    @Environment(\.theme) private var th

    var body: some View {
        Menu {
            content
        } label: {
            HStack {
                Text(label).font(jakarta(14)).foregroundStyle(th.fg1).lineLimit(1)
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
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }
}
