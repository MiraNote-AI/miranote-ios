# XCUITest UI test target and v1 regression tests

Refs #5
Branch: `feat/xcuitest-ui-tests` (worktree `../miranote-ios-wt-xcuitest`)
Base: `origin/docs/ios-v1-spec` -- the content of approved PR #4; the stacked
merge stranded the scaffold off `main`, PR #6 lands it there. The loop PR
targets `main` after #6 merges.

## Goal (acceptance criteria)

- [ ] AC1: `MiraNoteUITests` target exists (project.yml, XcodeGen) and runs
      via `xcodebuild test` on the iPhone 17 simulator alongside
      `MiraNoteTests`.
- [ ] AC2: `testSaveKeepsCanvasAndFilesCollection` -- start a memory, add
      text, Save: the text stays on the canvas (v1 bug wiped it); back on
      Home the "My memories" card with "1 memories" is shown and the
      empty-state hint is gone.
- [ ] AC3: `testLongPressMenuAppearsAtTouchPoint` -- press-and-hold on the
      empty canvas: the insert menu's center lands within 40pt of the press
      point (v1 bug offset it by ~100pt).
- [ ] AC4: `testEmptyStateHintShownOnFirstLaunch` -- D3 hint visible on a
      fresh launch.
- [ ] AC5: Mutation evidence -- AC2's test FAILS when the v1 inline-view-model
      bug is deliberately reintroduced (and AC3's against a `.local`
      coordinate-space mutation, if cheap). Outputs recorded in the ledger;
      mutations reverted.
- [ ] AC6: Full verifier green (see Verifier).
- [ ] AC7: App-target diff limited to accessibility/testability hooks; no
      behavior change.

HUMAN: none -- every criterion is machine-checkable.

## Stop conditions

- Success: AC1-AC7 pass AND the fresh-context reviewer passes.
- Iteration cap: 5.
- No progress for 2 consecutive iterations -> handoff.
- Escalation: a protected path would need editing; a check would need
  weakening; scope grows beyond issue #5.

## Verifier (per verify-repo and the v1 loop precedent)

From the worktree root:

1. `(cd MiraNoteKit && swift test)` -- expect 19/19 (Kit untouched here).
2. `swiftlint --strict` -- expect 0 violations.
3. `xcodegen generate && xcodebuild -project MiraNote.xcodeproj -scheme
   MiraNote -destination 'platform=iOS Simulator,name=iPhone 17' build test`
   -- expect BUILD + TEST SUCCEEDED with both test targets.
4. Governance: temp worktree of `MiraNote-AI/.github` at `origin/main`,
   4 target checks (contributing_format, no_cjk_or_emoji, claude_md_size,
   skills_registry).

## Iterations

## Deviations and decisions

- Issue AC2 was revised BEFORE iteration 1 (criteria freeze point): v1 has
  no reopen-a-memory UI, so the round-trip asserts in-place survival plus
  the filed card instead of "reopen the memory". Recorded in issue #5.
- Loop based on `origin/docs/ios-v1-spec` instead of `main` (see Base
  above); discovered while setting up: PRs #3/#4 were merged 11s apart so
  GitHub never retargeted the stacked #4.
