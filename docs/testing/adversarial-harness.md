# Adversarial QA harness

Scripted tests walk paths someone already imagined. MiraNote's real bugs are
about the order and timing of events across features, and about doing the
same thing several times. This harness finds those mechanically. Four parts:

| Part | Where | Runs in CI |
|---|---|---|
| Random-sequence models with invariants | `MiraNoteKit/Tests/MiraNoteKitTests/Harness/` | yes (`swift test`) |
| Gate mocks and ordering tests | `Harness/GateMocks.swift`, `Harness/GateOrderingTests.swift`, `ChatComposerTests.swift` (`ChatVoiceOrderingTests`), `App/Tests/PhotoEditOrderingTests.swift` | yes |
| Debug state probe | `App/Sources/UITestServices.swift` (`DebugStateProbe`), `CanvasScene.swift` (`debugState`) | DEBUG + `-UITEST` only |
| Simulator monkey | `App/UITests/MonkeyUITests.swift` | no (skipped unless `MONKEY=1`) |

## 1. Random-sequence models (Kit)

`SequenceHarness` runs many seeded sequences of user actions against a model
and checks invariants after every step. On a failure it shortens the
sequence (same invariant still failing) and prints the seed, the shortened
steps and a replay line. Turn that into a named regression test next to the
code it broke.

Models:
- `CanvasSequenceModel` -- `CanvasViewModel` + `TextFit` driven as the
  canvas scene drives them (autosize while typing, re-measure on every
  recorded change, previews kept on Done, empty blocks dropped when a
  session ends, Mira landing titles, moves and backdrops mid-session).
  Invariants: no fit creates an overlap; a dragged element is never lifted
  by a later fit; toggle pairs (grow/shrink, curated sets A/B/A, typing then
  erasing, a rewrite then Original) return every element exactly on a
  settled page and reach a fixpoint within four rounds on any page; Cancel
  restores the session start (exactly, when nothing else happened) and takes
  back only the block's own pushes; Mira's Revert undoes only Mira's change;
  JSON round trip is identity; no empty block outside a writing session;
  undo all the way back gives the starting page.
- `ChatStagingModel` -- `ChatViewModel` photo staging with a gate per pick:
  picks arrive, fail, stall, are removed or their batch cancelled, in any
  order. Invariants: Send is never held once nothing loads; no photo lost or
  duplicated; order kept within a batch; at most four; `canSend` honest.
- `ChatVoiceModel` -- hold to talk with a gated mic start and transcriber.
  Invariants: never two mics, none left on when idle, "Transcribing..."
  never sticks, words land at most once.

Run (CI defaults: 500 sequences per model, fixed seed, each under 30 s):

    cd MiraNoteKit
    swift test --jobs 2 --filter SequenceTests

Knobs (environment):
- `HARNESS_SEED=<n>` base seed; `HARNESS_SEQUENCES=<n>`; `HARNESS_LENGTH=<n>`
- `HARNESS_LONG=1` local soak: 20,000 sequences x 80 steps, time-based
  seed (printed). About 6 minutes for the canvas model.
- `HARNESS_TRACE=1` prints the state after each step of the shortened
  failing sequence.

To replay one failure, use the line the failure prints, for example
`HARNESS_SEED=104377848497032 HARNESS_SEQUENCES=1 HARNESS_LENGTH=10`.

Adding a model: conform to `SequenceModel` (`init(seed:)`, `nextAction`,
`apply`, `violations`, optionally `finish`, `tearDown`, `trace`). Actions
must be self-contained (elements by index modulo the count, never by id) so
a shortened sequence still replays.

## 2. Gate mocks

`GateQueue` holds every call to a service until the test releases it (also a
call not made yet: it then returns at once). A call ignores cancellation,
like a request already on the wire. Fakes: `GatedStudio` (stylize, cutout,
outline, describe, generate), `GatedTranscription`, `GatedChat`, and
`MicLedger` / `GatedRecorder` (held mic start, `live` counts mics on). They
use public Kit API only; `project.yml` compiles the file into the app's unit
tests too.

Ordering tests enumerate every interleaving of a result with the user's
flow:
- `GateOrderingTests` -- Mira's title released before, during and after a
  writing session ending in Done, Cancel or Undo; and the background
  "Apply to this page" painting landing on the page when it arrives.
- `PhotoEditOrderingTests` (app) -- an AI photo edit released at every point
  of Done, Cancel, reopen, B&W, delete, canvas undo, another photo, a scene
  round trip.
- `ChatVoiceOrderingTests` (in `ChatComposerTests.swift`) -- the late
  mic-start failure of a slid-away take.

The canvas dictation take (text and Mira strips) lives in `CanvasScene`
view state and is not unit-testable without extracting it; it is covered by
`DictationOwnershipUITests` with the delay hooks and by the monkey.

## 3. Debug state probe

In DEBUG builds launched with `-UITEST`, every scene carries an invisible
element `debug.state` whose label is JSON, refreshed four times a second:

- `scene` (`canvas`, `sticker`, `chat`, `home`), `micLive` (mock recorders
  on, all of them), `listening` (what the strips, the Voice recorder or the
  chat composer show: `text`, `mira`, `voice`, `starting`, `chat`);
- canvas: `recorderHeld`, `writing` (block id), `writingDown`,
  `pendingTakes`, `photoEditing`, `photoEditors` (id, working),
  `undoDepth`, `selected` (the selected element's id), `importing`,
  `pageWidth`, `backdrop`, `backdropDescribes` (the backdrop's stored
  description), `pageColor`, `paper` (the paper kind), `elements` (id,
  kind, text, x, y, w, h);
- sticker: `busy`, `drafts`, `undoDepth`, `writing`, `scrollOffset` (the
  canvas scroll the page preview opens on, page points);
- chat: `staged`, `loading`, `responding`;
- render cost: `sceneBodies` (times the canvas scene's body ran) and
  `imageDecodes` (display images decoded), both since launch --
  `DragRenderUITests` reads them before and after a drag; `liftedWidth`
  (the last dragged copy's on-screen width: it must match the element's).

Delay hooks (launch arguments, `-UITEST` only): `-TRANSCRIBE_DELAY <ms>`,
`-TRANSCRIBE_FIRST_DELAY <ms>`, `-MIC_START_DELAY <ms>`, `-AI_EDIT_DELAY
<ms>`, `-CHAT_DELAY <ms>`, `-IMPORT_DELAY <ms>`, `-EXPORT_DELAY <ms>`,
`-GENERATE_DELAY <ms>`, `-TEXT_MODE_BEAT <ms>`, `-HOLD_INTERRUPT_AFTER
<ms>`. Transcript hooks: `-NUMBER_TAKES` (each take's words end with its
number, in the order the takes were let go) and `-FAIL_FIRST_TAKE` (the
first take fails). Screenshot hooks: `-STICKER_SAMPLE <SF Symbol>` (a
die-cut sticker of that symbol stands in for the made one) and
`-OWNER_SHOTS` (keeps the mock services but hides test-only controls such
as the Samples pill, so frames match a Release build).

## 4. Simulator monkey

`MonkeyUITests` launches with one random delay hook and performs random
taps, long-presses, drags, tool switches, Done / Cancel / Undo, typing,
strip holds, recorder buttons, and Home / background / foreground. After
every event it reads the probe and checks: no mic on unless something shows
it listening (re-checked after 1.2 s), Done never leaves the block it ended
overlapping something new, no element off the page, no crash. A failure
prints the seed, the last 30 events and the probe JSON. It avoids controls
that open system UI (picker, camera, share, Settings).

The test reads `MONKEY=1`, `MONKEY_SEED` (default: time-based, printed)
and `MONKEY_EVENTS` (default 300); xcodebuild passes them on from the
`TEST_RUNNER_` prefixed variables. Run one batch (keep batches at 1000
events or fewer, one simulator):

    TEST_RUNNER_MONKEY=1 TEST_RUNNER_MONKEY_SEED=1001 \
      TEST_RUNNER_MONKEY_EVENTS=1000 xcodebuild test \
      -project MiraNote.xcodeproj -scheme MiraNote \
      -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
      -jobs 2 -parallel-testing-enabled NO \
      -only-testing:MiraNoteUITests/MonkeyUITests

About 1.6 s per event (1000 events, about 27 minutes). Every event is
logged as `[monkey-event]`; the summary line counts what the run saw (probe
reads, writing, mic live, photo editor), so a run that checked nothing
fails.

`OwnerTourUITests` is the deterministic companion: it walks every screen
and tool, checks each step lands and leads back and that no tappable
control sits mostly under another, and photographs each screen (into
`SHOTS_DIR` when set, `TEST_RUNNER_SHOTS_DIR` for xcodebuild). Run it on
the smallest (16e) and a large phone and look at the photos.

## 5. Mutation check

For each Kit function changed by a fix: break it on purpose (flip a
condition, drop a guard), run `swift test --filter` on its tests and the
sequence models, and confirm something fails. A mutation nothing catches is
a missing test: add one. Record survivors and the tests added in the plan's
Iterations.

## Before pushing

Sequence models green (and one `HARNESS_LONG=1` run for a change to canvas
or chat logic), ordering tests green, a monkey batch on the touched feature,
no surviving mutation on changed Kit logic.
