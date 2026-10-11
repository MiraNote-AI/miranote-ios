# Redesign phase B: text styling, page paper, page ratio

Refs #85 (phase A: #81, plan `2026-10-10-redesign-phase-a.md`)

## Goal (acceptance criteria)

B1 -- text styling (`feat/text-styling`, builds on phase A's #84)
1. Per-block font, any color (palette swatches + system picker with
   eyedropper), alignment, text background.
2. Old saves decode with defaults and render as before (kit tests).
3. Editor, reading view and height measurement share one face (`TextFace`).
4. Each style change is one undo step; a picker drag is one step per block
   and property (`PickerUndoGate`, unit-tested).

B2 -- page paper: Blank / Grid / Lined / Dot + solid page color (screen 05).
B3 -- page ratio 3:5 shared by canvas, reading view and export.

For every PR: MiraNoteKit `swift test` green; Release build; full app suite
on iPhone 17 Pro; `checks.no_cjk_or_emoji` exit 0; fresh-context review.
HUMAN: visual match to handoff screens 11-20 (B1), 05 (B2).

## Stop conditions

Same contract as phase A: 5 iterations per PR, 2 without progress -> handoff,
escalate on protected paths / weakened tests / scope beyond #85, never
self-merge.

## Iterations

1. B1 written TDD: kit TextStyleTests (8) red -> TextBlock fields + custom
   Decodable + CanvasViewModel+TextStyle -> green; kit 360/360. App: TextFace,
   hex colors, alignment/background rendering in editor + reading view,
   measurement takes the face, accessory rows (fonts+sizes, colors,
   background, alignment button). TextStylingUITests 2/2. Release OK, CJK 0.
   Full suite: 2 failures, both stalls from machine load (a VM at ~170 % CPU;
   a pre-existing test took 630 s in one run) -- both passed on rerun in
   19 s / 27 s.
2. Fresh-context review: NOT DONE -- shared picker timestamp could merge
   different blocks/properties into one undo; swatch labels read hex; no
   selected trait on font / "No background"; familyNames per call. Fixed:
   PickerUndoGate (+5 unit tests), named swatches, traits, cached families.
   Verified: no code rebuilds an existing TextBlock (style cannot be
   dropped). Declined: background padding concern (padding is constant).
