import SwiftUI

// Phase 2a: natural-language brief → prefilled wizard draft.

struct BriefSheet: View {
    var onClose: () -> Void
    @EnvironmentObject private var state: AppState
    @Environment(\.theme) private var th
    @State private var brief = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        AISheetChrome(title: "New campaign from brief",
                      subtitle: "Describe what you want to run — the wizard opens prefilled for review",
                      onClose: onClose) {
            VStack(alignment: .leading, spacing: 12) {
                TextEditor(text: $brief)
                    .font(jakarta(13.5))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(height: 110)
                    .background(th.bg1)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(th.borderStrong, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Text("Example: \u{201C}produk skincare baru, budget 200rb/hari, perempuan 18–35, optimize untuk purchase, pakai pixel yang ada, link ke lumio.id\u{201D}")
                    .font(jakarta(11.5))
                    .foregroundStyle(th.fg4)
                    .lineSpacing(2)
                if let error {
                    Text(error).font(jakarta(12, .medium)).foregroundStyle(th.danger)
                }
            }
        } footer: {
            if busy {
                ProgressView().controlSize(.small)
                Text("Drafting…").font(jakarta(12)).foregroundStyle(th.fg3)
            }
            Btn(variant: .primary, icon: "sparkles", label: "Draft campaign",
                disabled: brief.trimmingCharacters(in: .whitespaces).isEmpty || busy) {
                run()
            }
        }
    }

    private func run() {
        busy = true
        error = nil
        Task {
            do {
                let pages = (try? await state.backend.pages()) ?? []
                let draft = try await AIService.parseBrief(
                    brief, currency: state.snapshot.account.currency,
                    pixels: state.snapshot.pixels, pages: pages)
                state.createPrefill = draft
                onClose()
                state.createOpen = true
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }
}
