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
8. D3 written: chat Home pill, M-mark warm-white bubbles, ink user
   bubbles, Send pill; canvas Mira card lifted warm-white with the same
   mark. The handoff's "Quick starts" card is omitted: chat always opens
   seeded with the user's question, so it would never show. D4 written:
   applyFontSet (kit, 3 tests) + four sets from TextFace's faces; one-tap
   layout = the existing "Tidy the layout" turn (now one named constant).
   Targeted UI 22/22 after rerunning two load flakes in reading/bin tests.
9. Review: D3 DONE (chat field unlabeled for VoiceOver -> labeled); D4
   DONE with medium: two sets could read as worn at once, default titles
   read as Editorial -> one worn set, only once a set face is on the
   page; disabled tiles dim. One-tap layout while Mira works cannot occur
   (the panel cannot open mid-turn; the Mira bar is hidden under it).
10. Pre-approval pass (Jason: "make sure teammates can approve as is").
   Whole-phase review: NOT YET -- Soft lit Classic (shared Optima body);
   a VoiceOver compare outlived its row; VoiceOver reached tools behind
   the onboarding card; dropping over the keyboard deleted unsigned; a
   24 pt literal in two more places. Fixed each in its own PR: unique
   faces per role (+UI test), compare handlers on the panel and any
   visible change ends it, card modal (alert role, asserted), no
   drag-delete while editing text, one displayPointSize. Not taken:
   "Add a note" assertion is the marker pill, not the review field.
   Simulator probe (external screenshots mid-gesture): zone resting and
   armed render over the whole dock; fixed ghosting (zone opaque), the
   clipped dragged element (armed zone now says "Release to delete"),
   the photo panel overflowing the screen (tabs and filters scroll), and
   the Modern ring invisible on its dark tile (ring outside the tile).
   Device sweep: D3 alone on iPhone 17 Pro Max failed 3 image-ask UI
   tests. Bisected: green on dev, red at the phase C tip -- the
   redesigned dock sits where the helper's "120 pt below the lower photo"
   deselect tap used to be paper, so it opened the Text tool. Helper now
   taps beside the photo (Pro and Pro Max 5/5). The fix sits at the
   bottom of the stack (#82) so every redesign PR is green on its own.
11. Re-review of the fixes: APPROVABLE except the drag-while-editing
   guard, which never held (moving an element selects it and ends text
   editing). Probe: dragging another block while typing lowers the
   keyboard and the signed dock returns -- no unsigned keyboard area
   exists, so the dead guard was removed.
12. Zhaoyan's #78 / #80 merged to dev; the whole stack rebased onto it.
   Conflicts at #84 (#80's page tap moved from the removed Saved panel
   into StickerPanelScene, with the Image panel's guard so unpicked
   stickers survive (+UI test); #80's tests moved to mode.voice /
   mode.sticker), #95 and #96 (both sides' CanvasBoardView parameters
   kept; #78's reveal-on-close kept beside the compare binding). #78's
   auto-close after an AI edit means the compare row covers filters and
   frames; top-bar Undo covers AI edits.
