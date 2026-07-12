# Library toolbar button -- plan & ledger

REQUIRED SUB-SKILL: run-loop
Refs MiraNote-AI/miranote-ios#30
Spec: docs/specs/2026-07-12-library-toolbar-button-design.md
Branch: `feat/library-toolbar-button` (worktree `miranote-ios-wt-library`)
Base: cae36da

## Goal

The shared favorites folder (images + stickers) opens from a fourth
bottom-toolbar button; taps place items on the canvas; photos can join
the folder from the photo edit panel.

## Acceptance criteria

- [ ] `GeneratedSticker.kind` (sticker | image), old JSON decodes as
      sticker -- Kit tests
- [ ] Fourth InputModeBar slot `Library` visible wherever the bar shows
- [ ] Library panel: grid of saved items over the user's page; empty
      state line; prune-on-open hygiene (parity with the Image panel)
- [ ] Tap places: sticker -> sticker element, image -> image element,
      then returns to the canvas -- UITest
- [ ] Photo edit panel action saves the current photo into the folder
      (idempotent per file) -- UITest or Kit
- [ ] New view-layer tests carry mutation evidence
- [ ] swiftlint --strict = 0; Kit suite green; full build test green on
      the shadow simulator (iPhone 17, 0DB498B2)
- [ ] Fresh-context subagent review (criteria + diff only) returns DONE
- [ ] ONE PR referencing #30, CI green (HUMAN: review + merge; naming
      overlap with the photo-library source flagged for Gloria/Meng)

## Stop conditions

- Iteration cap: 5 per criterion-cluster; no-progress rule after 2.
- Escalation: protected paths, check weakening, scope beyond #30.

## Environment

- Shadow simulator 0DB498B2 (probes/tests); user simulator FB498BEA
  gets verified installs only.
- Backends not required (feature is fully local).

## Iterations

(appended as they complete)

1. Kit: GeneratedSticker.kind (sticker | image) with decode fallback to
   sticker; store tests for kind round-trip + legacy JSON. 4/4 store
   tests green.
2. App: EditorMode.library (books.vertical) -> FlowScene.libraryPanel ->
   LibraryPanelScene (grid over the user's page, empty state, tap
   places by kind); PhotoEditPanel bookmark files the photo as an image
   entry (idempotent per file, noticed). First UITest run: 2/3 failed --
   the panel's prune-on-open used the Image panel's minSide 24, which
   ate the deliberately tiny -UITEST artwork. Library hygiene relaxed to
   missing-file pruning only (minSide 1, reasoned in code); 3/3 UITests
   green. Mutation evidence: with App+Kit sources stashed the test
   build fails (2 errors) -- the suite cannot pass without the feature.
   swiftlint --strict 0; Kit 207 green.
