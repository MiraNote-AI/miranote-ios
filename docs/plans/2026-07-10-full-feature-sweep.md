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

## Findings

| # | Area | Symptom | Evidence | Status |
|---|------|---------|----------|--------|

## Morning report

(written before 08:30)
