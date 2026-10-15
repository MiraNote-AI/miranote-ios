# Design fidelity pass -- rebuild every screen to the 2026-10-07 handoff

Refs: owner feedback 2026-10-15 (`mira-dev-feedbacks/oct 15`), design handoff
`resources/design-2026-10-07/` (38 screens, `layout-reference.tsx` per screen).

## Goal

Every screen in the handoff is matched in the app: positions, sizes, type,
color, glass, blur and the drawn interactions. Each PR shows simulator
screenshots side by side with the design screen it implements. Where the
design does not draw something the product obviously needs (Mira chat voice
and photos, error states), it is added in the same visual language.

Acceptance (per stream):
- Side-by-side screenshot for every design screen in the stream (HUMAN: owner
  judges fidelity; engineer self-checks frame values against the tsx).
- `xcodebuild test` app unit + UI suites green; `swift test` for MiraNoteKit.
- Release build compiles; no CJK/emoji in committed text.

## Owner feedback (2026-10-15) -- must all land

1. Mira chat: voice-to-text is missing; photos cannot be sent. WeChat-style
   composer in the app's art style: voice toggle far left, field, "+" for
   photos; no emoji button.
2. Background tool: rebuild per screen 05.
3. Text editing UI from screen 04.3 on: typing-time blur scrim, the 3-layer
   accessory (secondary row / toolbar / dictation strip), sizes and layout;
   custom text color sheet per screen 14.
4. Drag-to-delete: behavior kept, UI per screen 22 (the composer becomes the
   red drop zone).
5. Everything else: go through all 38 screens.

## Decisions taken without the owner (he asked not to be blocked; revisit Saturday)

| Topic | Decision | Why |
|---|---|---|
| Layout insets | 16 for chrome (nav, composer, sheets), 20 canvas, 19 tool bar | design system is 16-based |
| Type floor | design sizes, but never below 10 pt (9/8 pt labels become 10) | design fidelity vs legibility |
| Text editing default tool | Aa (font row) active when editing starts | screen 11 is the first editing state |
| Font size S/M/L | kept, as trailing chips in the font row | not drawn; removing a feature silently is worse |
| Cancel while editing text | reverts the editing session | implied by the header |
| New text default | Josefin Medium 21, ink #293322 | every text screen draws it |
| Text background "none" | first chip, outlined | design ambiguous |
| AI rewrite | in place: Original / Clean up / Expand, keyboard stays | screen 15 |
| Background controls | apply live, each an undo step; the bottom bar "Apply to this page" asks Mira for a generated background (replaces the mood chips) | screen 05 |
| Curated sets | apply display font + body font + text color + page backdrop together | screen 05 cards pair two fonts with a color band |
| Custom color + eyedropper | one shared `CustomColorSheet` (text color, text background, page color) | screens 14, 20, 05 |
| Mira result | glass sheet with Revert / Keep, no auto-keep timer | screen 07 |
| Header trailing label | "Save" on the canvas (still files the page); export stays reachable from Reading | design label; export-from-canvas is a flow change for Saturday |
| Blank canvas fill | keep the dawn-to-dusk gradient | most editor screens draw it; white only on 04 |
| Home | design visuals; drop "N notes"; no bell (no feature behind it); Start still opens the editor | bell and the Mira-first flow are product calls |
| Chat voice | hold to talk, transcript fills the field for editing (not auto-send) | owner said "voice-to-text" |
| Chat photos | "+" tray (Photos / Camera); staged thumbnails; the photo is described by the image service and the description rides with the message (no backend change) | chat model is text-only |
| Image sheet third pill | "AI Sticker", routes to the Sticker tool | design label |
| Placed photo size | aspect-true (as today), r18 corners | design crops are mock content |
| Photo compare | hold = split Before / Current | both labels drawn at once |
| Photo edit extra tiles | keep Match page / Warm / Film / Frames after the design's four | existing features |
| Sticker "Jeans" style tile | omitted until the designer defines it | undefined |
| Keyboard | system keyboard, `.keyboardAppearance(.dark)` | custom keyboards out of scope |
| Canvas leading pill (P0) | "Home" on the bare canvas (way home); "Canvas" while a tool is open in place (Background, photo or sticker edit) and it folds that tool | the design's "Canvas" on the bare canvas has nowhere to go |
| Canvas card width (P0) | the page keeps its fixed 360 pt width, so the card sits 21 in on a 402 pt phone (design: 20 on 374) | widening the page would move every saved element and the export |
| Composer Go at rest (P0) | full ink as drawn, still disabled with an empty field | design draws it ink; the greyed pill read as broken |
| Muted text (P0) | #878476 as drawn for the leading nav label, composer placeholder and sheet subtitle (not the darkened #5E5C52) | fidelity bar; ~3.4:1, owner to confirm Saturday |
| Idle suggestion chips (P0) | removed from the canvas; follow-up chips stay on Mira reply cards; quick actions return in the screen-06 overlay (P2) | design draws nothing between tool bar and composer |

## Streams (one branch / PR each, stacked on P0)

- **P0 chrome** -- insets, NavPill, undo asset, composer type and highlight,
  `GlassSheet`, tool bar, canvas card r30 + shadow, header labels.
- **P1 text editor** -- screens 10-21.
- **P2 canvas** -- screens 04, 05 (Background rebuild), 06 (Mira canvas chat
  overlay), 07 (result sheet), 22 (drag-to-delete).
- **P3 Mira chat** -- screen 02 plus the WeChat composer, voice, photos.
- **P4 media** -- screens 08-09 (voice), 23-29/34-36 (image, photo edit),
  30-33/35 (sticker), 37-38 (export sheet, toast), 01 (Home), 03 (onboarding).

Audit reports with exact values: `gap-text.md`, `gap-canvas.md`,
`gap-media.md` (session scratchpad; key values are copied into each PR).

## Iterations

1. Audits of all 38 screens done (3 parallel read-only agents); plan and
   decisions recorded -- criteria 0/5 passing, no code yet.
2. P0 chrome landed: 16/20/19 insets, NavPill 70/60 x34 SemiBold 12 + undo
   asset, composer type/highlight, `GlassSheet` (ContextCard now draws it),
   tool bar shadow, canvas card r30 + rim + shadow, Save label, idle chips
   gone. iPhone 17 Pro frames within 1 pt of 04's rhythm (nav 64-98, card
   117-708, tool bar 728-768, composer 784-838) -- P0 1/1.
