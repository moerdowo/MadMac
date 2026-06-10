import SwiftUI
import AppKit

// First-run onboarding: step-by-step guide to getting a Marketing API token
// and ad account ID, next to the connect form.

struct OnboardingView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.theme) private var th

    var body: some View {
        ConditionalScroll {
            VStack(spacing: 24) {
                // header
                VStack(spacing: 8) {
                    ZStack(alignment: .topTrailing) {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(th.accent)
                            .frame(width: 56, height: 56)
                            .overlay(Image(systemName: "bolt.fill")
                                .font(.system(size: 26, weight: .bold))
                                .foregroundStyle(.white))
                        Circle()
                            .fill(th.brandMagenta)
                            .frame(width: 16, height: 16)
                            .overlay(Circle().stroke(th.bg2, lineWidth: 2.5))
                            .offset(x: 5, y: -5)
                    }
                    Text("Welcome to MadMac")
                        .font(jakarta(24, .extra)).kerning(-0.3)
                        .foregroundStyle(th.fg1)
                    Text("Manage your Meta ads natively. Nothing goes live without your approval.")
                        .font(jakarta(13.5))
                        .foregroundStyle(th.fg3)
                }
                .padding(.top, 8)

                HStack(alignment: .top, spacing: 16) {
                    // steps
                    Card(pad: 22) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("GET YOUR TOKEN & ACCOUNT ID")
                                .font(jakarta(11, .bold)).kerning(0.6)
                                .foregroundStyle(th.fg3)
                                .padding(.bottom, 14)

                            OnboardingStep(
                                number: 1, title: "Create a Meta app",
                                detail: "On the Meta developer site, choose Create app with the use case \u{201C}Create & manage ads with the Marketing API\u{201D}. No app review is needed for your own account.",
                                linkLabel: "Open App Dashboard",
                                url: "https://developers.facebook.com/apps")
                            OnboardingStep(
                                number: 2, title: "Create a System User",
                                detail: "In Business Settings, go to Users → System users → Add. Name it (e.g. \u{201C}madmac\u{201D}) and give it the Admin role.",
                                linkLabel: "Open Business Settings",
                                url: "https://business.facebook.com/settings")
                            OnboardingStep(
                                number: 3, title: "Assign assets to the system user",
                                detail: "Select the system user → Add assets. Grant your ad account (Manage campaigns) and the app from step 1 (Manage app). Without the app role, token generation shows \u{201C}No permissions available\u{201D}.")
                            OnboardingStep(
                                number: 4, title: "Generate the access token",
                                detail: "Still on the system user, click Generate new token: pick your app, set expiration (Never is fine), and check ads_management, ads_read, read_insights, business_management. The token is shown once — copy it straight into the form.")
                            OnboardingStep(
                                number: 5, title: "Find your ad account ID",
                                detail: "Open Ads Manager and look at the URL: act=1234567890 — the number is your account ID. It's also listed under Business Settings → Ad accounts.",
                                linkLabel: "Open Ads Manager",
                                url: "https://adsmanager.facebook.com",
                                last: true)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    // connect form
                    Card(pad: 22) {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("CONNECT YOUR ACCOUNT")
                                .font(jakarta(11, .bold)).kerning(0.6)
                                .foregroundStyle(th.fg3)
                            ConnectForm()
                        }
                    }
                    .frame(width: 360)
                }
                .frame(maxWidth: 980)
            }
            .frame(maxWidth: .infinity)
            .padding(28)
        }
    }
}

private struct OnboardingStep: View {
    var number: Int
    var title: String
    var detail: String
    var linkLabel: String?
    var url: String?
    var last: Bool = false
    @Environment(\.theme) private var th

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle().fill(th.accentSoft).frame(width: 26, height: 26)
                Text("\(number)")
                    .font(jakarta(13, .extra))
                    .foregroundStyle(th.accent)
            }
            .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(jakarta(14, .bold))
                    .foregroundStyle(th.fg1)
                Text(detail)
                    .font(jakarta(12.5))
                    .foregroundStyle(th.fg3)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                if let linkLabel, let url {
                    Button {
                        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
                    } label: {
                        HStack(spacing: 5) {
                            Text(linkLabel).font(jakarta(12.5, .semibold))
                            Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(th.accent)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
        }
        .padding(.bottom, last ? 0 : 16)
    }
}
