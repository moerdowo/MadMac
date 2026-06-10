import SwiftUI

// Connect a real Meta account: paste a Marketing API access token + account ID.
// Token goes to the Keychain; the ads-cli sidecar reads it from the environment.
// ConnectForm is shared by the onboarding screen and the reconnect sheet.

struct ConnectForm: View {
    var compact: Bool = false
    @EnvironmentObject private var state: AppState
    @Environment(\.theme) private var th
    @State private var token = Credentials.load()?.accessToken ?? ""
    @State private var accountId = Credentials.load()?.accountId ?? ""
    @State private var pageId = Credentials.load()?.pageId ?? ""
    @State private var busy = false
    @State private var status: String?
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            field("Access token", hint: "System User token") {
                SecureField("EAAB…", text: $token)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(th.bg1)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(th.borderStrong, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            field("Ad account ID", hint: "with or without act_") {
                WizardTextField(text: $accountId)
            }
            field("Facebook Page ID", hint: "optional · for ad creation") {
                WizardTextField(text: $pageId)
            }
            Text("Stored in your macOS Keychain. The first connection installs Meta's meta-ads CLI into a private environment (needs Python 3.12/3.13).")
                .font(jakarta(11.5))
                .foregroundStyle(th.fg4)
                .lineSpacing(3)

            if let status {
                HStack(spacing: 8) {
                    if busy { ProgressView().controlSize(.small) }
                    Text(status)
                        .font(jakarta(12.5, .medium))
                        .foregroundStyle(failed ? th.danger : th.fg2)
                }
            }

            HStack {
                Btn(variant: .ghost, label: "Explore sample data") {
                    state.connectOpen = false
                    state.switchToSample()
                }
                Spacer()
                Btn(variant: .primary, icon: "link", label: busy ? "Connecting…" : "Connect",
                    disabled: token.isEmpty || accountId.isEmpty || busy) {
                    connect()
                }
            }
        }
    }

    private func connect() {
        busy = true
        failed = false
        status = "Preparing the ads-cli environment…"
        let creds = Credentials(accessToken: token.trimmingCharacters(in: .whitespacesAndNewlines),
                                accountId: accountId.trimmingCharacters(in: .whitespacesAndNewlines),
                                pageId: pageId.trimmingCharacters(in: .whitespacesAndNewlines))
        Task {
            do {
                try await Sidecar.shared.ensureInstalled { msg in
                    Task { @MainActor in status = msg }
                }
                status = "Verifying credentials with Meta…"
                _ = try await Sidecar.shared.meta(["-o", "json", "ads", "adaccount", "list"],
                                                  credentials: creds)
                try creds.save()
                status = nil
                busy = false
                state.connectOpen = false
                state.switchToLive()
            } catch {
                busy = false
                failed = true
                status = error.localizedDescription
            }
        }
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

// Modal version, used to reconnect once past onboarding.
struct ConnectSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.theme) private var th

    var body: some View {
        ZStack {
            Color(hex: 0x0E0F1A).opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { state.connectOpen = false }

            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Connect Meta account").font(jakarta(18, .extra)).foregroundStyle(th.fg1)
                        Text("Need a token? The onboarding guide walks you through it.")
                            .font(jakarta(12.5)).foregroundStyle(th.fg3)
                    }
                    Spacer()
                    IconButton(icon: "xmark", size: 32, bordered: false) { state.connectOpen = false }
                }
                .padding(.init(top: 20, leading: 24, bottom: 20, trailing: 24))
                .overlay(alignment: .bottom) { Rectangle().fill(th.border).frame(height: 1) }

                ConnectForm()
                    .padding(24)
            }
            .frame(width: 560)
            .background(th.bg2)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.3), radius: 40, y: 16)
        }
    }
}
