# Mira image and style intents -- design

Approved by Meng on 2026-07-10 (brainstorm in session; scope, landing
mode, and grammar all user-decided).

## Goal

Everything the editor's buttons can ask of AI, the Mira ask bar can too.
Text transforms already route through Mira; this adds the image side and
the local style commands:

1. Generate a picture or sticker from words, onto the canvas.
2. Edit a photo with words (restyle in place; cut out into a sticker).
3. Apply filters and frames by name.
4. Style text by words (size steps, palette colors).

## Non-goals

- No backend changes: everything rides the existing :8002 endpoints and
  local editor mutations.
- No LLM-routed function calling for canvas asks (evaluated, deferred:
  every instant command would pay a network round trip and -UITEST
  determinism would need scripted tool traces). The local cue router
  stays the single classifier.
- No new visual chrome beyond one reply form (the two-candidate picker).

## Intent grammar

`MiraIntent.classify` gains four intent families. All cues are checked
in English and Chinese (Chinese written as unicode escapes in source,
per org Rule 3).

- **generateImage(prompt, sticker: Bool)** -- cues: draw, paint,
  generate, "画" (draw), "生成" (generate),
  "来一张" (give me a). Contains sticker /
  "贴纸" -> sticker kind (transparent subject); otherwise
  background kind. Style words already in the prompt (watercolor,
  illustration, photo and their Chinese forms) simply stay in the prompt
  text -- the server prompt-builder reads them; no style state.
- **editPhoto(itemID, instruction)** -- cues: "make the photo ...",
  "把照片" / "把这张" prefixes with a free
  instruction tail -> `/stylize` in place. "turn ... into a sticker" /
  "抠成贴纸" -> makeSticker(itemID) via `/cutout` +
  `/border`, replacing in place (panel parity).
- **applyFilter(itemID, name) / applyFrame(itemID, name)** -- filter
  names bw ("black and white", "黑白"), warm, film, match,
  none/original; frame names polaroid ("拍立得"), white,
  none. Local, instant.
- **styleText(itemID, change)** -- bigger/smaller
  ("大一点" / "小一点") move one step along the
  S/M/L point sizes; color words map to the existing five palette names
  (ink, forest, taupe, tan, textSecondary; green/"绿" -> forest,
  grey/"灰" -> textSecondary).

**Target resolution** mirrors the text precedent exactly:

- Photos (`targetPhoto()`): the selected image wins; else, if the canvas
  has exactly one image, that one; else clarify ("More than one photo
  here -- tap the one you mean and ask again.") with no canvas change.
- Text (`styleText`): the selected text block wins; else the longest
  non-empty block (same heuristic `targetText()` already uses).

**Cue precedence** (first match wins): filters and frames are checked
before the free-form photo edit, so "make the photo black and white"
is the bw filter, never a `/stylize` round trip; make-sticker is
checked before the generic edit for the same reason; generation cues
are checked before photo cues so "draw ..." never requires a photo.
Anything that matches no family falls through to converse, unchanged.

## Turn machinery, receipts, undo

- **Slow intents** (generate, stylize, make-sticker) run the full
  existing turn: intent-specific working verbs (Painting... /
  Restyling the photo... / Cutting the sticker...), Stop interrupts with
  zero canvas change and refills the prompt, timeouts and the failure
  card behave as today.
- **Instant intents** (filter, frame, text size, text color) skip the
  working bar: mutate immediately inside one `beginChange()` snapshot
  and show the one-line receipt (e.g. "Made the words bigger.",
  "Gave the photo its polaroid frame."). Revert stays one undo.
- **Generated candidates**: a new coordinator phase `.imageChoices`
  carries TWO in-memory images (never written to disk until placed).
  The Mira card renders two thumbnails plus an xmark. Tapping one places
  it (`addImages` for pictures; `addSticker` + favorites-store add for
  stickers, matching the panel) and shows "Added a picture." /
  "Added a sticker." with Revert. The xmark discards both, canvas
  untouched, no receipt. Canvas edits dismiss the choices the same way
  they dismiss replies today.
- **Photo edits** reuse `replaceImageFile` (undoable, clears the filter)
  and then re-describe the new pixels through the existing
  describe-after-edit hook so chat context follows.

## Component changes

- `MiraNoteKit/ViewModels/MiraIntent.swift` + new
  `MiraIntent+Image.swift`: the four families and `targetPhoto()` (the
  classifier stays under the 400-line file cap by splitting).
- `MiraCanvasCoordinator`: gains `imageStudio: ImageStudioService`
  (default mock; the two existing constructors' call sites updated),
  the `.imageChoices` phase, placement/discard entry points, and the
  instant-outcome path.
- `App/Screens/Editor/MiraStrip.swift` (`MiraCard`): renders the
  two-thumbnail choice row (reusing the panel's result-thumb styling).
- `App/Screens/EditorFlowView.swift`: passes the already-present
  `services.imageStudio` into the coordinator (one line).

## Error handling

- Service failures land on the existing calm failure card with Try
  again; the prompt refills. No partial canvas state is possible
  because mutations happen only in `settle`/placement.
- Clarify outcomes (no photo, ambiguous photo) reuse the existing
  clarify card with chips; zero canvas change.
- A candidate that fails to decode is dropped; if both fail, the turn
  fails with the standard card (mock never exercises this).

## Testing

- Kit: classification tests per family (one English + one Chinese cue
  each), target-resolution tests (selected / only-one / ambiguous),
  instant-intent undo restores in one step, coordinator test for the
  imageChoices phase -> placement -> receipt flow with the mock studio.
- UITests (mock studio, deterministic): "draw a paper crane" -> two
  thumbnails -> tap one -> element lands + receipt; "make it black and
  white" on the sample photo -> instant receipt; ambiguous-photo ask ->
  clarify card, canvas unchanged.
- Standard gates: swiftlint --strict 0, full Kit + UITest suites green
  on the shadow simulator, film-strip pass against live :8002 before
  install.
