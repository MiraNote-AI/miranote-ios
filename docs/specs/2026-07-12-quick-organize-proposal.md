# Quick organize -- proposal (decision needed)

Refs MiraNote-AI/miranote-ios#32
Status: PROPOSAL. Nothing here is built; the team picks a direction
first (Gloria: layout aesthetics; Meng: scope for the demo).
Source ask: 2026-07-11 meeting, "quick organize canvas page".

## What already exists (survey, 2026-07-12)

`CanvasViewModel.quickOrganize(canvasWidth:spacing:)` -- deterministic
one-column tidy:

- Sort: title blocks (pointSize >= 24) first, then everything else
  top-to-bottom by current position.
- Place: centered column, gaps from REAL element heights (24pt), no
  overlap possible, rotation reset to 0.
- One undo step (beginChange snapshot), instant and local.

Two entry points already reach it:

1. The "Tidy the layout" suggestion chip over the prompt bar (appears
   whenever the page has 2+ elements).
2. Any Mira ask containing tidy / layout / organize / arrange.

So "a quick organize button" exists in spirit. The open question is
whether the meeting wanted MORE than a single centered column.

## Three directions

### A. Polish the existing tidy (smallest)

Keep one column; fix its rough edges: left-align body text blocks
instead of centering everything, keep photo sway (the -28/0/+28
stagger used at import) instead of a dead-straight line, and preserve
stickers' rotation (a scrapbook where every sticker sits at 0 degrees
reads as ironed flat).

- Cost: ~1 short loop. No new UI.
- Risk: may still read as "it just stacked my stuff".

### B. Local layout presets (recommended for the demo)

Quick organize becomes a small set of deterministic arrangements, and
repeated taps cycle through them:

1. **Column** -- today's behavior, polished per A.
2. **Collage** -- two-lane masonry: photos/stickers alternate lanes
   with slight sway and +/-3 degree tilt; text spans both lanes.
3. **Hero** -- biggest photo goes large at top, title overlaps its
   bottom edge, everything else tucks below in a tight grid.

Workflow example:

1. User has a messy page: title, 3 photos, 2 stickers, a paragraph.
2. Taps "Tidy the layout" chip -> Column. Receipt: "Tidied into a
   column. Tap again for a collage."
3. Taps again -> Collage. Again -> Hero. Again -> back to Column.
4. Undo restores the exact pre-tap layout at any point (existing
   snapshot machinery; each tap is one undo step).

- All local, instant, deterministic -- demo-safe and testable
  (same reasons the film-strip loop can lock it).
- Mira asks route to the same presets: "make it a collage" -> Collage.
- Cost: ~1-2 loops (layout math + receipt copy + tests).
- Decision needed from Gloria: the three arrangements above are an
  engineering sketch; she may want to redlines the collage/hero specs.

### C. AI layout (post-demo)

Send element inventory (sizes, kinds, text lengths) to the chatbot
backend; the LLM returns positions/scales. Most "AI-native", but slow
(seconds), non-deterministic (hard to test, hard to demo twice), and
needs a new endpoint + schema on miranote-api during demo week.

Recommendation: park until after July 12; if the demo narrative needs
an "AI organized my page" beat, B with the receipt worded as Mira
("I tidied it into a collage") reads the same on stage.

## Recommendation

B, scoped to the demo: Column (polished) + Collage first, Hero if time
allows. A is folded into B's first preset. C parked.

## Open questions for the team

1. Gloria: do Collage/Hero match her scrapbook direction, or does she
   want to spec the arrangements herself in Figma first?
2. Meng: is cycle-on-repeat-tap acceptable, or should the receipt offer
   named chips ("Column / Collage / Hero")?
3. Is quick organize worth a spot on the bottom toolbar, or does the
   suggestion chip + Mira ask suffice? (The bar just gained Library as
   its fourth slot in #31 -- a fifth gets crowded.)
