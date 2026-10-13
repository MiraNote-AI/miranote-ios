# Redesign phase D: the remaining handoff screens

Refs #93 (A: #81, B: #85, C: #89)

Jason, 2026-10-12: finish every handoff screen; decide as the expert.

## Goal (acceptance criteria)

D1 -- Home and onboarding (`feat/home-and-onboarding`)
1. Home (01): the large Start button leads, the retrieval pill follows;
   collection cards take the handoff shape with titles at >= 4.5:1.
2. Onboarding (03): the first blank page introduces the five tools once;
   Skip closes, "Choose your background" opens Background; never again.

D2 -- recording bar and drag-to-delete (`feat/recorder-and-drag-delete`)
3. Recording bar (08): ink capsule with discard, waveform, clock and stop;
   discard throws the take away.
4. Drag-to-delete (22): a dragged element shows the delete zone over the
   dock; released below the canvas it is deleted, one tap from undone.

D2b -- photo edit revert and compare (27-28)
5. The photo panel reverts this session's edits in one undo step, and a
   hold shows the photo as it was when the panel opened.

D3 -- Mira chat restyle (02, 06). D4 -- background font sets and one-tap
layout (05).

For every PR: kit `swift test`; Release build; full app suite; CJK check;
fresh-context review. HUMAN: visual match to the handoff screens.

Decisions: no bell or profile buttons on Home (handoff draws both; there
is no notification or account feature behind them). The pre-existing,
non-interactive person glyph on dev is left alone.

## Iterations

1. D1 written: Start button 226x92 above the pill, cards 188 pt with the
   cover block; card colors darkened along their hue (tan takes ink) for
   contrast. ToolsOnboarding overlay on the first blank page, gated by
   HintCenter; UI tests see it only with `-HINT editor-tools`. 4 UI tests
   green; screenshots match 01 and 03.
2. Fresh-context review: DONE with should-fix -- graduation untested (UI
   tests bypass it) -> HintCenterTests; tools behind the card still acted
   -> scrim, tap = Skip (+UI test); 11 pt count at 0.85 opacity fell to
   3.85:1 -> full opacity; absence asserted with waitForExistence -> a
   predicate wait. HintCenterTests 2/2, onboarding UI 5/5, Release OK ->
   PR #94.
3. D2 written: ink recording bar with discard; drag-to-delete derives the
   zone from the move's @GestureState (a cancelled drag clears it). Canvas
   UI tests 15/15 + 2 new green.
4. Review: NOT DONE -- armed zone red 3.4:1; discard/stop 34 pt wide; a
   stop finishing after discard revived the take; deleting at the exact
   canvas edge; zone smaller than the deleting area. Fixed: red #7F2E22
   (6.6 / 5.2:1), 44 x 44 targets, stop checks the same take is still
   recording, 24 pt margin, zone covers the dock. 4/4 green.
5. Re-review: 1-4 DONE; zone NOT DONE -- an overlay on the bare
   @ViewBuilder repeated per dock child. Wrapped the dock in one VStack.
   Canvas UI 17/17, Release OK.
6. D2b written: restoreImage (kit, 2 tests); panel remembers the photo on
   open, offers Hold to compare + Revert after a visible edit; the board
   draws the original with a Before tag; one session per photo. UI test
   green after a firstMatch fix (Label children inherit the id).
7. Review: NOT DONE -- a system-cancelled hold left the compare stuck
   (onEnded never ran); Revert erased a summary that landed mid-session.
   Fixed: @GestureState drives the compare; the summary follows the
   pixels (+test). VoiceOver toggles the compare. Not covered by tests:
   "Before" appearing mid-hold (XCUITest cannot observe during a press).
