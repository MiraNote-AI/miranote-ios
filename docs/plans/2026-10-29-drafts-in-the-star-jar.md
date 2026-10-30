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
- [ ] Only Save starts a mood ask; drafts are never judged (2, 3)
- [ ] `hasBeenSaved`, the jar's stars, `savedAt` for drafts (4, 5, 6)
- [ ] zh-Hans strings (7)
- [ ] Jason's review nits; the Draft tag's theme (8, 9)
- [ ] verify-repo, the fresh-context check, the pre-merge review (10, 11)
- [ ] Push; PR body from the org template; answer Jason's review

## Iterations

1. Merged dev (7083a82). The four conflicts all kept both sides -- criteria 1/11; xcodegen, the Kit build and the app's build-for-testing exit 0.
