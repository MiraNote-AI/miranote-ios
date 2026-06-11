# XCUITest UI test target and v1 regression tests

Refs #5
Branch: `feat/xcuitest-ui-tests` (worktree `../miranote-ios-wt-xcuitest`)
Base: `origin/docs/ios-v1-spec` -- the content of approved PR #4; the stacked
merge stranded the scaffold off `main`, PR #6 lands it there. The loop PR
targets `main` after #6 merges.

## Goal (acceptance criteria)

- [x] AC1: `MiraNoteUITests` target exists (project.yml, XcodeGen) and runs
      via `xcodebuild test` on the iPhone 17 simulator alongside
      `MiraNoteTests`.
- [x] AC2: `testSaveKeepsCanvasAndFilesCollection` -- start a memory, add
      text, Save: the text stays on the canvas (v1 bug wiped it); back on
      Home the "My memories" card with "1 memories" is shown and the
      empty-state hint is gone.
- [x] AC3: `testLongPressMenuAppearsAtTouchPoint` -- press-and-hold on the
      empty canvas: the insert menu's center lands within 40pt of the press
      point (claimed v1 bug: ~100pt offset; see Deviations).
- [x] AC4: `testEmptyStateHintShownOnFirstLaunch` -- D3 hint visible on a
      fresh launch.
- [x] AC5: Mutation evidence -- AC2's test FAILS when the v1 inline-view-model
      bug is deliberately reintroduced (and AC3's against a `.local`
      coordinate-space mutation, if cheap). Outputs recorded in the ledger;
      mutations reverted.
- [x] AC6: Full verifier green (see Verifier).
- [x] AC7: App-target diff limited to accessibility/testability hooks; no
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

1. Added MiraNoteUITests target (project.yml + scheme), insert-menu
   accessibility hook in CanvasView, and 3 UI tests -- criteria 5/7
   (AC1-AC4, AC7); xcodebuild BUILD + TEST SUCCEEDED (1 unit + 3 UI:
   hint 3.3s, long-press 7.7s, save round-trip 14.8s), Kit 19/19,
   swiftlint --strict 0, governance 4/4.
2. Mutation evidence -- (a) inline-view-model mutation (exact pre-fix
   code from 036e528^): testSaveKeepsCanvasAndFilesCollection FAILED at
   "canvas content must survive Save", TEST FAILED -- AC5 core proven.
   (b) historical `.local` coordinate mutation: test PASSED, then PASSED
   again with tolerance tightened to 5pt -- the claimed ~100pt offset
   does not reproduce (see Deviations). Mutations reverted by targeted
   edits; final full suite re-run green. Criteria 7/7.
3. Maker-checker (fresh-context): DONE -- reviewer independently re-ran
   the full verifier (Kit 19/19, swiftlint 0, simulator suite 4/4,
   governance 4/4). 1 WARN: AC3's test has never been observed red
   (consequence of the mutation-2 finding; accepted consciously --
   detection rests on the 40pt arithmetic). 3 NITs: index-based back
   navigation, typeText hardware-keyboard hazard, AC3 parenthetical
   reworded post-freeze (testable threshold unchanged). Criteria 7/7;
   proceeding to terminal state.

## Deviations and decisions

- Issue AC2 was revised BEFORE iteration 1 (criteria freeze point): v1 has
  no reopen-a-memory UI, so the round-trip asserts in-place survival plus
  the filed card instead of "reopen the memory". Recorded in issue #5.
- Loop based on `origin/docs/ios-v1-spec` instead of `main` (see Base
  above); discovered while setting up: PRs #3/#4 were merged 11s apart so
  GitHub never retargeted the stacked #4.
- FINDING (mutation 2): the v1 review's coordinate-space bug claim
  ("menu lands ~100pt below the touch with `.local`") does NOT reproduce
  on the iPhone 17 / iOS 26 simulator -- the exact pre-fix gesture code
  places the menu within 5pt of the press point. SwiftUI keeps a view's
  local coordinate origin at its layout frame even when ignoresSafeArea
  expands its drawing, so background-local equals the ZStack space here.
  The 036e528 named-coordinate-space change was defensive, not
  corrective, and its commit message asserts a runtime fact that was
  never reproduced. The named space is kept (more robust to future view
  re-parenting); the lesson -- review findings about runtime behavior
  need a runtime repro before being recorded as fact -- goes to the org
  loop-engineering notes.
- Ops slip during mutation testing: reverting mutation 1 via
  `git checkout <file>` also wiped the uncommitted accessibility hook;
  re-applied. Revert mutations with targeted edits, not file checkout.
