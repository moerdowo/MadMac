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
