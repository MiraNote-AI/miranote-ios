# Demo readiness sweep -- plan & ledger

REQUIRED SUB-SKILL: run-loop
Refs MiraNote-AI/miranote-ios#34
Branch: `integration/demo-sweep` (worktree `miranote-ios-wt-demo`;
LOCAL ONLY -- an octopus merge of main + PR #29 + PR #31, never pushed
as its own PR). Fixes land on the PR branch they belong to, or as new
minimal branches off main.

## Goal

Every demo journey (issue #34 list) walked live on the integration
build; broken things fixed; a demo-day runbook written.

## Acceptance criteria

- [ ] Journeys 1-10 walked on the shadow simulator with all five
      backends live; film-strip evidence per journey; verdict each:
      OK / FIXED (with locking test) / FLAGGED (owner + why)
- [ ] Fixes ship on their proper branch with suites + lint green there
- [ ] Runbook committed: backend start order, keys location, simulator
      prep, reset-for-demo steps, known rough edges
- [ ] Fresh-context subagent review for any code fix
- [ ] HUMAN: PR reviews; final polish judgment

## Stop conditions

- Iteration cap: 5 per finding; no-progress rule after 2.
- Budget: this is demo week -- prefer FLAGGED over heroic fixes for
  anything bigger than a contained change. Backend changes only as
  minimal separate PRs on miranote-api.
- Escalation: protected paths; check weakening; design decisions
  (those go to #32 / Discord, not this loop).

## Environment

- Backends 8001/8002/8003/8004/8005 all healthy at loop start.
- Shadow simulator: iPhone 17 (0DB498B2); user simulator FB498BEA gets
  the final verified build only.
- Probes are throwaway, deleted before any commit.

## Iterations

1. Probe A (journeys 1-3), live: EN draft -> editor -> filed; CJK draft
   (pasteboard input) -> clean Chinese page; find -> open -> back keeps
   the conversation (PR #29 beat); expand shows the working bar and the
   result renders REAL BULLETS on canvas (film f092) with the 4-slot
   toolbar visible (PR #31). 4/4 probe tests passed. All OK.
2. Probe B (journeys 4-5), live :8002: generate (kite over lake,
   ~30s) -> placed; long-press Edit photo -> warm filter -> bookmark
   saves to library ("Saved to your library.") -> Ask AI watercolor
   lands -> Make sticker cutout replaces in place (film f090, clean
   white outline). Probe's two failures were probe bugs: the panel
   auto-closes after conversion (by design -- the photo became a
   sticker), and journey 6's tap hit the newest entry (the sticker),
   which correctly placed as a sticker (film f106). App all OK.
3. Probe B2: the saved PHOTO entry (kind image) places as an image
   element, no sticker. Passed. Journey 6 fully OK.
4. Probe C (journeys 7-10), live: sound record round trip + dictation
   against :8005 (honest no-words hint on a silent sim mic) passed;
   background ask -> two live candidates -> placed; title ask LANDED
   (film f135: serif title over the sunset backdrop) -- the probe
   asserted the wrong receipt copy ("Added a title." vs the real
   "Added a soft title."). Export stalled on the photos-add permission
   alert: environment, not app (the sweep had granted photos but not
   photos-add).
5. Probe C2 with corrected assertions + photos-add granted: caption
   ("Added a few words."), tidy ("Tidied the layout."), and export
   confirmation all passed.

## Verdict

10/10 journeys OK on the integration build (main + #29 + #31).
ZERO app defects found; every probe failure traced to probe
assumptions or simulator permission environment. Demo prep facts
captured in docs/demo-runbook.md (same PR as this plan).
