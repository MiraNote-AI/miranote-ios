# A push draft's first Save makes it a star

Refs #257

## Goal

- A push draft opens unsaved (`isDraft == true`, `hasBeenSaved == false`):
  `TriggerDraftBuilderTests.testDraftIsUnsavedUntilSaveMakesItAStar`.
- Its first Save files it saved and Home plays the fold: same Kit test
  (`StarFold.arrival == .fold`) and the UI test
  `PhotoTriggerUITests.testCtaDraftsFirstSaveFoldsIntoTheJar`.
- An edited push draft left via Home is no star: same Kit test.
- Kit suite, MiraNoteTests and the affected UI classes (PhotoTriggerUITests,
  StarJarSaveUITests, DraftPagesUITests) pass; the touched files lint clean.

Stop conditions: run-loop defaults (cap 5, no-progress rule).

## Root cause

`TriggerDraftBuilder.draft` built its page as `Memory(title:memoryDate:items:)`.
`Memory.init` defaults `isDraft` to false and `hasBeenSaved` to `!isDraft`,
so the push draft arrived as a page already saved. Home's Save passed
`wasStar: memory.hasBeenSaved` (true), `StarFold.arrival` returned `.none`,
and no fold played. The same default made an edited push draft left via
Home a star without a Save. Fix: build it with `isDraft: true`, as Start
(`Memory(isDraft: true)`) and the Mira chat draft already do.

## Other entry points checked

- Start a memory / a journal's New memory: `Memory(isDraft: true)` -- fine.
- Home ask bar -> chat -> "open canvas": `.editor`, same as Start -- fine.
- Chat draft card: `Memory(..., isDraft: true)` -- fine.
- Deep links / URL schemes: none exist (no `onOpenURL`).
- Share extension: none exists (one application target).
- `HomeViewModel.startMemory()` builds `Memory(createdAt:)` (not a draft)
  but nothing in the app calls it -- noted, not changed.

## Decisions

- The push draft keeps the photos' shooting day as `memoryDate` (coordinator,
  2026-11-26). The jar files stars by `memoryDate`, so a push about last
  month folds into last month's jar, out of sight from this month's header
  jar. Whether it should show in the current jar goes to the team lead as a
  separate product question.

## Iterations

1. Kit test added -> fails on dev (4 assertions); `isDraft: true` added ->
   Kit suite 1209 tests, 0 failures (2 skipped). UI test with the fix
   reverted fails ("the star folds into the jar", 8 s timeout): mutation
   evidence.
2. Fresh-context review (criteria + diff only): VERDICT DONE; low notes --
   push drafts already autosaved by dev builds keep `hasBeenSaved == true`
   (no migration, noted in the PR); UI test parses the probe inline.
3. With the fix on iPhone 17 Pro: MiraNoteTests 213 (0 failures, 12
   skipped); PhotoTriggerUITests 38/38, StarJarSaveUITests 6/6,
   DraftPagesUITests 8/8. Touched files lint clean. SUCCESS.
