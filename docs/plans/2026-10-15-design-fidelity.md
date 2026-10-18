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
| Image sheet third pill | removed (owner, 2026-10-17, TestFlight 1.0(5)): Photo Library and Camera only | stickers are the fifth tool; the pill duplicated it |
| Placed photo size | aspect-true (as today), r18 corners | design crops are mock content |
| Photo compare | hold = split Before / Current | both labels drawn at once |
| Photo edit extra tiles | keep Match page / Warm / Film / Frames after the design's four | existing features |
| Sticker "Jeans" style tile | omitted until the designer defines it | undefined |
| Keyboard | system keyboard, `.keyboardAppearance(.dark)` | custom keyboards out of scope |
| Canvas leading pill (P0) | "Home" on the bare canvas (way home); "Canvas" while a tool is open in place (Background, photo or sticker edit) and it folds that tool | the design's "Canvas" on the bare canvas has nowhere to go |
| Canvas card width (P0) | the page keeps its fixed 360 pt width, so the card sits 21 in on a 402 pt phone (design: 20 on 374) | widening the page would move every saved element and the export |
| Composer Go at rest (P0) | full ink as drawn, still disabled with an empty field | design draws it ink; the greyed pill read as broken |
| Muted text (P0) | #878476 as drawn for the leading nav label, composer placeholder and sheet subtitle (not the darkened #5E5C52) | fidelity bar; ~3.4:1, owner to confirm Saturday |
| Image tool placement (P4a) | opens in place over the live canvas (no separate scene): Choose photos sheet -> Recents -> placed, nav Canvas/Save, then Cancel/Add | 23-29 keep the live page visible; placed photos stay editable and selectable there |
| Multi-select grid (P4a) | option B, a custom PhotoKit grid (r18 cells, ink ring, order badges, "N selected"/"Editing"); denied access offers Settings or the system picker; -UITEST reads 9 painted samples | option A (inline system picker) could not draw the design's cells and its privacy notice could not be dismissed or driven by XCUITest |
| Image tool Cancel / Add after placing (P4a) | Cancel removes this visit's photos in one undo step (`CanvasViewModel.remove(itemIDs:)`); header Add keeps them and closes; composer Add reopens Recents | 25/29 draw Cancel/Add after placing |
| Photo edit tiles (P4a) | Outline = studio outline on the current pixels, in place; Cutout = composer target, the photo becomes a sticker in place; AI Editing = composer words, stays open on the result; filters/frames toggle | spec 6c; design 27 lights Outline while the composer speaks for Cutout, the app lights the tile the composer serves |
| Photo edit initial composer (P4a) | "Undo last edit or hold compare" / Done until AI Editing or Cutout is picked | no tile is chosen on open |
| Photo compare (P4a) | hold shows the split; a short tap pins it (also the VoiceOver action) | testable and accessible; hold still works as drawn |
| Before/Current labels (P4a) | on white@.72 capsules | plain muted text vanished on dark photos |
| Lifted photo (P4a) | aspect-true inside the 342x323 box, corner min(66, 20% of the short side) | placed photos stay aspect-true |
| Photo edit Cancel (P4a) | reverts to the session original (one undo step) and closes; scrim tap = Done | replaces the old in-card Revert |
| Selected photo (P4a) | 3 pt ink border on r18; corner resize dots kept | removing resize silently is worse |
| Sticker Add (P4a) | Add hands the showing result to the canvas, which asks where it goes (tap to place) | keeps the existing placement flow |
| Sticker presets (P4a) | Food set only (30 handoff PNGs, flat ground made transparent at bundling); tap places at centre | the heart/croissant/cat tabs have no sets yet |
| Sticker sheet while typing (P4a) | folds to the collapsed 147; Generate drops the keyboard | 430 does not fit above the keyboard |
| Josefin weights (P4b) | follow the tsx (Bold where it says Bold) | the 01 and 37 screen.png exports render Josefin at Regular although the tsx says Bold; 03/08/09 render Bold |
| Home cards (P4b) | design colors and #D9CDBA titles as drawn; titles wrap naturally, so "Daily Log" sits on one line | "Home = design visuals"; the design hand-breaks its sample titles |
| Home card titles (adversarial review) | **accessibility deviation, owner to confirm Saturday**: ink titles on the tan card (7:1); the grey and olive cards keep the drawn #8F7E76 / #878476 under paper titles (3.5 / 3.4:1, re-check); forest keeps #D9CDBA (8.4:1) | the drawn titles read at 1.5:1 on tan ("Little Joys" on a fresh install) and ~2.4:1 on grey and olive, under the 3:1 WCAG AA asks of large text (Bold 20) |
| Home prompt copy (P4b) | keeps "When was my Paris trip?" (Bold 14, ink@0.5) | "what i eat...." is mock content; the bar retrieves |
| Home hero (P4b) | centred; Fraunces stand-in with lines pulled 7 pt closer | design hero sits 8 pt left of centre; 1769_W05 unlicensed |
| Onboarding (P4b) | Back = blank canvas; Next and Go = Background; a row or strip icon opens that tool; undo drawn dimmed; strip tiles centred at the 56 pt pitch | FLOW Onboarding -> Background; nothing to undo |
| Voice armed state (P4b) | kept (no live mic without a press), restyled to the 54 pt ink recorder geometry | privacy |
| Recorder discard circle (P4b) | keeps an xmark | design circle is empty |
| Pending voice marker (P4b) | pulses where the take will land (blank page: 09's marker spot), not 08's canvas centre | the marker should appear where the sound goes |
| Voice result (P4b) | attach first, Revert / Keep sheet, no auto-keep; any other edit or tool tap keeps; re-record = Revert + Voice; note editing moves to the selected marker; the same `ResultSheet` as Mira's screen 07 (integration) | screen 09 |
| "tap to play" (P4b) | the tap that selects an unselected marker also plays it | the label must be true |
| Export entry (P4b) | stays in Reading (share button opens the in-scene sheet); Share as a header glyph in the sheet | decisions row "Header trailing label" |
| Export tiles (P4b) | fill the row (design 66x54 on 374); PDF hides Save to Photos and Files takes the ink; Print tile swaps the actions for one Print button; PDF adds a page-cut row | flexible widths on wider phones; Photos takes images only |
| Export quality (P4b, adversarial review) | default High; Original = 4x within a 24 MP budget, as low as the budget needs on a very long page (no 3x floor) | memory on long pages; the floor broke the budget (32 MP at 10,000 pt) |
| Save toast (P4b) | success closes the sheet; failure (#8C4A3A) keeps it, toast above; 2 s; no Open/Share bar | screen 38's Files UI is system UI |
| Idle suggestion chips (P0) | removed from the canvas; follow-up chips stay on Mira reply cards; quick actions return in the screen-06 overlay (P2) | design draws nothing between tool bar and composer |
| Screen 10 (P1) | reading (a): tapping Text shows the Text tool active, the editing header and "Type or polish your memory" for a 250 ms beat, then the block and keyboard appear | the minimal reading; the composer-as-entry reading changes the flow |
| Page while writing (P1) | the card keeps its full height; the keyboard and text chrome ride over it under the scrim; a new block lands a third of the way down (top 110) and the edited block scrolls to 30% | as drawn; the real keyboard is ~165 pt taller than the mock's, so the drawn mid-card text position would sit under the chrome |
| Text insets and line height (P1) | every block (old ones too) draws at 12/14 insets on a 30-on-21 line; background r24 in both states plus the screen-21 shadow | one geometry for editing, display, export and TextMeasure; old pages rewrap slightly |
| Josefin weight (P1) | the Josefin face renders Medium (500) as drawn | every text screen draws Medium |
| Font row (P1) | Futura, Josefin, Optima, Helvetica, Raleway, Didot, Classic (the old "" default); chip labels in their own face; S/M/L = 15/21/30 | design order; legacy blocks can return to their face |
| Swatch check / custom slot (P1) | checkmark symbol (forest on light, white on dark); an applied custom color fills the custom slot, which still opens the sheet | glyph contrast; one place to see and change a custom color |
| Align tool (P1) | every tap activates align and steps the alignment | existing tests and muscle memory; no dead first tap |
| AI rewrite commit (P1) | previews are free; leaving the row, Done, or header undo commits once (one undo step); typing makes the typed words the new Original; failures go in the dictation subtitle | screen 15 plus the implied states |
| Custom color model (P1) | the drawn curated spectrum; the hue rail turns it around the wheel (rail rests at 0.38, screen 14's handle); HEX and Pick color set the color exactly and move the target to the nearest spot | design spectrum identical on 14 and 20, so the rail cannot just pick from it; HSV would not look like the design |
| Custom sheet dock (P1) | the composer shows under the sheet ("Type or polish your memory") but is inert: a tap there, or on the page, cancels the sheet; swipe down on the sheet top cancels | screens 14/20 draw it; typing a Mira ask mid-color-pick has no meaning |
| Eyedropper (P1) | full-screen page snapshot with a 64 pt loupe; lift to take the color; Cancel keeps the sheet's color | "sample it from your memory": the page only, true colors (not the dimmed screen) |
| Dictation (P1) | hold to talk; a quick tap starts and a second tap stops (VoiceOver and tests use the tap) | hold as drawn, tap kept for accessibility |
| Cancel after Done (P1) | Done ends the session; the block stays selected (arrange state, screen 21) | screen 21 follows 20 |
| Background sheet size (P2) | the canvas card's width (360) and its height + 7; content scrolls on short phones, One-tap layout pinned 10 above the sheet bottom | screen 05 frames the sheet on the card |
| Background "Default" (P2) | no Default chip (not drawn): the chosen color dot tapped again returns the page to the gradient; the preview eyebrow reads DEFAULT / PAINTED / #RRGGBB | keeps the gradient reachable without an undrawn control |
| Swatch hexes (P2) | the design's five (#F6F4E8, #F4E0D1, #D6E3D4, #D1E0F0, #E6D9F0); old pages keep their stored hexes, unselected | screen 05 |
| Curated set page colors (P2) | 01 #D03A02, 02 #FCD766, 03 #879064, 04 #FBFBFC, 05 #236FB3, 06 #415A58, 07 #24382D, 08 #F59081 (from each card's band where its label sits); text colors as the card labels | the design does not say which band color is the page |
| Curated set card labels (P2) | "Poppins" (design typo "Poppin"); body-face names at 10 pt per the type floor; bands 01/02 sampled from screen.png (out-of-order Figma stops) | fidelity to what is rendered |
| Bundled faces not in the font row (P2) | the curated faces are not added to `TextFace.choices`; the font row is P1's | avoids a P1 conflict |
| Custom / Pick (P2, integration) | both open P1's `CustomColorSheet` over the dock (14 above the composer slot, riding the keyboard for HEX); the page previews live, Apply is one undo step, a tap outside cancels; Pick opens straight into the eyedropper | GAPS #2; one sheet for text, text background and page |
| Mira chat composer (P2) | the dark capsule IS the live composer (Figma "Canvas question composer"), a single-line field whose Send key (the system Return) sends -- a paste never does; the bottom composer is a button that opens the chat and shows a waiting draft with Go; Canvas, Done and a scrim tap close the chat | design draws no other field; draft never lost |
| Mira chat quick actions (P2) | the four as drawn, always; "Make text warmer" polishes the target text | design labels |
| Mira dictation (P2) | hold the strip to talk, release to transcribe into the question; never auto-sent; the system keyboard is set dark; one `DictationStrip` component with the text accessory (only the glass differs: screen 06 vs 11) | owner: voice-to-text |
| Result sheet (P2) | Keep = accept, Revert only when the turn changed something; an edit or a new ask moves on; the receipt timer is removed from the coordinator | screen 07 + decision above |
| Delete zone copy and color (P2) | one copy in both phases ("Drop here to delete / Release outside the canvas"), #D86C5D as drawn (2.3:1, owner asked for the design); arming shows on the lifted element's red frame; the design's microphone glyph is a copy-paste slip, a bin is drawn | screen 22 |
| Blank page empty state (P2) | no hint on the page | screen 04 |
| Chat header (P3) | Home on the chat's frost (white@0.62) and a forest Canvas pill that opens a blank page, both 70 wide on P0's `NavPill`; no title; the design's centre undo is left out | a conversation has nothing to undo |
| Chat composer (P3) | the design's 342x54 r27 surface laid out WeChat-style: voice toggle far left, the field growing from one line to four, then scrolling (the keyboard's Send key sends and the keyboard stays up for the next message; a paste never sends) or "Hold to talk", and "+" that turns into the Send pill once there is text or a photo | owner feedback 1 |
| Chat voice (P3) | hold shows the ink recorder bar (live bars, clock); release transcribes into the field with the keyboard up, never sent by itself; sliding up 60 pt cancels; VoiceOver gets a tap toggle | owner: voice-to-text |
| Chat photos (P3) | "+" opens a glass tray (Photos, up to 4; Camera); staged 56 pt thumbnails with remove badges; the image service describes each photo and the descriptions ride with the message as "(photo) ..." lines; sent photos show above the bubble | the chat backend is text-only |
| Chat hold-to-talk vs `DictationStrip` (integration) | kept separate: in the chat the composer itself becomes the hold button (WeChat), not a strip; the recorder plumbing also differs (chat view model vs canvas scene) | different control; a shared kit dictation helper is a follow-up |
| Text Cancel scope (review) | Cancel restores only the edited block from the session start; a Mira backdrop, restyle or photo edit that landed meanwhile stays, as its own undo step | the old whole-page revert took paid work with it (no Redo) |
| Lifted element (review, owner) | an ordinary move shows the element itself at full size; only armed over the delete zone does it shrink into the compact card | a big photo moving as a 164 x 82 card read wrong |
| Chat composer "+" (review, owner) | "+" always visible; Send appears beside it with text or a staged photo | photos can be added after typing |
| Photo editor visit (review, owner) | the floating Undo and header Cancel act on this visit's own edits only; Done keeps them; Compare still shows the photo as it came | "Cancel" next to "Done" means "discard this visit" |
| Curated sets on a text background (review, owner) | a block with a text background keeps its text color | set 01/03 black on the Ink chip read at ~1.2:1 |
| Merriweather (review, owner) | static Regular/Bold v2.002 (~0.3 MB) from google/fonts e9263a5 instead of the 4.6 MB variable font | one set, two weights |
| Food preset size (review) | presets placed at a 72 px short side at least (5 handoff PNGs are 50 x 22) | Favorites prunes anything under 24 px |
| Editor bottom gap (review) | 2 above the home indicator (36 from the edge, as drawn), 16 above a bare edge, 10 above a keyboard | a flat 2 sat on the SE's edge |
| Limited photo access (review) | the Recents sheet says only shared photos show and offers Share more (system limited picker) and Pick photos; a library observer refetches | the grid alone had no way to the other photos |
| Mira result vs Background (review) | opening Background keeps the waiting result and closes its sheet | the sheet covered the sets and One-tap layout |
| Chat photos storage (review) | sent chat photos live in tmp/ChatPhotos and are deleted when the chat closes | the transcript is not saved; Documents kept them forever |
| Photo editor reopened mid-edit (adversarial review) | Done during an AI edit keeps it running; reopening that photo is the same editor, showing the work; Cancel there never takes back the kept edit; the header Undo is visit-scoped like the floating one | two controllers for one photo let the late result wipe newer edits |
| Grown legacy text (adversarial review) | a text box that grows to fit (old 6 pt padding, a longer polish) pushes the elements below it (in its columns) down by the growth, in Reading/export and in the editor's remeasure (no undo step) | the grown box ran under the photo below |
| Chat picks (adversarial review) | picks load side by side, staged in pick order; one still loading after 20 s counts as failed; a loading placeholder has a remove badge | a stuck iCloud original held Send for good |
| Placed elements and text pushes (harness) | a text box's shrink never lifts an element above where it was last placed (drag, resize handle, Mira's page edit, Tidy); a pull held back is room the next push uses first; an element follows the element right above it that moved most, so the same fits reversed reverse; a box resized by hand starts its pushes afresh | the user's own placement wins; sizing back and forth (curated sets) must never drift the page |
| Typing's undo point (harness) | words typed after any step recorded during a writing session (Mira's title, a size) record a step of their own; after an undo past the session's start, the session starts again at its next change | one Undo took Mira's title and the words typed after it together, with no canvas Redo |
| Background "Apply to this page" (owner, TestFlight 1.0(5)) | Apply puts Mira's first painting on the page when it lands, as picking it from the choices would (receipt with Revert); the canvas chat's "Change background" still offers the choices | Apply left a choice tray nobody noticed: "Apply does nothing" |
| Background Apply (owner, TestFlight 1.0(6)) | never a dead pill: with no words Apply closes the sheet, keeping what the sheet applied (a hex typed but not confirmed included); with words the sheet stays up showing "Painting a background..." and the pill reads Stop, then closes on the canvas with the Revert / Keep sheet once the painting lands; a failure stays in the sheet with the reason and the words back | "Apply still does not apply": the empty-field pill was disabled, and the sheet vanished at the start of a turn |
| New memory in a journal (owner, TestFlight 1.0(5)) | opens the canvas; Save files the page in that journal | it added an empty record without opening anything |
| Empty blocks in history (harness) | restoring a step drops an empty block nobody is writing; an empty new block undone away never comes back by redo | an empty block outside a session was filed as part of the page |
| Follow-up: image file garbage collection | not done in this PR: `ImageFileStore` files no page references (AI results, preset taps, undone photos) are never deleted; needs a reference sweep across the library | out of scope for the fidelity PR |

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
3. P1 text editor landed: scrim + blur, three-layer accessory (rows /
   five-icon glass tool bar / hold-to-talk strip), header Cancel reverts the
   session, in-place AI rewrite, reusable `CustomColorSheet` with
   eyedropper, r24 text background, screen-21 frame; side-by-sides for
   10-21 match within ~2 pt except the system keyboard and the edited
   text's height on the page -- P1 1/1.
4. P2 canvas landed: Background rebuilt as the screen-05 glass sheet (preview,
   drawn page-type tiles, 5 swatches + Custom/Pick seam + hex, 8 curated sets
   with bundled OFL faces, Apply-to-page = Mira backdrop); Mira canvas chat
   (06) with hold-to-talk dictation; result sheet (07) with Keep/Revert and no
   timer; drag-delete zone in the composer slot with a lifted element (22);
   blank page empty (04); composer pill 19 from its trailing edge. iPhone 17
   Pro Max frames on the 05 sheet land on the spec to the point (tile 205,
   swatch 302, hex 351, sets 409, layout 518 from the card top); 06 within
   ~1 pt after half-leading fixes -- P2 1/1, composites in the PR.
5. P4a image / photo edit / sticker (screens 23-36) landed on iPhone Air:
   Image tool in place (Choose photos, PhotoKit Recents grid, placed state),
   lifted-photo editor (scrim, Undo / Compare / Favorite, tiles, split
   compare), Sticker sheet (tabs, Food set, spinner, preview, styles with
   undo/redo), kit `redo()` / `remove(itemIDs:)`. Kit 408, app unit 34, UI
   81 (3 skipped) green; Release builds -- P4a 1/1, owner to judge fidelity.
6. P4b landed (01 Home, 03 onboarding, 08/09 voice, 37 export, 38 toast):
   iPhone 17 side-by-sides within ~2 pt of the frames (bottom chrome
   anchored to the bottom on the taller phone); kit metering + Original
   quality + export toast tested -- P4b 6/6 screens.
7. P3 landed (02 Mira chat): header pills, greeting and Quick starts card,
   r28 Mira bubbles beside the 36 pt mark, the WeChat-style composer with
   hold-to-talk into the draft and photo staging (described for the
   text-only backend); greeting and Quick starts within 2 pt -- P3 1/1.
8. Integration: the six streams stacked P0 -> P1 -> P2 -> P4a -> P4b -> P3,
   each later stream reconciled in its own commit. Shared now: one
   `DictationStrip` (06, 11-20), one `ResultSheet` (07, 09), one
   `ComposerCapsule` (canvas, Background, tool pages; Go 19 in), one scrim
   token, `NavPill` surfaces for paper / chat / scrim, P1's
   `CustomColorSheet` for the page color too, `MiraMark` on 02 and 06.
   Kit 452, app unit 34, UI 111 (3 skipped) green on iPhone 17 Pro and
   16e; Release builds; 38 screens re-photographed side by side.
9. Review of #104-#109 (maverickjia): 21 should-fix and the nits fixed on
   `fix/fidelity-review`, each with a test that failed before where a
   probe could be written; owner decisions on the five questions applied
   (decisions above). Kit 463, app unit 48, UI 123 (3 skipped) green;
   swiftlint unchanged at 75; 22, 05 and 37 re-shot.
10. Harness, mutation and owner-fix rounds (TestFlight 1.0(5)): seeded
    sequence models, gate mocks, a debug state probe and a simulator
    monkey (docs/testing/adversarial-harness.md) found and fixed the
    placement, undo-point, empty-block and late-mic bugs above; 28 hand
    mutations of changed Kit logic, 6 survivors each given a test; owner
    fixes: no AI Sticker pill, New memory opens the canvas, Apply paints
    the page, the written block stays above the text tools, a cheap photo
    drag, an owner-path tour. QA: two outdated tests fixed (scroll a photo
    back after writing below it; the probe no longer matches staticTexts
    queries). Kit 533, app unit 72, UI 168 (4 skipped) green on iPhone 17
    Pro; Release builds.
