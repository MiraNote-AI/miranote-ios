# Full-Feature Night Sweep — plan & ledger

REQUIRED SUB-SKILL: run-loop
Refs MiraNote-AI/miranote-ios#13
Branch: `fix/full-feature-sweep`
Night of 2026-07-09 -> 2026-07-10. All times CDT.

## Goal

Walk every feature the v2.1 design defines, on the simulator, the way a
user would; collect film-strip evidence; fix what is broken; ship ALL iOS
fixes as ONE reviewable PR by 08:30.

Sources of truth: the v2.1 design artifact + memory `project_ui_flow_v2.md`.
Design decisions there are not reversed silently — a mismatch with the doc
is a bug; a doubt about the doc itself goes to the morning report.

## Acceptance criteria

- [ ] Every checklist area below toured on the shadow simulator
      (35B7DA99) with film-strip evidence under the session scratchpad
- [ ] Each shipped fix carries a locking test (Kit or UITest)
- [ ] `swiftlint --strict` = 0; full MiraNoteKit + UITest suites green on
      the shadow simulator from a clean state
- [ ] Fresh-context subagent review (criteria + `git diff main...HEAD`
      only) returns DONE
- [ ] App installed on the user simulator (6E165F5B), binary timestamp
      verified
- [ ] ONE PR open on miranote-ios, CI green, self-explanatory body
      (HUMAN: review + merge)
- [ ] Morning report appended to this file: findings table
      (found -> fixed | deferred | by-design), skips with reasons

## Stop conditions

- Iteration cap: 5 per finding-loop (one finding = one mini-loop).
- No-progress: 2 consecutive iterations without movement -> mark DEFERRED
  with evidence, move to the next finding.
- Budget: fixes FREEZE at 07:00; 07:00-08:00 clean-state suites +
  fresh-context review + install; PR open by 08:30 with the report done.
  Last night ran overdue; the freeze is hard this time.
- Escalation (write a morning note, do not act): protected paths; any
  check-weakening; backend work larger than a small contained fix.

## Scope rule

All app fixes -> this branch, one PR. If a finding is backend-caused,
prefer an app-side fix; touch the backend only if the feature is otherwise
untestable, as its own minimal PR on miranote-api, flagged in the report
(cross-repo work cannot share one PR).

## Feature checklist (tour order)

1.  Home / library: cover grid, caption dates, create page, search
    (plain text, CJK, photo summaries)
2.  Starter drafts materialize with sane layout
3.  Canvas basics: add/edit text, autosize, drag, rotate, select/deselect,
    long-press delete, undo/redo
4.  Text editor: Polish flow (:8001)
5.  Sound: arm -> record -> review -> place
6.  Image tab: Library import + auto-describe (:8002), AI image + style
    chips, samples row (UITEST)
7.  Photo edit: Filters / Frame / Make sticker (:8002 local models) /
    Ask AI stylize + re-describe
8.  Mira chat (:8003): multi-turn, page grounding incl. photo summaries,
    draft -> "Put this on the page", clean placed text, dismissal,
    receipt capsule + Revert
9.  Suggestions: Tidy the layout; Add a soft title (AI)
10. Quotes (:8004) surface where designed
11. Export + settings
- SKIP: dictation/voice — :8000 is reserved for another project on this
  machine (standing rule; noted in the report).

## Working rules (lessons already paid for)

- Explicit `cd` starts every commit/install; verification and commits
  never share one command chain; installs verified by binary timestamp.
- Film-strip probes are throwaway and deleted before any commit.
- Probe grammar: `waitForExistence` before first taps; deselect before
  drag; unique fresh-canvas text for assertions.
- Ledger lines carry wall-clock timestamps.
- DerivedData stays pinned to `MiraNote-dkuprfnxlknmjmfxgtrgsugxgwii`.

## Iterations

(appended as the night runs; format:
`N. HH:MM <what changed> -- criteria X/Y, <verify summary>`)

1. 00:12 setup -- repos synced to fresh main, branch cut, backends
   8001-8004 healthy (live chat + describe probes pass), app rebuilt and
   installed on the shadow sim (binary 00:03), both sims booted, mic and
   photos permissions pre-granted, two seed photos generated via live
   /generate and added to the sim photo library.
2. 00:12 tour A filmed (areas 1, 3, search; 103 frames): canvas basics
   all pass (type, select, drag, long-press menu, delete, undo, Done
   files 2->3); reading/edit round-trip passes; search -> hit -> reading
   passes; live journal reply grounded in the page and honest about the
   unseen photo. Findings F1, F2 opened.
3. 00:19 tour B filmed (areas 4-7; 195 frames): armed-not-recording
   sound flow passes; live Polish lands with single-line receipt +
   Revert and re-fitted block; live generate (style chip, Working state,
   result placed) passes in 31s; photo edit sections/filters reached.
   Picker probe tapped the privacy banner icon instead of a grid cell --
   probe bug, import re-proved in tour C. Findings F4, F5 opened; PB1
   (keyboard capsule) resolved not-a-bug on film.
4. 00:31 tour C filmed (areas 8-11 + F5 evidence; 207 frames): live
   converse lands the draft body directly with "Added a few words."
   receipt (the shipped design -- probe expectation was stale); soft
   title lands live but OVERLAPS existing words (F8 opened, the fix of
   the night); tidy suggestion works; abandon-then-relaunch loses the
   words on film (F5 confirmed); export sheet correct incl. Advanced
   row, but save hit the photos-add permission alert (probe env: grant
   photos-add, done); :8004 confirmed unwired (F7).
5. 00:46 fix batch coded -- F8 measured-title landing with page
   push-down (MiraCanvasCoordinator.landTitle); F2 ChatMarkdown (Kit) +
   chat bubble + strip adoption + scripted reply carries ** on purpose;
   F4 StickerFavoritesStore.pruned + panel adoption; F5 finish() files
   non-empty canvas on Home AND Done + onAutosave on scenePhase
   background; F7 README truthful about :8004. Locks: 6 new Kit tests
   (129/129 green), 3 new UITests queued. swiftlint --strict: 0 after
   extracting landTitle (function cap) and renaming a probe param.

## Findings

| # | Area | Symptom | Evidence | Status |
|---|------|---------|----------|--------|
| F1 | Home | Collection cards show a plain color block | tourA f0016 vs f0022 | BY DESIGN (book-spine card; HomeView.swift comment). Report notes a cover-thumbnail idea as a future design question. |
| F2 | Chat | Assistant bubbles render literal `**` markdown | tourA f0078 | OPEN -> fix: inline-markdown rendering (Kit helper + bubble/strip adoption), Kit test lock |
| F4 | Image panel | MY STICKERS row renders 6-7 blank tan squares | tourB f0086/f0128 | OPEN -> root cause: mock-era 8x8 tan debris persisted in favorites; fix: usability filter + prune, Kit test lock |
| F5 | Editor | Home button discards a non-empty canvas; app kill loses all words | code: EditorFlowView onExit; tourB counts static at 3 | OPEN -> fix: Home files non-empty canvas (file() is id-idempotent), file on scenePhase background; UITest lock |
| F6 | Editor | Editing an old page then Done might move it to Daily Log | code read | NOT A BUG: HomeViewModel.file replaces in place by id |
| F7 | Docs | iOS README maps a "quotes" feature to :8004 but the app has no :8004 client | rg MiraNoteConfig | FIXED (README row replaced with a truthful roadmap note) |
| F8 | Mira | AI soft title lands on top of existing words (fixed 60pt box, no push-down) | tourC f0097 | FIXED (measured box + page slides down; Kit test locks frames apart + one-undo revert) |

## Morning report

(written before 08:30)
