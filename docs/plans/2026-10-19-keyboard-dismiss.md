# Lower the keyboard without sending (Home ask bar, editor fields)

Refs #120

REQUIRED SUB-SKILL: run-loop (the owner is away for two hours and asked for
the fix to be done end to end; a PR is the end state, a human merges).

## Goal

From #120's acceptance criteria:

1. On Home, a tap outside the ask bar and a scroll of the page lower the
   keyboard; what was typed stays in the bar.
2. In the editor, the Mira question, "Apply to this page", the Sticker
   prompt, the photo AI prompt and the sticker edit instruction can lower the
   keyboard without sending and without closing their panel; the draft stays.
3. Writing on the page keeps Done, Cancel and the tap on the page.
4. UI tests for Home and at least one editor field: focus, tap outside, the
   keyboard is gone, the draft is kept.

Checked by: the new `KeyboardDismissUITests` (fail on dev 03dec34, pass
here); the existing text editor, sticker, photo, background and Mira chat UI
suites for criterion 3 and for no regressions; the verify-repo commands
(MiraNoteKit `swift test`, app unit and UI suites, swiftlint baseline, Release
build). After review, the keyboard tests and the suites of these screens also
run on iOS 17.5 and 18.6 simulators. HUMAN: whether the way the keyboard goes
down feels right on a phone.

## Approach

One rule for every one-line field: while it has the keyboard up, a tap
outside it that no button takes lowers the keyboard, and the words stay. On
Home a scroll lowers it too (`scrollDismissesKeyboard(.immediately)`). A tap
on the page never throws typed words away: where leaving drops them, the
first tap only lowers the keyboard.

| Place | Lowers the keyboard |
|---|---|
| Home ask bar | a tap on the page that is not a button; a scroll (a tap on the bar itself focuses the field) |
| Mira chat question | a tap on Mira's panel |
| Background "Apply to this page" | a tap on the Background sheet |
| Sticker prompt | a tap on the Sticker sheet; the first tap on the page while the prompt has words |
| Photo AI prompt | a tap on the photo (its sheet sits under the keyboard); the first tap on the page beside it while the prompt has words |
| Sticker edit instruction | a tap on the Edit sticker card (a tap on its capsule focuses the field) |

## Decisions taken without the owner (revisit when back)

| Topic | Decision | Why |
|---|---|---|
| A tap on the page while typing (Sticker panel, photo editor) | while the prompt has words, the first tap only lowers the keyboard; with nothing typed, or with the keyboard down, it goes back or closes as before (agreed in review, narrowed to a prompt with words) | leaving drops the typed words there: the Sticker panel's prompt, and an idle photo editor with its prompt |
| The dimmed page of the Mira chat | unchanged: it closes the chat at once | the draft stays in the composer, and Mira's panel lowers the keyboard |
| A tap on the field's own capsule (Home ask bar, sticker edit) | focuses the field | otherwise the new page and card taps would lower the keyboard from the bar's edge or star; it must not take the field's own taps (the caret), checked on iOS 17.5, 18.6 and 26.3 in iteration 4 |
| A Done button over the keyboard | not added | the handoff draws none, and the Mira keyboard already carries the dictation strip |
| HEX fields of the color sheets, the New collection alert | left as they are | not in #120's criteria (the alert is the system's) |

## Steps

- [x] 1. `KeyboardDismissUITests`: one test per row above; run on dev, all fail.
- [x] 2. Home: a focus state for the ask bar, a tap on the page, scroll dismissal.
- [x] 3. Mira chat: panel tap; the dimmed page still closes the chat at once
  (iteration 3).
- [x] 4. Background: a tap on the sheet lowers the Apply field.
- [x] 5. Sticker panel: sheet tap; the page tap lowers the keyboard first while
  the prompt has words (review).
- [x] 6. Photo editor: a focus state for its prompt; a tap on the photo.
- [x] 7. Sticker edit panel: a focus state for the instruction; card tap.
- [x] 8. Verify: new tests pass; full verify-repo run; swiftlint not above dev.
- [x] 9. Fresh-context review of the diff against the criteria.
- [x] 10. PR to dev with `Closes #120`.
- [x] 11. Review: the first-tap rule only while the field has words; while a
  made sticker waits, a tap on the page (which cannot leave) still lowers the
  keyboard. Tests for an empty Sticker and photo prompt, a waiting sticker, and
  the caret in the Home bar and the sticker edit field.
- [x] 12. Review: the keyboard tests and the Home, Background, Sticker, sticker
  edit, photo editor and Mira chat suites on iOS 17.5 and 18.6 simulators.

## Stop conditions

- Success: criteria 1-4 pass and the fresh-context review agrees.
- Iteration cap: 5. No progress in 2 iterations in a row: stop, write the
  handoff.
- Escalate: a protected path, a test that would need weakening, or work
  beyond #120.
- Budget: wall clock 12:36-14:30 CDT on 2026-10-19 (the owner's two hours).

## Iterations

1. `KeyboardDismissUITests` (7 tests) written and run on dev 03dec34: 7/7 fail
   at the keyboard check, every setup step passing -- criteria 0/4.
2. Fix in six files: 6/7 pass. The photo test tapped the Photo Editing title,
   which a probe screenshot showed under the keyboard; the photo is what shows,
   so the test taps it and the page beside it is left as it was -- 7/7 pass.
   The final file on dev: 7/7 fail. With the two dimmed-page changes undone,
   their tests fail ("the chat stays open", "the panel stays open") --
   criteria 1, 2 and 4 passing; 3 waits for the full UI suite.
3. Full verify of iteration 2: MiraNoteKit 533/0, app unit 72/0, UI 179 run
   (4 skipped, 0 failures), Release device build 0 warnings, swiftlint 128
   (dev 128), governance checks pass. Fresh-context review: DONE, nothing
   blocking; four notes acted on. (a) Closing the photo editor lets an idle
   editor go with its typed prompt, and a tall photo leaves about 90 pt of
   page beside it: the first tap there now only lowers the keyboard. (b) The
   new page and card taps lowered the keyboard from the ask bar's star and
   edges and from the sticker capsule's margins: those capsules now focus
   their field, meant also to keep the field's own taps safe on iOS 17-18 (only
   the iOS 26.3 simulator was installed; checked in iteration 4). (c) In the Mira chat the first-tap
   rule cost a second tap to close and saved nothing (the draft is kept):
   reverted. Tests updated; on the code before these changes four checks fail
   where expected (bar star, dimmed page closes the chat, editor stays open
   beside the photo, sticker capsule). With the changes: the new tests and the
   ten suites that use these fields, 89 tests, 88 passed; the sticker capsule
   check tapped the gap past the capsule (it now measures from Go, and fails
   with the capsule's tap removed). Final code: the new tests, StickerEdit,
   ToolScope and PhotoRevert, 20/20; Release 0 warnings; swiftlint 128 -- criteria
   4/4 passing.
4. Review follow-up (Jason's review of e175ae3; the owner is back, so no
   wall-clock budget). The first-tap rule holds only while the prompt has
   words; while a made sticker waits, the page tap (which cannot leave) now
   lowers the keyboard. `KeyboardDismissUITests`: 11 tests (four new, the
   sticker edit one also checks the caret). Undone one at a time, each piece
   fails its check: the words check (both empty-prompt tests stay open), the
   waiting-sticker keyboard (it stays up), and an overlay taking the bar's or
   the capsule's taps (the caret stays at the end). The caret check first
   typed one word: a tap on the word the caret is in makes iOS show its edit
   menu instead of moving the caret (seen in the screen recording), and that
   version failed 2-3 times in 20 on dev itself; with two words and the tap
   on the first, 20/20 on dev and 20/20 here. A tap 2 pt into the sticker
   edit field landed in the capsule's padding (the field's frame takes it
   in); the check taps 14 pt in. Fresh-context review: DONE, nothing
   blocking; its notes acted on (the waiting sticker, this plan's wording,
   the sticker edit caret, end-state checks, wider suites). All runs on this
   branch merged with dev b310b64 (#118 in). iOS 18.6 (iPhone 16 Pro): the
   keyboard tests and the Sticker, sticker edit, photo, Mira chat, dictation,
   canvas editor, page tap, tour and text push suites 106/106; Background
   (the hex field) and Home 16/16. iOS 17.5 (iPhone 15 Pro): the same 106
   tests 104 passed, Background and Home 16/16; the two failures (canvas
   drag `testDragMovesUnselectedElementDirectly`, dictation
   `testADragWhileTheKeyboardIsUpNeverDeletes`) fail 3/3 on dev b310b64 on
   the same simulator, so they come with iOS 17, not this branch. iOS 26.3:
   MiraNoteKit 537/0, app unit 72/0, UI 187 run (4 skipped: live backend,
   demo, monkey) 0 failures, Release device build 0 warnings; swiftlint 128
   (dev 128); governance checks from .github main c72b9f0 pass -- criteria
   4/4 passing.
