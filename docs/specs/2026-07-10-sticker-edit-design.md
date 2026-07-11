# Editing a placed sticker -- design

Approved by Meng on 2026-07-10 (brainstorm in session; mechanism and
cut-preservation both user-decided). Refs issue #21.

## Goal

A sticker already on the canvas can be changed with words, from both
sides of the app:

1. Mira: "make the sticker blue" / "把贴纸改成蓝色" restyles the
   targeted sticker in place.
2. UI: the sticker's long-press menu gains Edit sticker, opening a
   one-field instruction panel.

Both run the same pipeline: `/stylize` (new pixels) -> `/cutout` ->
`/border` outline (re-cut, so the die-cut look survives shape-changing
asks like "give the cat a hat"). User-decided over the faster
alternatives (reusing the old alpha mask, or asking the model to keep
transparency) because only a re-cut handles shape changes and the
model's transparency support is unreliable.

## Non-goals

- No backend changes: all three endpoints exist on :8002.
- No filters or frames for stickers; no regenerate-style editing (the
  existing "draw a sticker ..." ask already covers that).
- No fix for the pre-existing photo zero-target clarify copy ("More
  than one photo here" when there are none) -- known wart, out of
  scope.

## Intent grammar

New family in the cue router (`MiraIntent+Image.swift`), checked
between generation and the photo family:

- **editSticker(itemID, imageData, instruction, prompt)** -- fires when
  the ask mentions a sticker in any form ("the sticker", bare
  "sticker" -- "change sticker to blue" is how people actually type --
  "贴纸"), carries an edit verb (the shared list in the 2026-07-10
  edit-verb-widening spec), and is NOT an indefinite new-sticker wish
  ("a sticker", "another sticker": "make a sticker of a cat" stays
  conversational) or the photo-conversion phrase ("into a sticker" /
  "抠成" -- "把照片抠成贴纸" mentions 贴纸 but must stay makeSticker
  on the photo). (Amended 2026-07-10 after device testing: the original
  definite-mention allow-list missed article-less phrasings.)
  `instruction` is the user's whole ask; `prompt` is the original
  sticker's prompt (the new favorites entry keeps its label).
- **clarifySticker(question)** -- raised instead when the target is
  missing or ambiguous. Zero stickers: "No sticker on this page yet --
  generate one first?". Several, none selected: "More than one sticker
  here -- tap the one you mean and ask again."

**Target resolution** (`stickerTarget(editor:)`) mirrors photos: the
selected sticker wins; else, if the canvas has exactly one sticker,
that one; else clarify. Only `.sticker` items count.

**Photo-family guard (bug fix)**: the photo family bails when the ask
mentions a sticker in ANY form -- the broad word ("sticker", "贴纸"),
not just the definite forms -- but no photo (and is not the conversion
phrase).
Today "make the sticker warmer" lands on the PHOTO warm filter because
`filterCue` only sees "warmer"; after this change a sticker-flavored
ask can never mutate a photo.

Unchanged neighbors: "draw a sticker ..." stays generation (checked
first); "turn the photo into a sticker" stays makeSticker on a photo.

## Turn machinery, receipts, undo

- editSticker is slow work (`isSlowImageWork`), so it runs on the
  150 s image timeout with verb "Redrawing the sticker...". Stop
  interrupts with zero canvas change and refills the prompt.
- Success reuses the existing `stickerReplaced` outcome: receipt
  "Restyled the sticker." / "Undo brings the old one back.", one undo
  step, and the new version joins the favorites store (parity with
  every other sticker-producing path; the old favorite stays).
- `settleStickerReplaced` branches on the target's current content:
  `.image` -> `replaceImageWithSticker` (existing photo-conversion
  path), `.sticker` -> `replaceSticker` (new). Missing item -> the
  existing retry-failure card.
- New mutator `CanvasViewModel.replaceSticker(itemID:with:)` follows
  the `replaceImageWithSticker` pattern exactly: guard the item is a
  `.sticker`, `beginChange()`, swap content. Callers never wrap it in
  another `beginChange`.

## UI entry

- `CanvasBoardView` context menu, `.sticker` branch (today
  `EmptyView()`): an Edit sticker button when the sticker has stored
  pixels (`fileName` non-empty), reported through a new
  `onEditSticker` callback (same shape as `onEditImage`).
- `CanvasScene` holds `editingStickerItem` next to `editingImageItem`,
  with the same open guards (not while Mira works; stop mic first) and
  the same auto-close when the item stops being a sticker.
- New `App/Sources/Screens/Editor/StickerEditPanel.swift`: a
  `ContextCard` titled "Edit sticker" with one instruction field
  ("Tell AI what to change"), a Go button, a notice line, and Done.
  Runs stylize -> cutout -> outline, saves the file, builds a
  `GeneratedSticker` keeping the old prompt and symbol, calls
  `replaceSticker`, adds to favorites, notices "Done -- take a look.
  Undo brings the old one back." Accessibility ids:
  `sticker.ai.instruction`, `sticker.ai.run`, `sticker.done`.

## Error handling

- Sticker with no stored pixels (legacy symbol stickers,
  `fileName == ""`): Mira raises a calm clarify ("This sticker has no
  stored pixels to work on -- try another?"); the menu entry simply
  does not appear in the UI.
- Any pipeline step failing or timing out lands on the existing calm
  failure card with Try again; no partial canvas state is possible
  because mutation happens only in settle / panel completion.

## Testing

- Kit, classification: English and Chinese edit cues route to
  editSticker; "turn the photo into a sticker" still converts the
  photo; "把照片抠成贴纸" still converts the photo; "make the sticker
  warmer" no longer applies the photo warm filter; "make a sticker of
  a cat" (indefinite) stays converse; photo and text asks unaffected.
- Kit, targeting: selected sticker wins; only-sticker auto-targets;
  several-unselected and zero-sticker asks clarify with zero canvas
  change.
- Kit, turn (ScriptedImageStudio): pixels replaced in place through
  the full stylize -> cutout -> outline chain; favorites gains one;
  one undo restores the old sticker; empty-pixels ask fails calmly.
- UITests (mock studio, shadow simulator): generate-and-place a
  sticker, ask "make the sticker blue", assert the receipt and that
  the element is still a sticker; long-press -> Edit sticker -> type
  -> Go -> Done notice.
- Standard gates: swiftlint --strict 0, full Kit + UITest suites green
  on the shadow simulator, live film-strip against :8002 before
  install.
