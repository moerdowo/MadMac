# MadMac AI Features — Specification (for review)

Status: **implemented & tested 2026-06-11** (all phases; 3b chat deferred as specified)
Provider: **OpenAI API** (chosen for image generation + editing)

## Principles

1. **Off by default.** AI is invisible until enabled in Settings *and* an OpenAI API key is provided. No AI UI elements render otherwise.
2. **AI drafts, the review sheet decides.** AI output only ever fills wizard drafts, staged changes, or advisory annotations. AI can never invoke a Meta write command. The Approve button remains the only door to the ad account.
3. **Clear data boundary.** Only the minimum needed leaves the Mac: ad copy text, campaign metrics (aggregate numbers), and images the user explicitly submits. The Meta access token, account credentials, and Keychain contents are never sent to OpenAI.
4. **Visible cost.** Every image-generation action shows an approximate cost before running. Text actions are sub-cent and run without confirmation.

---

## Settings (gate for everything)

New **AI** section in Settings (⌘,):

| Control | Behavior |
|---|---|
| Enable AI features (toggle) | Default **off**. When off, every AI affordance in the app is hidden. |
| OpenAI API key (secure field) | Stored in macOS Keychain (`com.moerdowo.MadMac` / `openai`), never on disk in plain text, never logged. |
| Test connection (button) | Calls `GET /v1/models`; shows ✓ or the API error. |
| Text model (picker) | Default `gpt-4o-mini` (cheap); alternative `gpt-4o` / latest — list fetched from `/v1/models`, defaults confirmed at implementation time. |
| Image model | `gpt-image-1` (generation + edits). |
| Image quality (picker) | Low / Medium / High — maps to gpt-image-1 quality, shown with per-image cost estimate. |
| Data disclosure (static text) | One paragraph stating exactly what is sent to OpenAI (see Principles #3). |

Enabling requires both the toggle *and* a key that passes Test connection.

---

## Phase 1 — Creative Studio (the OpenAI-specific value)

### 1a. AI copywriter (wizard step 3)

A "✨ Generate copy" button beside the Headline field opens a small sheet:

- Inputs: product description (free text, prefilled from campaign name + destination URL), tone (Casual / Professional / Playful), language (Indonesian / English / Both).
- Output: 5 headlines + 5 primary texts, shown as selectable chips.
- Accepting fills Headline + Primary text with the first picks and the DCO variant fields with the rest (auto-enabling dynamic creative).
- One Responses API call with structured output (JSON schema: `{headlines: [string], texts: [string]}`).

### 1b. Image generation (wizard step 3)

"✨ Generate image" in the media drop zone:

- Inputs: prompt (prefilled from product description + headline), aspect (1:1 feed · 1536×1024 landscape · 1024×1536 portrait/Reels), count (1–4).
- Calls `POST /v1/images/generations` (gpt-image-1); results preview in a grid; accepted images are saved as PNG to `~/Library/Application Support/MadMac/generated/` and appended to `draft.media` — from there the **existing** creative-upload pipeline takes over.
- Cost line above the Run button: "≈ $0.04–0.17 per image at Medium" (exact figures pulled into the UI at implementation from current pricing).

### 1c. Image editing (wizard step 3)

Each item in the media list gets an "✨ Edit" action:

- Inputs: the selected image + a plain-language instruction ("remove the text overlay", "swap background to a bathroom counter", "extend to 9:16 for Reels").
- Calls `POST /v1/images/edits` (multipart, gpt-image-1). Result previews side-by-side with the original; accepting adds the edited file as a *new* media item (original kept, so both can run as DCO variants).

**Why this matters:** today you need a designer or Canva round-trip for every aspect-ratio variant or background swap. This makes creative iteration a 20-second loop inside the wizard.

---

## Phase 2 — Planning assistance

### 2a. Brief → launch plan

"✨ New from brief…" button next to "New campaign" (Campaigns header):

- One text field: *"produk skincare baru, budget 200rb/hari, perempuan 18–35, optimize purchase, pakai pixel ADASSD"*.
- The model receives the brief plus the app's reference data (available pixels, pages, account currency) and returns a structured `DraftCampaign` (JSON schema mirrors the Swift struct: name, objective, daily, bidAmount, countries, optimization, pixelId, copy…).
- Result opens the **wizard prefilled** (not the review sheet directly) so every field is inspectable, then flows through review as usual.
- Optionally generates copy in the same call; image generation stays a separate explicit click (cost).

### 2b. Policy pre-check (review sheet)

When a draft includes creative copy, the review sheet shows a "Policy check" row:

- The model evaluates copy + headline against a condensed rubric of Meta ad policies (personal attributes, unrealistic results, before/after claims for cosmetics, prohibited content).
- Output: `{risk: none|low|high, flags: [{text, reason, suggestion}]}` rendered as a green ✓ line or amber warning items above the budget warning.
- Advisory only — never blocks Approve. Runs automatically (sub-cent) with a "Skip checks" preference.

---

## Phase 3 — Analysis (needs delivery data to be useful)

### 3a. AI insights in Diagnostics

A "✨ Analyze account" button on the Diagnostics section (and auto-weekly, optional):

- Input: the existing `AccountSnapshot` serialized to compact JSON (series, per-campaign metrics, breakdowns — numbers only, no PII).
- Output: 3–5 narrative insights, each optionally carrying a machine-readable recommendation (`pause entity X` / `set budget of X to Y`).
- Recommendations render with a **"Stage this"** button → flows into the existing pending-changes engine → review sheet. AI never applies anything.

### 3b. Ask your account (chat)

Deferred until 3a proves out. A small panel where questions are answered by the model calling *read-only* insights queries as tools (campaign list, insights get with date ranges/breakdowns). Write tools are not exposed to the model, by construction.

---

## Architecture

```
Sources/AI/
  OpenAIClient.swift     // URLSession; /v1/responses, /v1/images/generations,
                         // /v1/images/edits, /v1/models. No SDK dependency.
  AIService.swift        // feature-level API:
                         //   generateCopy(brief) -> CopySet
                         //   generateImages(prompt, aspect, n) -> [URL]
                         //   editImage(url, instruction) -> URL
                         //   parseBrief(text, context) -> DraftCampaign
                         //   policyCheck(draft) -> PolicyReport
                         //   analyze(snapshot) -> [InsightRecommendation]
  AIPrefs.swift          // enable flag (UserDefaults) + key (Keychain)
```

- All requests to `api.openai.com` over TLS; `Authorization: Bearer` from Keychain at call time.
- Structured outputs everywhere (`response_format: json_schema`) so parsing never guesses.
- Errors surface in the existing banner; a 401 deep-links to Settings → AI.
- Generated images are cleaned from `generated/` when older than 30 days.

## Cost expectations (order of magnitude, to verify at implementation)

| Action | Est. cost |
|---|---|
| Copy generation / brief parse / policy check | < $0.01 each |
| Account analysis | ~$0.01–0.03 |
| Image generation | ~$0.01 (low) – $0.25 (high) per image |
| Image edit | similar to generation |

## Proposed build order

1. **Phase 1** (settings + copywriter + image gen/edit) — the OpenAI-specific differentiator, self-contained in the wizard.
2. **Phase 2** (brief → plan, policy check) — reuses Phase 1 plumbing.
3. **Phase 3** after your account has delivery data worth analyzing.

## Open questions for review

1. Image quality default: Medium (~$0.04–0.07/image) reasonable?
2. Should the policy check run automatically on every review (sub-cent) or only on click?
3. Brief → plan: open the prefilled wizard (proposed) or jump straight to the review sheet?
4. Generated-image retention: 30 days okay, or keep forever?
5. Phase 3 auto-weekly analysis: opt-in notification, or on-demand only?
