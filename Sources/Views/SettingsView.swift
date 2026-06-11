import SwiftUI

// Native Settings (Cmd+,) — the prototype's Tweaks panel: appearance, accent,
// dashboard layout, density.

struct SettingsView: View {
    @EnvironmentObject private var prefs: Prefs
    @EnvironmentObject private var state: AppState
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let th = Theme(dark: scheme == .dark, accent: prefs.accent.color)
        VStack(alignment: .leading, spacing: 22) {
            section("Appearance", theme: th) {
                Picker("Theme", selection: prefs.$appearance) {
                    ForEach(AppearanceChoice.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 10) {
                    Text("Accent").font(jakarta(13)).foregroundStyle(th.fg2)
                    Spacer()
                    ForEach(AccentChoice.allCases) { choice in
                        Button {
                            prefs.accent = choice
                        } label: {
                            Circle()
                                .fill(choice.color)
                                .frame(width: 22, height: 22)
                                .overlay(Circle().stroke(th.fg1.opacity(prefs.accent == choice ? 0.9 : 0), lineWidth: 2)
                                    .padding(-3))
                        }
                        .buttonStyle(.plain)
                        .help(choice.rawValue)
                    }
                }
            }

            section("Dashboard", theme: th) {
                Picker("Layout", selection: prefs.$dashLayout) {
                    ForEach(DashLayout.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            section("Density", theme: th) {
                Picker("Spacing", selection: prefs.$density) {
                    ForEach(Density.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            section("AI (OpenAI)", theme: th) {
                AISettings(th: th)
            }

            section("Account", theme: th) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.snapshot.account.name).font(jakarta(13, .semibold)).foregroundStyle(th.fg1)
                        Text(state.mode == .sample ? "Sample data" : state.snapshot.account.accountId)
                            .font(jakarta(11.5)).foregroundStyle(th.fg3)
                    }
                    Spacer()
                    Btn(variant: .secondary, size: .sm,
                        label: state.mode == .sample ? "Connect account…" : "Reconnect…") {
                        state.connectOpen = true
                    }
                }
            }
        }
        .padding(26)
        .frame(width: 440)
        .environment(\.theme, th)
    }

    private func section<C: View>(_ title: String, theme: Theme,
                                  @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(jakarta(11, .bold)).kerning(0.6)
                .foregroundStyle(theme.fg3)
            content()
        }
    }
}

// ── AI section (opt-in, OpenAI key in Keychain) ───────────────────────────

private struct AISettings: View {
    var th: Theme
    @ObservedObject private var ai = AIPrefs.shared
    @State private var keyField = AIPrefs.loadKey() ?? ""
    @State private var testResult: String?
    @State private var testing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $ai.enabled) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Enable AI features").font(jakarta(13, .semibold)).foregroundStyle(th.fg1)
                    Text("Copy & image generation, brief → campaign, policy checks, analysis")
                        .font(jakarta(11)).foregroundStyle(th.fg3)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            if ai.enabled {
                HStack(spacing: 8) {
                    SecureField("OpenAI API key (sk-…)", text: $keyField)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                        .onChange(of: keyField) { _, newValue in
                            try? AIPrefs.saveKey(newValue.trimmingCharacters(in: .whitespacesAndNewlines))
                            testResult = nil
                        }
                    Btn(variant: .secondary, size: .sm,
                        label: testing ? "Testing…" : "Test connection",
                        disabled: keyField.isEmpty || testing) {
                        testing = true
                        testResult = nil
                        Task {
                            do {
                                let models = try await OpenAIClient().listModels()
                                testResult = "✓ Connected · \(models.count) models available"
                            } catch {
                                testResult = "✗ \(error.localizedDescription)"
                            }
                            testing = false
                        }
                    }
                }
                if let testResult {
                    Text(testResult)
                        .font(jakarta(11.5, .medium))
                        .foregroundStyle(testResult.hasPrefix("✓") ? th.success : th.danger)
                }

                HStack(spacing: 14) {
                    Picker("Text model", selection: $ai.textModel) {
                        Text("gpt-4o-mini").tag("gpt-4o-mini")
                        Text("gpt-4o").tag("gpt-4o")
                        Text("gpt-4.1-mini").tag("gpt-4.1-mini")
                        Text("gpt-4.1").tag("gpt-4.1")
                    }
                    .font(jakarta(12))
                    Picker("Image quality", selection: $ai.imageQuality) {
                        ForEach(ImageQuality.allCases) { q in Text(q.rawValue).tag(q) }
                    }
                    .font(jakarta(12))
                }
                Text(ai.imageQuality.costHint)
                    .font(jakarta(11)).foregroundStyle(th.fg4)

                Toggle("Run policy check automatically in the review sheet", isOn: $ai.autoPolicyCheck)
                    .toggleStyle(.checkbox)
                    .font(jakarta(12))

                Text("What leaves your Mac: ad copy you write or generate, aggregate campaign metrics, and images you explicitly submit — sent only to api.openai.com. Your Meta access token and account credentials are never shared. AI output only fills drafts and staged changes; applying anything still requires Approve in the review sheet.")
                    .font(jakarta(10.5))
                    .foregroundStyle(th.fg4)
                    .lineSpacing(2)
            }
        }
    }
}
