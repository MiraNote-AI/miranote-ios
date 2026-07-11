# Widening the edit verbs -- design

Approved by Meng on 2026-07-10 (inline, after testing #21 on device:
natural phrasings fell through to chat). Refs issue #23. Ships inside
PR #22 -- it builds directly on the sticker-edit family and stacked
PRs are not allowed.

## Goal

The canvas ask bar recognizes how people actually phrase an edit. One
shared verb list gates BOTH word-edit families (sticker edit and photo
free edit):

- English: "make ", "change ", "turn ", "edit ", "redraw ",
  "restyle ", "recolor ", "repaint ", "give ", "add ", "put ".
- Chinese: "把", "改", "换", "变", "给".

So "change the sticker to blue", "turn the sticker into a dragon",
"add a hat to the sticker", "贴纸改成蓝色", "给贴纸加顶帽子", and
"change the photo to feel like winter" all route to the edits they
mean.

## Unchanged boundaries

Everything that guards routing today stays, test-pinned: definite
sticker mentions only ("add a sticker of a cat" still converses);
generation cues ("draw ", "画") win first; conversion phrases ("into a
sticker", "抠成") still convert the photo; a sticker-flavored ask
never touches a photo; asks with no photo/sticker mention are
untouched (text transforms, caption, organize, converse).

## Non-goals

- No verbless edits ("贴纸蓝一点") -- too loose; ordinary remarks
  about a sticker would trigger redraws.
- No LLM routing (evaluated and deferred in the 2026-07-10 image
  intents spec).
- Known accepted looseness: "add words to the photo" becomes a photo
  stylize (the model paints words in) -- the same ambiguity class the
  photo family already has with "make".

## Change

`MiraIntent+Image.swift` gains one helper, used by both call sites:

- `static func hasEditVerb(_ lowered: String) -> Bool` -- the list
  above.
- `stickerEditIntent`: `editVerb` line switches to the helper.
- `photoIntent`: `freeEdit = mentionsPhoto && hasEditVerb(lowered)`.

No other component changes; the pipeline, targeting, settle, UI, and
backend are untouched.

## Testing

- Sticker family: "change the sticker to blue", "turn the sticker
  into a dragon", "add a hat to the sticker", "贴纸改成蓝色" (no 把),
  "给贴纸加顶帽子" -> editSticker; "add a sticker of a cat" ->
  converse.
- Photo family: "change the photo to feel like winter" -> editPhoto.
- Full existing suites stay green (the boundary tests from #21/#22
  double as regressions here).
- Gates: swiftlint --strict 0, full Kit + app suites on the shadow
  simulator. No live probe: no network path changes; the live pass
  from earlier today exercised the same pipeline.
