# Mira sees the canvas -- design

Approved by Meng on 2026-08-08, section by section, then revised after
an adversarial review pass that found three ways the first draft would
have shipped bugs (a hardcoded 360pt canvas width, an undo step per
changed field, and point sizes applied without re-measuring the text
box). Mira on the canvas today receives a flat string of words and
nothing about the page's appearance; this spec gives her the geometry
always, the pixels on demand, and the ability to act on both.

Tracked as miranote-api#38 (backend, lands first) and
miranote-ios#41 (app).

## Goal

Four families of asks must work on the canvas. All four are blocked
today by the same thing -- Mira cannot see the page.

1. Questions about the page: "how does this page look", "is anything
   crowded", "what is in the photo on the left", "are those two text
   blocks overlapping".
2. Nudging one element: "move the title above the photo", "make this
   picture bigger", "pull it toward the middle", "line those two up".
3. Rearranging the whole page: "tidy this page up", "排一排".
4. Style and content that follow what is on screen: "the title is too
   small", "this color fights the background", "write a line for this
   picture".

## What Mira gets today, for the record

`ChatNote(page:)` (Chat.swift:70) flattens the page into title + one
newline-joined body. It carries text, sound notes, sticker prompts,
and the import-time vision sentence for each photo. It carries no
position, size, rotation, z-order, point size, color, or background,
and no rendering of the page. The journal system prompt states the
limit outright: "you cannot see its pixels".

Two consequences worth naming. `.organize` cannot be model-driven, so
it is a hardcoded single-column stack (`quickOrganize`). And the
canvas classifier is a keyword ladder (`MiraIntent.classify`), so
anything phrased outside its vocabulary falls to `.converse` and gets
conversation instead of action.

Bug found while specifying: the comment on `ChatNote(page:)` says
"in reading order" but it iterates `page.items`, which is creation
order -- neither z-order nor top-to-bottom. `composedMemory()` sorts
by y for the same job. The page map below fixes this.

## Non-goals

- The chat screen is untouched. `MiraChatView` sends library pages as
  flat `ChatNote`s; those are pages the user is not editing and do not
  need geometry.
- No new element kinds, no delete-by-Mira, no text rewriting through
  `edit_page` (the existing text transforms own that).
- No `restyle_photo` tool this round. Free-form photo restyling stays
  on the keyword path; the tool_trace pattern makes it a cheap
  follow-up once `set_background` proves out.
- No background prompt in the data model (see Follow-ups).
- No real-device networking. Backends stay on localhost per
  `MiraNoteConfig`.

## Approach: geometry always, pixels on demand

Rejected: sending only a rendered screenshot to a vision model. A
vision model returns regions it can see, not the app's element ids, so
targeted edits would need a parallel element list anyway -- the same
work, plus a per-turn vision bill and Mira's reasoning split across
two models and two backends.

Rejected: geometry only, no pixels ever. Three of the four families
need nothing but geometry, but "does this look good" and "what is in
that photo" genuinely need the image.

Chosen: the page map is always in context and is the source of truth
for facts (what is where, how big, what overlaps). A rendered page
image rides along with every canvas turn, but is only spent when the
model calls `look_at_page` -- impressions only: crowding, balance,
how the colors sit.

## Where it plugs in

Only the `.converse` branch changes. The keyword fast paths stay: they
are instant, free, and correct for the phrases they match.

    canvas command bar
      +- MiraIntent.classify
           +- keyword hit -> unchanged (polish, filters, photo edits,
           |                 stickers, generation ...)
           +- no hit      -> .converse   <-- rebuilt
                 |
                 |  sends: page map (numbered elements + boxes)
                 |         + rendered page image
                 v
             :8003 /chat, canvas mode
                 |  model reasons over the map
                 |  needs pixels -> look_at_page -> :8002 -> Gemini
                 v
             reply text + optional tool calls
                 |
                 v
             device validates -> applies once -> receipt + Revert

Three existing mechanisms make this cheap, and the design deliberately
reuses each rather than inventing a parallel one:

- Rendering a page: `StaticPageView` (PageRendering.swift:8) already
  renders a whole page offscreen for reading mode and export.
- Backend calling backend: `text_client.py` (:8001) and
  `retrieval_client.py` (:8004) already do this; the look tool adds
  `image_client.py` (:8002) in the same shape.
- A tool call as an instruction to the app: `create_note` already
  works this way -- the server stores nothing, the app reads the call
  out of `tool_trace` (LiveChatService.swift:78).

Decided by Meng: the `tidy` / `organize` / `arrange` / `layout`
keywords move off the local fast path onto the model, so "tidy the
layout" (including the suggestion chip) becomes a network turn with
the working indicator instead of an instant local rearrange.
`quickOrganize` survives as the offline fallback, not as the primary
path.

## The page map

`ChatRequest` gains `page` alongside `notes`. Canvas turns send
`page` and an empty `notes`; the chat screen keeps sending `notes`
with no `page`. The backend treats "`page` is present" as canvas
mode: the page-edit tools are released only then.

Rendered as a compact block, not JSON -- fewer tokens, and the model
reads a labeled table fine:

    [The page open in the editor -- 393 wide, 812 tall, default
    gradient background]
    t1  text     (28,40)   304x44   30pt      "Noodle shop by the bridge"
    p1  photo    (40,110)  280x200  film      a steaming bowl on a wooden counter, evening light
    t2  text     (28,336)  304x120  15pt      "We found it by accident, ..."
    s1  sticker  (250,300) 80x80    tilted 8  "a tiny paper boat"
    a1  sound    (40,470)  44x44              "the rain outside"
    [End of page]

Rules:

- **The canvas is device-width, and the map says which width.** The
  board is `.frame(maxWidth: .infinity)` and reports its real width
  into `editor.canvasWidth` (CanvasBoardView.swift:105,113), so
  element positions are stored in device points -- 393 on an iPhone
  15, 440 on a Pro Max, far more on iPad. 360 is only the width the
  reading/export renderer draws at. The map therefore carries this
  device's actual canvas width, and every coordinate in and out is in
  that same space. **No layer of this feature may hardcode 360**; a
  map that says 360 on a 393pt screen puts "centered" 21pt left of
  center, and pushes "over to the right" off the visible page.
- **Handles.** `t`/`p`/`s`/`a` plus an index, assigned per turn and
  mapped back to `CanvasItem.ID` on device. UUIDs would burn tokens
  and invite transcription errors.
- **Exactly one map is ever in context, and it is always current.**
  `run_turn` appends the *composed* message -- context block included
  -- to the session history (chat_loop.py:52), and history runs 40
  messages deep. Left alone, turn 4 would show the model four
  contradicting maps, and because handles are re-numbered by y every
  turn, turn 1's `t1` may be a different element than turn 4's. The
  model would move the wrong thing with full confidence. So in canvas
  mode the history stores the user's raw words only, and the current
  map is injected fresh for each model call without being persisted.
  This matters far more than the equivalent staleness in `notes`:
  coordinates and handles are acted on, not just read.
- **Order.** Sorted by y, top to bottom. This is the fix for the
  creation-order bug above; "the first block", "the one above it" now
  mean what the user means.
- **Boxes, not centers.** `CanvasItem.position` is the element's
  center. The map emits top-left x,y plus width and height, because
  the questions being asked ("is the title above the photo", "do
  these overlap") are about edges. Device converts on the way out and
  on the way back in.
- **Defaults omitted.** No `tilted` when rotation is 0, no color when
  it is `ink`, no filter or frame when unset. The map stays short.
- **Photos** carry the import-time vision sentence (`ImageRef.summary`),
  including today's honest fallback when vision has not run yet.
- **Cap 24 elements, and say what was dropped.** Mirrors the existing
  `MAX_NOTES` / `MAX_BODY_CHARS` caps in journal.py. A silent
  truncation would read to the model as a complete page; the block
  ends with the count omitted when any were.

## Tools released in canvas mode

Three additions -- `edit_page`, the background pair, and
`look_at_page` -- on top of the existing journal set (text transforms,
`find_quote`, `create_note`), which is unchanged. Chinese trigger
phrases go in
`prompts/tool_descriptions.txt`, which is allowlisted for CJK
(`**/prompts/*.txt`); no CJK enters code.

### `edit_page(changes)`

The workhorse. One call is one canvas change, one receipt, one undo
step. Each entry names a handle and only the fields that change:
`x`, `y`, `w`, `h`, `size` (text point size), `color`, and `layer`.

`color` takes a palette name, not a hex value -- `TextBlock.colorName`
is resolved by the App layer. The tool description enumerates the
legal names so the model picks from the palette instead of inventing
"warm beige". `layer` takes `front` or `back` and means the same as
the existing `bringToFront` / `sendToBack` (but see the apply
section -- it must not call them).

`size` is a free point size clamped to 11-48, not one of the three
steps (13/17/30) the existing +/- intent walks. Decided by Meng: the
ladder cannot answer "just a little bigger", and the app already
places titles at 30 and captions at 15, so the ladder was never the
whole vocabulary anyway.

    move the title above the photo -> [{id:t1, x:28, y:24}]
    make this picture bigger       -> [{id:p1, w:320, h:228}]
    tidy this page up              -> [{id:t1,..},{id:p1,..},{id:t2,..}]
    the title is too small         -> [{id:t1, size:34}]
    the sticker covers her face    -> [{id:s1, layer:back}]

Families 2, 3, and the style half of 4 are all this one tool --
rearranging the page differs from nudging one element only in how
many entries the array has. No `move_element` / `resize_element` /
`align_elements` zoo.

If the model calls `edit_page` more than once in a turn, the app
merges every call into a single change set and applies it once.
Otherwise one turn would leave several receipts and several undo
steps behind. Within a merge, later calls win field by field, so a
model that corrects itself mid-turn lands its correction.

### `set_background(prompt)` and `clear_background()`

Separate because the clocks do not match: a chat turn is budgeted in
seconds, background generation runs up to 150s (`imageTimeout`).
The backend does no work -- it records the call in `tool_trace`, the
app reads it and runs the existing slow image path on its own budget.
This is `create_note`'s pattern, second use.

**The slow work is a new turn, not a continuation.** By the time the
app reads the instruction, the chat turn has already settled --
`turnTask` is nil and the phase is `.reply`. The app therefore starts
a fresh turn for the image work: bump `turnGeneration`, replace the
reply card with the working bar, and run under `imageTimeout`. Left
implicit, Stop would have nothing to cancel and a late receipt could
land on top of whatever the user did next.

### `look_at_page()`

Detailed below.

### Receipt text is derived by the app, not written by the model

One element moved -> "Moved the title."; three or more changed ->
"Rearranged the page."; point size only -> "Made the title bigger."
The receipt strip is a fixed UI element (Meng, 2026-07-09: one line,
check mark, changed copy, Revert, 6s auto-keep), so its voice must
stay steady. The model owns the conversational reply, where variety
is welcome.

## look_at_page

The app renders the page with `StaticPageView` and sends it with every
canvas turn. Nothing is spent unless the model calls the tool.

On call, the backend posts the image to :8002 `/describe`. That
endpoint's prompt is currently hardcoded for photos ("one warm,
concrete sentence"), so it gains an **optional `prompt` query
parameter defaulting to today's text**. The photo-import path is
unchanged; the canvas look passes its own prompt, asking about
arrangement, crowding, emphasis, and how the colors sit.

- **One look per turn.** `max_tool_iterations` is 6; uncapped, the
  model could look six times. A second call returns "you already
  looked at this page this turn" without a vision call.
- **JPEG, long edge 1536.** The canvas scrolls without limit, so a
  page can be 393x3000; at 2x that is enormous. Downscaling makes a
  very tall page coarse, which is acceptable: precision lives in the
  map, the image only carries impression.
- **Rendered at the real canvas width, not 360.** `StaticPageView`
  defaults `designWidth` to 360, but the model must be shown what the
  user is looking at. The look render passes `editor.canvasWidth`.
- **Failure is not turn failure.** If the render is unavailable (the
  App-layer closure unwired, as in tests and previews) or :8002 is
  down, the tool returns that it could not look and the model answers
  from the map.

The App layer owns rendering because `StaticPageView` lives in
`App/Sources/Screens/Reading/` while the coordinator lives in
MiraNoteKit. The coordinator gains `renderPage: (() -> Data?)?`,
wired by the view -- the same shape as the existing `prepareTurn`
closure.

Privacy: the page image leaves the device. Photos already do, at
import (`/describe`) and on edit (`/stylize`), so this introduces no
new category of data leaving.

## Timeouts

A ladder, innermost first, so exactly one clock can fire and the
user always sees the same message for the same situation:

| Layer | Budget | On expiry |
|---|---|---|
| `look_at_page` -> :8002 -> Gemini | 25s | tool reports it could not look; the turn continues on the map |
| canvas turn (`MiraCanvasCoordinator.timeout`) | 60s | stop, canvas untouched, words returned |
| the chat HTTP request itself | 75s, passed explicitly | never fires first |

The third row is a fix, not just a setting: `LiveChatService` calls
`postJSON` without a timeout today (LiveChatService.swift:70), so it
inherits URLSession's 60s default. Left alone against a 60s turn
budget, the two clocks race and the same failure surfaces under two
different messages.

Worst case inside 60s: 25s lost to a stuck look, then 35s for the
model to answer from the map.

## Applying edits on device

`MiraOutcome` gains `pageEdited([ElementChange], MiraReceipt)`.
`settle` applies it as one snapshot, one receipt, one Revert --
reusing Keep-pattern behavior (6s auto-keep, inline Revert, header
undo as the backstop) untouched.

### One undo step means bypassing the snapshotting helpers

`setTextPointSize` (CanvasViewModel.swift:215), `setTextColorName`
(:223), `bringToFront` (:314) and `sendToBack` (:320) each call
`beginChange()` themselves, while `resize`, `setText`,
`autosizeTextHeight` and `rotate` do not. Driving the apply path
through the first group would push one snapshot per changed field,
and `revert()` pops exactly one (`undo()`), so the user would tap
Revert on a five-element change and watch four fifths of it stay.
That breaks the promise the receipt makes.

So the apply path takes its own single `beginChange()` and then
mutates `memory.items` directly, in the style of `resize` / `setText`
/ `rotate`. It never calls the four snapshotting helpers. Either a
non-snapshotting variant of each is added, or the mutation is written
inline in the apply function -- an implementation call, but the
one-snapshot invariant is not.

### Point sizes are applied before positions, with a re-measure between

The existing text-resize intent never changes a point size alone: it
pairs `setTextPointSize` with `autosizeTextHeight` fed by
`Memory.estimatedTextHeight` (MiraCanvasCoordinator+Images.swift:163).
Skip that and 34pt text clips inside a box measured for 15pt.

It compounds within a single `edit_page`: the model computed its y
coordinates against the heights it saw in the map, so changing a
point size silently invalidates every position below it. The apply
order is therefore fixed:

1. apply `size` and `color` changes,
2. re-measure every touched text box with `estimatedTextHeight` and
   autosize it,
3. apply `x` / `y` / `w` / `h` / `layer`.

Positions win because they are what the user asked for most
literally; the re-measure sits between so the boxes are honest before
anything is placed against them.

### Guards

Run before anything is applied; all pure functions on device.

1. **Unknown handle -> skip that entry; unknown palette color -> drop
   that field, keep the rest of the entry.** Models occasionally
   invent a `t9`, or a color name that is not in the palette.
2. **Coordinates clamped into the page, at the real canvas width.**
   Nothing may be pushed off the sides of `editor.canvasWidth`; y may
   grow downward (the canvas scrolls) but never negative. Clamping
   against a hardcoded 360 on a wider screen would itself be the bug.
3. **Point sizes clamped to 11-48.**
4. **Every entry invalid -> treat the turn as a failure.** Showing a
   receipt when nothing landed would be a lie. Falls to the `clarify`
   card: Mira did not find the element and asks which one was meant.
5. **Nothing to arrange -> clarify, not an empty edit.** An empty
   page, or a page with one element, answers "tidy this up" with the
   clarify card rather than a receipt for a change that did nothing.

## Error handling

The existing `MiraFailure` taxonomy, and in every failing case the
canvas is untouched and the words are returned to the input bar.

- Backend down or turn timeout -> `retry` card (existing copy).
- Reply with no tool calls -> not an error; the normal reply card.
- Tool calls that all fail the guards -> `clarify` card.
- `look_at_page` failed -> not an error; the model answers from the
  map.

## Offline and mocks

`quickOrganize` stays as the fallback when the backend is
unreachable: a deterministic local rearrange beats a failure card for
"tidy this page". `MockChatService` gains canned page edits, so
previews, snapshot QA, and tests exercise the apply path without a
network.

## Testing

Swift:

- Page map: y ordering, handle assignment, center-to-corner
  conversion, omitted defaults, the 24-element cap and its stated
  remainder, and that the width in the header is `canvasWidth` rather
  than a constant (assert with a width that is not 360).
- Guards: unknown handle skipped, out-of-range coordinates clamped at
  a non-360 canvas width, point size clamped, all-invalid becomes a
  clarify failure with the canvas untouched, one-element page answers
  "tidy" with clarify.
- Apply: a change set touching point size, color, layer and position
  at once produces **exactly one** undo step -- the regression test
  for the snapshotting-helper trap; Revert restores the page whole; a
  canvas edit between receipt and Revert makes Revert decline
  (existing `receiptChangeCount` rule).
- Apply order: raising a point size grows the text box before the new
  positions land, and the result has no overlap the model did not
  ask for.
- Merging: two `edit_page` calls in one trace produce one receipt,
  with the later call winning field by field.
- `set_background` from tool_trace runs as a fresh turn: Stop cancels
  it, and its receipt cannot land after the user has moved on.

Python:

- Canvas mode gates the tools: `page` present releases the page
  tools, absent withholds them.
- Canvas mode stores raw words in history: after three turns the
  session holds three user messages and zero page maps.
- `edit_page` argument validation and the tool_trace shape the app
  parses.
- `look_at_page` calls the image client, and the second call in a
  turn short-circuits without one.
- `/describe` keeps its current output when no `prompt` is passed.

## Landing order

The work spans two repos and the api side must land first -- the app
cannot call tools that do not exist yet. Both PRs base on `main`
independently; nothing is stacked.

1. `miranote-api` (#38): canvas mode on `/chat`, the three tools, the
   `prompt` parameter on `/describe`, `image_client.py`.
2. `miranote-ios` (#41): the page map, the render closure, the guards,
   the apply path, the timeout ladder, mocks and tests.

## Found on the way, not fixed here

Reading mode and export render with `StaticPageView(designWidth: 360)`
while the editor lays elements out at the device width. On any screen
wider than 360 -- which is every current iPhone -- the exported long
image is already squeezing the page. This predates this work and is
not in its scope, but it is the same root confusion, so it should get
its own ticket rather than being discovered again later.

## Follow-ups

- `Memory.backgroundFileName` records a file name only, so the map
  cannot say what the background looks like; `look_at_page` covers it
  for now. Storing the generating prompt is a persisted-format change
  and gets its own decision.
- `restyle_photo` as a fourth tool, once `set_background` has proven
  the tool-as-instruction path a second time.
- Real-device networking will make a per-turn image upload real cost;
  the answer then is to upload only after the model asks, or to drop
  quality further.
