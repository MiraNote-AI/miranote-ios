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
