# Library toolbar button -- design

Refs MiraNote-AI/miranote-ios#30
Decision basis: 2026-07-07 (toolbar sticker slot becomes a shared
favorites folder holding images + stickers, one folder) and the
2026-07-11 meeting ask (library as the fourth bottom-toolbar button).

## What exists

- Bottom instrument panel: Sound / Text / Image (`EditorMode`,
  `InputModeBar`).
- `StickerFavoritesStore` (JSON next to the collections file, cap 12,
  newest first, prune-on-open hygiene): populated by sticker generation
  and convert-to-sticker; surfaced only as the Image panel's
  "My stickers" row.
- `CanvasViewModel.addSticker(_:at:)` and `addImages(_:around:)` place
  content; `ImageFileStore` holds the bitmaps.

## Shape of the change

1. **Entry kind** (Kit): `GeneratedSticker` gains
   `kind: Kind = .sticker` with `enum Kind: String { sticker, image }`.
   Decoding falls back to `.sticker` so persisted favorites survive.
   The type keeps its name -- renaming would churn every call site for
   no behavior; the doc comment carries the widened meaning.
2. **Fourth mode** (App): `EditorMode.library` (symbol
   `books.vertical`). `EditorFlowView.select(mode:)` routes it to a new
   scene case, same pattern as `.image` -> `.imageStart`.
3. **LibraryPanelScene** (App): EditorScaffold parity with the Image
   panel (user's page up top, panel + InputModeBar at the bottom).
   Grid of favorites thumbs (pruned on open). Tap places and returns to
   the canvas: sticker -> `addSticker`, image -> `addImages` (single
   ref). Empty state: one quiet line explaining how items get here.
4. **Save to library** (App): the photo edit panel gains a bookmark
   action that files the current photo's file name into the store as
   `kind: .image` (label = display name). One tap, notice-confirmed,
   idempotent per file name.

## Decisions

- Stickers and images share ONE folder and ONE cap (12): the 07-07
  decision says one folder; a bigger cap is a follow-up if the demo
  needs it.
- Placement position mirrors the existing favorites row
  (`contentBottom + 80`), no new layout logic.
- The Image panel's "My stickers" row stays as-is this loop (it shows
  everything in the folder, which now may include images -- acceptable;
  removing or renaming that row is Gloria's call).
- HUMAN: the word "Library" now names both the iOS photo library button
  inside the Image panel and the new folder button. Flagged in the
  issue for Gloria/Meng; rawValue `library` is stable either way, only
  the display title would change.

## Out of scope

- Quick-organize, TestFlight (separate meeting items).
- Long-press management (delete/rename) inside the library panel.
- Favoriting text blocks or sounds.
