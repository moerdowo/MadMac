import SwiftUI

// Creative Studio sheets used from the wizard: copy generation, image
// generation, image editing. All results land in the DraftCampaign only.

enum AISheetMode: Identifiable {
    case copy
    case imageGen
    case imageEdit(URL)

    var id: String {
        switch self {
        case .copy: return "copy"
        case .imageGen: return "imageGen"
        case .imageEdit(let url): return "edit-\(url.lastPathComponent)"
        }
    }
}

// ── 1a. Copywriter ─────────────────────────────────────────────────────────

struct CopyGenSheet: View {
    @Binding var draft: DraftCampaign
    var onClose: () -> Void
    @Environment(\.theme) private var th
    @State private var product: String
    @State private var tone = "Casual"
    @State private var language = "Indonesian"
    @State private var busy = false
    @State private var error: String?
    @State private var result: CopySet?
    @State private var pickedHeadline = 0
    @State private var pickedText = 0

    init(draft: Binding<DraftCampaign>, onClose: @escaping () -> Void) {
        _draft = draft
        self.onClose = onClose
        let d = draft.wrappedValue
        _product = State(initialValue: d.linkURL.isEmpty ? d.name : "\(d.name) — \(d.linkURL)")
    }

    var body: some View {
        AISheetChrome(title: "Generate ad copy", subtitle: "5 headlines + 5 primary texts → dynamic creative",
                      onClose: onClose) {
            VStack(alignment: .leading, spacing: 14) {
                aiField("Product / offer") {
                    TextEditor(text: $product)
                        .font(jakarta(13))
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .frame(height: 54)
                        .background(th.bg1)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(th.borderStrong, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                HStack(spacing: 12) {
                    aiField("Tone") {
                        Segmented(options: [("Casual", "Casual"), ("Professional", "Professional"), ("Playful", "Playful")], value: $tone)
                    }
                    aiField("Language") {
                        Segmented(options: [("Indonesian", "ID"), ("English", "EN"), ("Both", "Both")], value: $language)
                    }
                }

                if let result {
                    aiField("Headline — pick one") {
                        chipGrid(result.headlines, picked: $pickedHeadline)
                    }
                    aiField("Primary text — pick one") {
                        chipGrid(result.texts, picked: $pickedText)
                    }
                }
                if let error {
                    Text(error).font(jakarta(12, .medium)).foregroundStyle(th.danger)
                }
            }
        } footer: {
            if busy { ProgressView().controlSize(.small) }
            Btn(variant: result == nil ? .primary : .secondary,
                icon: "sparkles", label: result == nil ? "Generate" : "Regenerate",
                disabled: product.isEmpty || busy) {
                run()
            }
            if let result {
                Btn(variant: .primary, icon: "checkmark", label: "Use this copy") {
                    draft.headline = result.headlines[safe: pickedHeadline] ?? result.headlines[0]
                    draft.text = result.texts[safe: pickedText] ?? result.texts[0]
                    draft.extraHeadlines = result.headlines.enumerated()
                        .filter { $0.offset != pickedHeadline }.map(\.element)
                        .joined(separator: "\n")
                    draft.extraTexts = result.texts.enumerated()
                        .filter { $0.offset != pickedText }.map(\.element)
                        .joined(separator: "\n")
                    onClose()
                }
            }
        }
    }

    private func run() {
        busy = true
        error = nil
        Task {
            do {
                result = try await AIService.generateCopy(
                    product: product, tone: tone, language: language,
                    objective: draft.objective.rawValue)
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }

    private func chipGrid(_ items: [String], picked: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                Button {
                    picked.wrappedValue = i
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: picked.wrappedValue == i ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 13))
                            .foregroundStyle(picked.wrappedValue == i ? th.accent : th.fg4)
                            .padding(.top, 1)
                        Text(item)
                            .font(jakarta(12.5))
                            .foregroundStyle(th.fg1)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(picked.wrappedValue == i ? th.accentSoft : th.bg1)
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(picked.wrappedValue == i ? th.accent : th.border, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// ── 1b. Image generation ───────────────────────────────────────────────────

struct ImageGenSheet: View {
    @Binding var draft: DraftCampaign
    var onClose: () -> Void
    @Environment(\.theme) private var th
    @State private var prompt: String
    @State private var size = "1024x1024"
    @State private var count = 1
    @State private var busy = false
    @State private var error: String?
    @State private var results: [URL] = []
    @State private var selected: Set<URL> = []

    init(draft: Binding<DraftCampaign>, onClose: @escaping () -> Void) {
        _draft = draft
        self.onClose = onClose
        let d = draft.wrappedValue
        _prompt = State(initialValue: d.headline.isEmpty
            ? "High-converting Meta ad image for: \(d.name)"
            : "Meta ad image: \(d.headline). \(d.text)")
    }

    var body: some View {
        AISheetChrome(title: "Generate ad images",
                      subtitle: "gpt-image-1 · \(AIPrefs.shared.imageQuality.costHint)",
                      onClose: onClose) {
            VStack(alignment: .leading, spacing: 14) {
                aiField("Prompt") {
                    TextEditor(text: $prompt)
                        .font(jakarta(13))
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .frame(height: 64)
                        .background(th.bg1)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(th.borderStrong, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                HStack(spacing: 12) {
                    aiField("Aspect") {
                        Segmented(options: [("1024x1024", "1:1 Feed"), ("1536x1024", "Landscape"), ("1024x1536", "Portrait/Reels")], value: $size)
                    }
                    aiField("Count") {
                        Segmented(options: [(1, "1"), (2, "2"), (4, "4")], value: $count)
                    }
                }
                if !results.isEmpty {
                    aiField("Results — select to add") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
                            ForEach(results, id: \.self) { url in
                                Button {
                                    if selected.contains(url) { selected.remove(url) }
                                    else { selected.insert(url) }
                                } label: {
                                    ZStack(alignment: .topTrailing) {
                                        AsyncImage(url: url) { image in
                                            image.resizable().scaledToFill()
                                        } placeholder: { th.bg3 }
                                        .frame(width: 130, height: 130)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                        Image(systemName: selected.contains(url) ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 18))
                                            .foregroundStyle(selected.contains(url) ? th.accent : .white)
                                            .shadow(radius: 2)
                                            .padding(6)
                                    }
                                    .overlay(RoundedRectangle(cornerRadius: 10)
                                        .stroke(selected.contains(url) ? th.accent : .clear, lineWidth: 2))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                if let error {
                    Text(error).font(jakarta(12, .medium)).foregroundStyle(th.danger)
                }
            }
        } footer: {
            if busy {
                ProgressView().controlSize(.small)
                Text("Generating…").font(jakarta(12)).foregroundStyle(th.fg3)
            }
            Btn(variant: results.isEmpty ? .primary : .secondary,
                icon: "sparkles", label: results.isEmpty ? "Generate" : "Generate more",
                disabled: prompt.isEmpty || busy) {
                run()
            }
            if !selected.isEmpty {
                Btn(variant: .primary, icon: "plus", label: "Add \(selected.count) to media") {
                    draft.media.append(contentsOf: results.filter { selected.contains($0) })
                    onClose()
                }
            }
        }
    }

    private func run() {
        busy = true
        error = nil
        Task {
            do {
                let urls = try await AIService.generateImages(prompt: prompt, size: size, count: count)
                results.append(contentsOf: urls)
                selected.formUnion(urls)
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }
}

// ── 1c. Image editing ──────────────────────────────────────────────────────

struct ImageEditSheet: View {
    var source: URL
    @Binding var draft: DraftCampaign
    var onClose: () -> Void
    @Environment(\.theme) private var th
    @State private var instruction = ""
    @State private var busy = false
    @State private var error: String?
    @State private var result: URL?

    var body: some View {
        AISheetChrome(title: "Edit image",
                      subtitle: "\(source.lastPathComponent) · \(AIPrefs.shared.imageQuality.costHint)",
                      onClose: onClose) {
            VStack(alignment: .leading, spacing: 14) {
                aiField("Instruction") {
                    WizardTextField(text: $instruction)
                }
                Text("Examples: “remove the text overlay” · “swap the background to a marble counter” · “extend to portrait for Reels”")
                    .font(jakarta(11)).foregroundStyle(th.fg4)
                HStack(spacing: 14) {
                    VStack(spacing: 5) {
                        AsyncImage(url: source) { $0.resizable().scaledToFit() } placeholder: { th.bg3 }
                            .frame(maxWidth: 190, maxHeight: 190)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        Text("Original").font(jakarta(10.5)).foregroundStyle(th.fg4)
                    }
                    if let result {
                        Image(systemName: "arrow.right")
                            .foregroundStyle(th.fg4)
                        VStack(spacing: 5) {
                            AsyncImage(url: result) { $0.resizable().scaledToFit() } placeholder: { th.bg3 }
                                .frame(maxWidth: 190, maxHeight: 190)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(th.accent, lineWidth: 2))
                            Text("Edited").font(jakarta(10.5, .semibold)).foregroundStyle(th.accent)
                        }
                    }
                }
                if let error {
                    Text(error).font(jakarta(12, .medium)).foregroundStyle(th.danger)
                }
            }
        } footer: {
            if busy {
                ProgressView().controlSize(.small)
                Text("Editing…").font(jakarta(12)).foregroundStyle(th.fg3)
            }
            Btn(variant: result == nil ? .primary : .secondary,
                icon: "sparkles", label: result == nil ? "Edit" : "Try again",
                disabled: instruction.isEmpty || busy) {
                run()
            }
            if let result {
                Btn(variant: .primary, icon: "plus", label: "Add as variant") {
                    draft.media.append(result)
                    onClose()
                }
            }
        }
    }

    private func run() {
        busy = true
        error = nil
        Task {
            do {
                result = try await AIService.editImage(source, instruction: instruction)
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }
}

// ── Shared chrome ──────────────────────────────────────────────────────────

struct AISheetChrome<Content: View, Footer: View>: View {
    var title: String
    var subtitle: String
    var onClose: () -> Void
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer
    @Environment(\.theme) private var th

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(th.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(jakarta(16, .extra)).foregroundStyle(th.fg1)
                    Text(subtitle).font(jakarta(11.5)).foregroundStyle(th.fg3)
                }
                Spacer()
                IconButton(icon: "xmark", size: 28, bordered: false, action: onClose)
            }
            .padding(.init(top: 16, leading: 20, bottom: 14, trailing: 20))
            .overlay(alignment: .bottom) { Rectangle().fill(th.border).frame(height: 1) }

            ScrollView {
                content.padding(20)
            }
            .frame(maxHeight: 420)

            HStack(spacing: 10) {
                Spacer()
                footer
            }
            .padding(.init(top: 12, leading: 20, bottom: 14, trailing: 20))
            .overlay(alignment: .top) { Rectangle().fill(th.border).frame(height: 1) }
        }
        .frame(width: 560)
        .background(th.bg2)
    }
}

func aiField<C: View>(_ label: String, @ViewBuilder content: () -> C) -> some View {
    AIFieldView(label: label, content: content())
}

private struct AIFieldView<C: View>: View {
    var label: String
    var content: C
    @Environment(\.theme) private var th

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(jakarta(12.5, .semibold)).foregroundStyle(th.fg1)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
