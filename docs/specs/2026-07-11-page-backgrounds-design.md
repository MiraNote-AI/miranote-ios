# Page backgrounds -- design

Approved by Meng on 2026-07-11 ("both": new default gradient per the
provided mockup AND per-page AI backgrounds through Zhaoyan's
pipeline). Refs issue #24.

## Goal

1. The default page stops being flat paper: a full-bleed peach-to-plum
   gradient (per the mockup) in the editor, reading mode, covers, and
   export.
2. A page can carry its own AI-generated background: Mira asks like
   "give this page a sunset background" / "换个星空背景" run the
   :8002 /generate background command (Zhaoyan's pipeline -- prompt
   expansion, edge-to-edge journaling rule, 9:16), return two
   candidates in the existing picker, and the tapped one fills the
   page, persists with it, and undoes in one step.
3. "remove the background" / "去掉背景" clears back to the default
   instantly, one undo.

Known deviation, decided by Meng: the default look departs from the
2026-07-08 UI walkthrough's cream paper. Text legibility on the darker
lower half is a HUMAN taste call flagged in the PR.

## Non-goals

- No panel/button entry for backgrounds (Mira-only this round).
- No filters/frames on backgrounds; no per-collection defaults.
- No backend changes: the background command already exists.
- The "draw a picture uses the background command" misuse is NOT fixed
  here -- it needs a new api command (follow-up issue, next PR).

## Data model (hard-to-reverse, flagged)

`Memory` gains `backgroundFileName: String = ""` (empty = default
backdrop). Codable via the existing decodeIfPresent pattern, so old
saves decode to "" and render the new default; new saves remain
readable by the running build only (same as every prior field
addition). The file itself lives in ImageFileStore like photos and
stickers.

## Rendering

New shared `PageBackdrop` view (App layer): given a Memory, renders
the background image full-bleed (`scaledToFill`, clipped to the
24-corner rounded rect) when `backgroundFileName` resolves in the
ImageFileStore, else the new default gradient
(`Palette.backdropDawn` 0xF0B78E top -> `Palette.backdropDusk`
0x702E4E bottom). Consumed by BOTH the editor's `paper`
(CanvasBoardView) and `StaticPageView` (PageRendering.swift), which
today duplicate the old gradient. Hairline border and tap-to-deselect
behavior stay in their current owners. A background whose file is
missing (cleaned store) renders the default -- never a hole.

## Mira intent family

Checked BEFORE generation in the router (a background ask often
contains "draw"/"画"), and only when the ask mentions
"background"/"背景"/"底色" and neither "photo" nor "sticker" words
(cutout asks like "remove the photo's background" must keep falling
through to their own families).

- **setBackground(prompt)** -- background mention + an edit verb or a
  generation cue ("give this page a sunset background", "draw a starry
  background", "换个星空背景", "来个日落渐变的底"). Slow work
  (imageTimeout, verb "Painting the backdrop..."); performs
  `generate(kind: .background, prompt: ask)` and returns the
  two-candidate outcome.
- **clearBackground** -- "remove the background", "no background",
  "default background", "去掉背景", "清空背景". Instant: receipt
  "Cleared the background." / "Undo restores it.". Clearing when
  already empty still succeeds with the same receipt (harmless).

The two-candidate phase generalizes: `imageChoices` carries
`ImageChoicePlacement` (picture / sticker / background) instead of the
`sticker: Bool`. Placement for background saves the file and calls the
new `CanvasViewModel.setBackground(fileName:)` (beginChange inside;
one undo), receipt "Set the page background." The picker card renders
background candidates with a taller 9:16 thumb.

New mutator file `CanvasViewModel+Background.swift`:
`setBackground(fileName: String)` -- beginChange, assign; clearing
passes "".

## Error handling

- Service failure/timeout: existing calm failure card, prompt refill,
  zero canvas change.
- Discarding candidates (xmark) leaves the page untouched, no
  snapshot.
- Undo after placement restores the previous background (including
  "none"), because setBackground snapshots the whole memory like every
  mutator.

## Testing

- Kit: classification (EN + ZH set cues, clear cues, "remove the
  photo's background" stays out of the family, generation/sticker asks
  unaffected); setBackground/clear mutators one-undo; full turn with
  scripted studio (choices -> place -> memory.backgroundFileName set ->
  receipt; clear -> ""); decode of a legacy Memory JSON without the
  field.
- UITests (mock studio): "give this page a sunset background" -> two
  choices -> tap -> receipt, then undo via header button restores;
  clear ask -> receipt.
- Standard gates: swiftlint --strict 0, full Kit + app suites on the
  shadow simulator, live film-strip against :8002 (real pipeline
  output fills the page edge-to-edge) before install.
