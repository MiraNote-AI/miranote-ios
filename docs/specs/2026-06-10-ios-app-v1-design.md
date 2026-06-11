# MiraNote iOS App v1 -- Frontend Design

**Date:** 2026-06-10
**Source:** Jason's (Jiachen Zhong) hand-drawn sketches, posted in Discord #general
2026-06-11 01:41 UTC (IMG_4316-4319), plus his accompanying notes and the
decisions recorded below. Sketch originals stay in Discord (binary images are
not committed; Rule 3 allowlist does not cover jpg).

## Product shape (from sketches)

Three screens, one modal flow:

```
Home ──"Start a memory"──> Canvas ──long-press / toolbar──> input sheets
                                       ├── Text input sheet   (2.1)
                                       ├── AI Sticker sheet   (2.2a, see D2)
                                       └── Style Transfer sheet (2.2b, see D2)
```

### 1. Home (IMG_4316)

- Top bar: hamburger menu (left), profile avatar (right).
- Primary action: large pill button **"Start a memory"** -> opens a new Canvas.
- Collections row: horizontally scrollable cards ("Collection 1",
  "Collection 2", ...), drawn as book spines.
- Bottom: persistent input pill **"What is in your mind?"** with a small
  voice/keyboard glyph on the left (ASSUMPTION A3: glyph = voice input
  entry; same glyph reappears in the AI Sticker sheet).
- Empty state (per D3): when no collections exist, show one guiding line
  pointing at "Start a memory". No multi-step onboarding in v1.

### 2. Canvas (IMG_4317)

- Top bar: back chevron | title "Canvas" | right actions **Save** and
  **Quick organize** (ASSUMPTION A2: the scrawled second action reads
  "Quick organize" and corresponds to the auto-organization feature from the
  2026-06-06 meeting).
- Long-press anywhere on the canvas -> radial/popover menu with three
  options: **Text / Image / AI**.
- Bottom toolbar: pills **[sticker] [text] [photo]**, then an **AI** bubble
  button and an **expand** chevron-up button.
  - Jason's note: the bottom drawer behaves like WeChat's sticker library
    ("这里就和我们wechat的library类似").
  - ASSUMPTION A1: the circled up-arrow expands the drawer into that
    library view.

### 2.1 Text input sheet (IMG_4318)

- Modal sheet over the canvas; canvas behind is **blurred** (Jason: 虚化).
- Top bar: back chevron | "Text input" | **Done**.
- Body: free text editor.
- Bottom action row: **[voice] [clean] [expand] [polish]**.
  - Backend mapping (miranote-api POCs): voice -> voice-to-text (:8000),
    clean/expand/polish -> text-clean-expand (:8001). v1 wires these through
    a service protocol with a mock implementation; live HTTP comes later.

### 2.2 Image input (IMG_4319, restructured per D2)

Jason drew one combined sheet (add images + AI Sticker + Style transfer +
Generate) and explicitly asked whether to split it. Decision D2: **two
separate entries**, each its own sheet:

- **AI Sticker sheet**: prompt field "Describe a sticker" (+ voice glyph,
  see A3) -> Generate.
- **Style Transfer sheet**: image picker row ([+] plus up to 3 thumbnails,
  see D1) -> style chooser **Cartoon / Vintage / Hand-drawn** -> Generate.
- Both sheets blur the canvas behind them, same as 2.1.

## Decisions log

| # | Decision | By | Date |
|---|---|---|---|
| D1 | Image picker allows at most **3** images per add; cap is a single config constant | Meng | 2026-06-10 |
| D2 | AI Sticker and Style Transfer are **two separate entries**, not one combined sheet | Meng | 2026-06-10 |
| D3 | v1 guidance = **empty-state hints only**; full onboarding deferred | Meng | 2026-06-10 |

## Open questions

| # | Question | Owner |
|---|---|---|
| Q1 | Starting point: rebuild fresh, or rebase onto Jason's existing Xcode/SwiftUI prototype (demoed 2026-06-06, not yet pushed)? | Jason |
| Q2 | Confirm assumptions A1 (drawer expand arrow), A2 ("Quick organize"), A3 (voice glyph) | Jason |
| Q3 | When do sheets call live POC endpoints vs mocks (dev builds talk to localhost?) | team |
| Q4 | Home bottom pill "What is in your mind?" -- does it open the chatbot POC (:8003) flow? | Jason |
| Q5 | Should a plain add-photo path (no style transfer) exist? v1 routes both the [photo] pill and the long-press Image option through the Style Transfer sheet, which requires picking a style before Generate. Q1 resolved 2026-06-10: build fresh (Meng) | Jason |

## Non-goals for v1

- No real backend calls (service layer ships with mock implementations).
- No auth, no persistence beyond in-memory + simple local store.
- No sticker cutout pipeline UI (Zhao Yan's model) beyond the Generate stub.
- No multi-step onboarding (D3).
