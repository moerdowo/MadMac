<p align="center">
  <img src="docs/icon.png" width="128" alt="MadMac icon">
</p>

<h1 align="center">MadMac</h1>

<p align="center"><b>Manage your Meta ads natively on macOS.</b><br>
A SwiftUI app for your Meta ad account — campaigns, insights, and a review-before-launch flow that makes sure nothing spends money without your explicit approval.</p>

---

![Performance dashboard](docs/01-performance-overview.png)

## Why

Meta's Ads Manager is a heavy web app. MadMac is a real Mac app — sidebar, charts, switches, dark mode — talking to your ad account through the Meta Marketing API.

## The hero flow: review before launch

Nothing touches your ad account until you approve it.

Flipping any status switch or finishing the create wizard **stages** the change. A floating bar shows what's staged; *Review & launch* opens the launch plan — a spec tree for new campaigns and before→after diffs for status changes — gated behind **Approve & launch**. New campaigns are always created `PAUSED` unless you explicitly toggle *Launch active now*.

![Review sheet](docs/05-review-sheet.png)

## Features

- **Performance dashboard** — KPI cards with 7-day deltas and sparklines (spend, revenue, ROAS, purchases, CPA, CTR, reach, CPM), a revenue/spend chart with real 7/30/90-day ranges, spend-by-placement donut, audience demographics (age, gender, geo), top campaigns, and a diagnostics feed. Three switchable layouts: Overview, Spotlight, Table.
- **Full campaign creation** — the 3-step wizard builds the whole chain: campaign (budget) → ad set (optimization goal, bid cap, countries, pixel + conversion event, optional schedule) → creative (drag-and-drop image/video upload, headline, primary text, link, CTA, Facebook Page picker) → ad. Multiple assets or copy variants become a dynamic-creative (DCO) ad automatically.
- **Campaigns** — an expandable campaign → ad set → ad tree with per-row metrics, staged budget edits, duplicate, archive, and safe-delete (all gated behind the review sheet), search and status filters, and a detail drawer.
- **Menu-bar pacing** — today's spend vs. budget, blended ROAS, and staged-change count, always one click away.
- **Multi-account** — switch between every ad account your token can reach from the sidebar account card.
- **AI Creative Studio (optional, off by default)** — bring your own OpenAI API key (Settings → AI, stored in Keychain) to unlock: ad-copy generation (5 headlines × 5 texts, Indonesian/English, auto-fills dynamic creative), **image generation and editing** (gpt-image-1 — aspect presets for feed/Reels, "remove the text overlay"-style edits), natural-language **brief → prefilled campaign**, automatic **policy pre-checks** on your copy in the review sheet, and account **analysis with stageable recommendations**. AI only ever drafts and stages — applying anything still requires Approve. See [docs/ai-spec.md](docs/ai-spec.md).

  ![Campaigns](docs/04-campaigns.png)

- **Catalog, Diagnostics, Datasets** — product performance, account-health signals, and pixel events.
- **Onboarding that actually onboards** — a step-by-step guide to creating a Meta app, a System User, and a properly-scoped access token, with deep links into the right Meta dashboards.

  ![Onboarding](docs/00-onboarding.png)

- **Mayar design system** — Plus Jakarta Sans, brand blue/magenta, full light & dark token sets, four accent colors, and density settings (⌘,).

  ![Dark mode](docs/11-dark-overview.png)

## Connecting your account

MadMac opens with the onboarding guide. In short:

1. Create a Meta app ([developers.facebook.com/apps](https://developers.facebook.com/apps)) with the *Marketing API* use case.
2. In [Business Settings](https://business.facebook.com/settings), create a **System User** (Admin) and assign it your **ad account** and the **app**.
3. Generate a token with `ads_management`, `ads_read`, `read_insights`, `business_management`.
4. Your ad account ID is the `act=…` number in the [Ads Manager](https://adsmanager.facebook.com) URL.
5. Paste both into MadMac.

The token is stored in the **macOS Keychain** — it never touches disk in plain text. The first connection sets up a private helper environment in `~/Library/Application Support/MadMac/` (needs Python 3.12 or 3.13, e.g. `brew install python@3.13`).

Prefer to look around first? *Explore sample data* loads a fictional account with realistic numbers.

## Building

```sh
brew install xcodegen
xcodegen generate
xcodebuild -project MadMac.xcodeproj -scheme MadMac -configuration Release build
```

Requires macOS 14+ and Xcode 16+.

### Debug helpers

```sh
MadMac --snapshot /tmp/shots          # render every screen to PNG (ImageRenderer)
MadMac --connect <token> <account_id> # store credentials from the terminal
MadMac --live-check                   # exercise the live pipeline headlessly
```

## How it talks to Meta

`AdsBackend` protocol with two implementations:

- **SampleBackend** — the bundled demo dataset.
- A **live backend** against the Marketing API, with per-campaign insight queries capped to respect the ~200 calls/hour rate limit and currency-offset handling verified against a real account (IDR and 14 other currencies have no minor units in the Marketing API).

Every write the app can issue lives in [`Sources/Backend/CLIBackend.swift`](Sources/Backend/CLIBackend.swift): campaign/ad set/ad status updates, and campaign creation (always `PAUSED` unless approved live).

## Design

Implemented from a Claude Design handoff bundle ("Pacer — Meta Ads for Mac") on the Mayar design system: Plus Jakarta Sans (bundled), brand blue `#2D3DEC` / magenta `#E91E78`, ported to SwiftUI with full light/dark token sets. Charts are hand-rolled SwiftUI `Path`s — no dependencies. Built with [Claude Code](https://claude.com/claude-code).

## License

[MIT](LICENSE) — the bundled Plus Jakarta Sans font is licensed separately under the [SIL Open Font License](https://fonts.google.com/specimen/Plus+Jakarta+Sans/license).
