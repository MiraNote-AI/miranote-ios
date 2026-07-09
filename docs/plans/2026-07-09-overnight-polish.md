# Overnight polish loop -- self-driven UX review against UI Flow v2.1

Refs: design decisions v2.1 --
https://claude.ai/code/artifact/6d534efe-835b-4760-85a7-d3bd9216a750
(no GitHub issue: `gh` external writes are denied in this environment;
recorded as a deviation, reference is the design doc above.)

Meng's brief (2026-07-08, before sleep): use the app yourself via
screenshots/recordings, find experience problems and design-plan
mismatches, fix them carefully step by step. Results reviewed 09:00.

## Goal (acceptance criteria)

1. Every main v2.1 flow self-driven with a film-strip probe and the
   frames actually reviewed: home, search, collection detail, reading,
   export, trash, chat (ask/find/draft), canvas text, sound, image
   panel + photo edit, Mira turn (working/receipt/revert/failure),
   drag/resize/long-press.
2. Each defect fixed carries a test lock (Kit or UITest).
3. After every iteration: swiftlint 0, Kit suite green, full UITest
   suite green on the shadow simulator, fresh build installed to the
   main simulator.
4. Design-plan mismatches either fixed (when the plan is unambiguous)
   or written up as proposals for Meng (when fixing would mean deciding
   something new). Settled decisions are never reversed overnight.
5. HUMAN: visual taste judgments (spacing, warmth, wording) -- flagged,
   my picks explained, Meng reviews at 09:00.

## Stop conditions

- Success: criteria 1-4 met and a fresh-context subagent review of the
  accumulated diff returns DONE.
- Iteration cap: 12 (an iteration = one probe-or-fix cycle ending in a
  recorded verify result).
- No-progress rule: 2 consecutive iterations without a new finding
  fixed or verified -> stop, write handoff.
- Budget: wall clock 08:30 -- stop, wrap up, write the morning report
  regardless of remaining findings.
- Escalation: anything requiring a push, a PR, a protected path, or a
  reversal of a settled design decision -> proposal list, not code.

## Constraints

- Local commits only (feat/ios-flow-v2 in miranote-ios;
  feat/chat-journal-mode in miranote-api). No pushes, no PRs.
- Probes are throwaway UITests + host-side `xcrun simctl io screenshot`
  loops on the shadow simulator (35B7DA99); they are deleted before any
  commit. Main simulator (6E165F5B) only receives verified installs.
- Rule 3: committed text ASCII-only (this plan file is docs/plans,
  exempt, kept English anyway).

## Iterations

(appended as they complete)

1. Tour A (reading flows) filmed: 82 frames over home, collection,
   reading, export, chat find/draft, editor-from-draft. Findings:
   - F1 collection grid: the card label under each cover repeats the
     title already drawn inside the cover. Label should carry metadata
     (the page date) instead. Also: the starter draft page says
     "June 21" in its caption but its memoryDate is the July seed time,
     so it groups under JULY 2026 -- align the seed date with the
     content.
   - F2 an ImageRef with no real file renders as a bare tan rectangle
     (reading + canvas). Needs an intentional placeholder (faint photo
     glyph) so demo pages do not read as broken.
   - F3 chat hits row: caption under each cover repeats the truncated
     title (same duplication family as F1) -- switch to the page date.
   - F4 search treats app-meta words as content: "draft me a PAGE"
     matched the welcome page through the word "page". Extend stopwords
     with note/page/memory/draft/create/... meta words (plurals too).
   - F5 a chat-drafted page materializes with a huge title-to-body gap
     and static body height; body should sit right under the title and
     all text blocks should re-measure when the editor opens (also
     heals legacy pages with stale heights).
   Export sheet, home, draft card, chat header: no defects found.
   criteria progress: probe coverage partial (reading flows done).

2. Fixes F1-F5 landed and verified frame-by-frame on a re-filmed tour:
   - F1/F3: cover captions now say WHEN (CaptionDate "June 21"), covers
     alone say the title; starter seed memoryDate aligned to its June 21
     caption (groups under JUNE 2026). Verified in film.
   - F2: GradientPlaceholder carries a quiet, size-scaled photo glyph;
     visible even in small covers. Verified in film.
   - F4: app-meta stopwords (note/page/draft/...) -- "draft me a page"
     no longer summons unrelated covers. Kit-tested.
   - F5: took two passes. Pass 1 (nudge constants + remeasure on open)
     barely moved pixels -- caught by re-filming, not by tests. Pass 2:
     materializedForEditing now CHAINS blocks from estimated line
     heights (UIKit-free estimate, editor re-measures on open, tops
     preserved), gap locked at 12pt by Kit test; long-title overlap
     test added. Film shows one composition.
   Lint 0 (one type_body_length fixed by moving tests to
   ChatNoteTests). Kit 108. Full suite on shadow sim: 22 tests, 0
   failures, TEST SUCCEEDED (slow run, 32 min: network outage stalled
   system services; results unaffected -- Meng confirmed the outage and
   said to continue). Installed to the main simulator. Probe deleted
   before commit.
