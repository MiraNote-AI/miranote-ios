# Meeting Bug Sweep (2026-07-11) -- plan & ledger

REQUIRED SUB-SKILL: run-loop
Refs MiraNote-AI/miranote-ios#28
Branch: `fix/meeting-0711-bug-sweep` (worktree `miranote-ios-wt-bug-sweep`)
Base: cae36da (main after ios#27)

## Goal

Reproduce, fix, and lock the five defects Jason was assigned at the
2026-07-11 meeting (issue #28). Image-related findings from that meeting
are Meng's and already landed (ios#25/#27, api#32) -- out of scope here.

Findings:

- F1 Mira chat: "find my note" ask lands the user on Home instead of the
  found note / staying in the conversation.
- F2 AI quick-create note fails when the ask is written in Chinese.
- F3 Audio recording unresponsive.
- F4 Text expand: no loading state while the request runs; bullet points
  in the result render as literal markers, not bullets.
- F5 Canvas text intermittently lost, later reappears duplicated.

## Acceptance criteria

- [ ] Each finding reproduced on the shadow simulator (iPhone 17,
      0DB498B2) with film-strip evidence under the session scratchpad,
      or recorded as not-reproducible on this base with evidence
- [ ] Each shipped fix carries a locking test (Kit or UITest); view-layer
      regression tests ship with mutation evidence
- [ ] swiftlint --strict = 0
- [ ] MiraNoteKit suite green; full `xcodebuild ... build test` green on
      the shadow simulator from a clean state
- [ ] Fresh-context subagent review (criteria + `git diff main...HEAD`
      only) returns DONE
- [ ] ONE PR open on miranote-ios referencing #28, CI green
      (HUMAN: review + merge)

## Stop conditions

- Iteration cap: 5 per finding-loop (one finding = one mini-loop).
- No-progress: 2 consecutive iterations without movement on a finding ->
  mark DEFERRED with evidence, move on.
- Escalation (report, do not act): protected paths; check weakening;
  work growing beyond issue #28 (e.g. new feature asks from the meeting:
  library button, quick organize, TestFlight -- separate loops).

## Scope rule

App fixes only, this branch, one PR. Backend-caused findings get an
app-side fix where sensible; a backend change would be its own minimal
miranote-api PR, flagged here.

## Environment

- Backends: 8001 text, 8002 image, 8003 chat, 8004 retrieval,
  8005 voice -- all healthy at loop start.
- Shadow simulator: iPhone 17 (0DB498B2-BAB5-429A-8577-41B380976340).
- User simulator (verified installs only): iPhone 17 Pro (FB498BEA).
- Probes are throwaway, deleted before any commit.

## Iterations

(appended as they complete)

1. F1 probed live on the shadow sim. Opening a hit works (film f040);
   the defect is the way BACK: reading.back landed on Home with the
   conversation gone (probe asserts failed). Root cause: onOpenPage
   dismissed the chat cover and pushed the note onto the home stack.
2. F1 fixed: found pages now present OVER the chat (fullScreenCover on
   a chatHit state); back returns to the intact transcript -- film shows
   user message, hits row, and live reply all preserved. Locking test
   testFindHitRoundTripKeepsConversation ships with mutation evidence:
   FAILS with the fix stashed, passes restored. swiftlint --strict 0.
   Criteria progress: F1 closed, 4 findings to go.
3. F2 NOT REPRODUCIBLE on this base: live probe (Chinese ask via the
   simulator pasteboard, real :8003) produced the draft card, and it
   opened as a clean Chinese page in the editor (film). Backend traces
   confirm create_note fires for explicit and casual Chinese asks.
   Likely fixed by the 07-10 api journal-mode/docs-root work before this
   loop started. No app change.
4. F3 record path healthy in both variants on the shadow sim: pre-granted
   mic, and first-run permission alert -> Allow -> recording (films).
   Root cause of the meeting report identified as environment skew:
   ios#16 pointed dictation at :8005 on 07-10, but long-running local
   backends still served voice on :8000 (this machine had nothing on
   :8005 until this loop started it). Fix is operational: restart
   start-all.sh after pulling miranote-api. No app change; playback's
   silent return on a missing sound file noted for the report.
5. F4 probed live: the loading affordance EXISTS (working bar "Expanding
   the text..." + Stop, film f035; BreathingLock covers the block), so
   the no-loading half is stale on this base. The bullet half is real:
   /expand output and drafts carry "- " lines and both canvas display
   and reading mode printed them raw. Fixed: ChatMarkdown.withBullets
   swaps leading -/* markers for bullet glyphs (indentation kept,
   mid-sentence dashes untouched); canvas display and reading mode now
   render through ChatMarkdown; editing still round-trips the raw
   characters. Locks: 2 Kit tests + TextRenderingUITests (mutation
   evidence: UITest FAILS with the display fix stashed). Kit suite
   green, swiftlint --strict 0. F2-F4 closed, F5 to go.
6. F5 NOT REPRODUCIBLE on this base. Two probe journeys under -UITEST:
   (a) file -> read -> edit -> Done keeps exactly ONE entry (file()
   replaces by id, verified in code and on screen); (b) background
   mid-edit (autosave fires) -> resume -> more words -> Done: one entry
   carrying all words, no lingering autosave snapshot. Both passed.
   Likely explanation: the meeting build predated d402711 (autosave for
   real, merged 07-10 evening) -- same staleness as F3. The one
   ambiguous signal (multiple "orchid diary" matches in the editor) is
   the stacked-covers accessibility-tree effect, not duplication.
