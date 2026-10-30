# Drafts meet the star jar (update of PR #138)

Refs #137 (draft and saved pages) and PR #138 (this branch). The star jar
rules are Jason's product decision of 2026-10-28 in #general. The repo
owner approved the `hasBeenSaved` field on 2026-10-29.

REQUIRED SUB-SKILL: superpowers:test-driven-development

## Context

PR #138 was approved on 2026-10-26. It predates three changes on dev:

- the star jar (#142);
- the Simplified Chinese catalog (#145);
- text size (#149).

Merged as they stand, the jar would ask a draft's mood when Home leaves
it, and every draft would be a star.

## Goal (acceptance criteria)

1. **Merge.** dev is merged and every conflict keeps both sides. The
   branch differs from dev only in the draft-pages work.
   Check: `git diff --stat origin/dev HEAD`, then build-for-testing.
2. **Only Save starts a mood ask.** `HomeFlow` judges after Save, never
   after Home or the background autosave.
   HUMAN: `EditorFlowView.swift`, where `onComplete` carries whether Save
   filed the page.
3. **A draft's words are never judged.** `MoodJudge` skips a page that is
   a draft when its turn comes. Check: `MoodJudgeTests`.
4. **`Memory.hasBeenSaved`.** Save sets it and nothing clears it. A file
   written before the field reads as saved unless it is a draft.
   Check: `DraftPageTests`.
5. **The jar holds every page saved at least once.**
   - A never-saved draft is no star.
   - A saved page that becomes a draft keeps its star, with the mood its
     last Save got.
   - The next Save asks again.
   Check: `StarJarTests`, `DraftPagesUITests`.
6. **A draft keeps its last Save's time.** Filing a draft keeps `savedAt`
   from the last Save, so the jar does not drop a draft in as newly
   saved. Check: `DraftPageTests`.
7. **zh-Hans strings.** "Kept as draft" and "Draft" (the tag and its
   VoiceOver value) have zh-Hans translations.
   Check: `LocalizationCatalogTests`.
8. **Jason's review of #138.**
   - a. `testTheOpeningRemeasureIsNoEdit` fails when the baseline is
     taken before the opening remeasure (mutation evidence in the
     ledger), and `CanvasScene` says why the order matters.
   - b. The explicit Save signal is criteria 2 and 4.
   - c. `testSaveTurnsADraftIntoASavedPage` waits for the toast to appear
     before it waits for the toast to go.
9. **Draft tag theme.** The Draft tag follows the theme the way
   `SoftPill` does (Forest). HUMAN: screenshot.
10. **verify-repo.**
    - Kit `swift test` and the app's unit tests pass.
    - The full UI suite has no failure that dev does not have.
    - Release builds.
    - swiftlint finds no more violations than dev (136).
    - The governance checks pass.
11. **Review.** The fresh-context check says done. The pre-merge review
    has every finding fixed or answered: `/code-review high`, then
    `/security-review`, because `Models.swift` is a sensitive path.

## Stop conditions

- **Success:** criteria 1-11 pass.
- **Iteration cap:** 5.
- **No progress:** 2 iterations in a row without progress -> stop and
  write the handoff.
- **Escalate:** a protected path, a check that would need weakening, a
  second data-structure change, or work beyond #137 and the jar rules.

## Steps

- [x] Merge dev (1)
- [x] Only Save starts a mood ask; drafts are never judged (2, 3)
- [x] `hasBeenSaved`, the jar's stars, `savedAt` for drafts (4, 5, 6)
- [x] zh-Hans strings (7)
- [x] Jason's review nits; the Draft tag's theme (8, 9)
- [ ] verify-repo, the fresh-context check, the pre-merge review (10, 11)
- [ ] Push; PR body from the org template; answer Jason's review

## Iterations

1. Merged dev (7083a82). The four conflicts all kept both sides -- criteria 1/11; xcodegen, the Kit build and the app's build-for-testing exit 0.
2. Drafts in the jar (9f33471) and their zh-Hans strings (f073e1c) -- criteria 1-7/11 (2 is HUMAN); Kit 602/0, app unit 108/0, DraftPagesUITests 7/7, StarJarUITests 2/2. On 7083a82 the two new UI tests fail ("a draft never saved is no star"; "label became A sad walk, Joyful"), and LocalizationCatalogTests failed until the catalog had both entries.
3. Jason's three review points (the commit that adds this line) -- criteria 1-9/11. Mutation evidence: with the baseline taken at open, `testTheOpeningRemeasureIsNoEdit` fails; with the draft toast switched off, `testSaveTurnsADraftIntoASavedPage` fails at its new wait. Draft tag and toast screenshotted in System, Forest and Sunlit Pop, in English and Chinese.
   Ruling: the Draft tag keeps its paper capsule. The journal's own Home pill is the same unthemed `SoftPill` in every theme, Forest included, so the tag already matches it. No code change.
4. Verification, and fixes from it (f9dc2bd, ebd2ed3, the commit that adds this line) -- criteria 1-10/11.
   - Full run at 87eaacc: Kit 602/0; app unit 108/0; UI 233 (229 passed, 4 skipped, 0 failed); Release builds.
   - swiftlint found 137 violations, one more than dev: HomeFlow's body reached 266 lines, over the 250-line `type_body_length` limit, once dev's additions met the toast code. The toast moved to an extension (ebd2ed3) and the count is back to 136, as on dev.
   - After the later commits: Kit 604/0; DraftPagesUITests 7/7; StarJarUITests 2/2. Those commits only add tests and move the toast.
   - Governance checks from `.github` main (f732992): all four pass.
   - Fresh-context check: VERDICT DONE, with 0 IMPORTANT and 3 NIT findings.
     - NIT 1 FIXED f9dc2bd. The new test fails if drafts are dropped only when queued.
     - NIT 3 FIXED f9dc2bd. The new test fails if a missing `hasBeenSaved` reads as saved.
     - NIT 2 ANSWERED. With the baseline taken at open, `testLookingAtASavedPageKeepsItSaved` still passes, because the seeded page's heights already fit. Its comment now names the Kit test that guards the re-measure.
5. Pre-merge review, round 1: `/code-review high` on a35b849 returned 10 findings -- 2 fixed, 7 answered, 1 pre-existing.
   - **`MoodJudge.swift:79`**: a draft whose Save never got a mood stays unjudged. ANSWERED: the draft overwrites the saved words in place, so judging them would mean storing them -- a second data-structure change, which is an escalation trigger. The star reads "mood not read yet" until the next Save, as after any failed ask; no words are lost.
   - **`EditorFlowView.swift:80`**: emptying an existing page and leaving files nothing. PRE-EXISTING: dev's `finish()` has the same blank-page rule. It is listed in the PR as a follow-up.
   - **`CanvasViewModel.swift:638`**: `hasEdits` relies on the scene re-measuring before the first recorded change. ANSWERED: this is the design Jason reviewed. The order is documented at `CanvasScene.swift:177-181` and pinned by `testTheOpeningRemeasureIsNoEdit` (mutation-checked); an explicit "opened" hook would be a refactor beyond this PR.
   - **`CanvasViewModel.swift:59`**: `isClosing` is never cleared. ANSWERED: each editor presentation makes its own `CanvasViewModel` (`EditorFlowView.init`), and nothing uses one after `leave()`. Jason reviewed this placement.
   - **`EditorFlowView.swift:474`**: a third copy of the toast's show-and-hide timing. ANSWERED: "pending" waits for the cover to go, while "shown" drives the overlay -- two different moments. A shared toast helper would change `ReadingView` and `CanvasBoardView`, outside this PR; it is listed as a follow-up.
   - **`SaveToast.swift:50`**: the identifier is picked by message. ANSWERED: with two uses, moving the choice into `Message` or the caller moves the same switch without removing it. Revisit when a third caller comes.
   - **`StarJarView.swift:40`**: a copy of the star rule. FIXED 3fc2212: the forward step asks `StarJar.stars`.
   - **`CanvasViewModel.swift:647`**: the page is composed twice when filed. ANSWERED: that is one page, once per leave or autosave; the saving does not justify a second code path.
   - **`CollectionDetailView.swift:167`**: the Draft tag truncates a long date at large text sizes. FIXED eda0904.
     - Reproduced on an iPhone SE at 125%: "September... Draft".
     - After the fix, the date stays whole with the tag below it, and at 100% the two still share the line (screenshots).
   - **`Models.swift:73`**: `hasBeenSaved` is an optional init argument. ANSWERED: nothing rebuilds a page through init (copies use `var`). The nil default keeps a new draft out of the jar without every call site saying so, and the decoder shares it; a plain default would set the opposite trap for `Memory(isDraft: true)`.
   - Verify after the fixes: swiftlint 136; app unit 108/0; DraftPagesUITests 7/7; StarJarUITests 2/2.
   - `/security-review` could not run: this session's working directory is not a git repository. The owner decides how to run it.
