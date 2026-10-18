# Feature parity: dev (e67a4d3) vs fix/fidelity-review (2026-10-18)

The design rebuild rewrote `App/Sources/Screens/**` and silently dropped AI
image generation from the Image tool. This audit looks for anything else that
went missing.

Method: every user-reachable control on dev was listed from
`git show e67a4d3:App/Sources/Screens/**`. That covers buttons, context
menus, gestures, sheets, accessibility identifiers and accessibility actions.
Every UI test in `App/UITests` at e67a4d3 counts as a feature too. Each one
was then checked on HEAD, by identifier and label search and by reading the
code path.

Status values:
- **kept**: works as it did.
- **moved to X**: the same feature through another control.
- **changed per "Y"**: changed on purpose, recorded in the decisions table of
  `docs/plans/2026-10-15-design-fidelity.md`.
- **MISSING**: gone, with no recorded decision.

## Summary

| Item | Outcome |
|---|---|
| AI image generation in the Image tool | was MISSING; restored in 6075639 (AI Image pill, decision "Image sheet third pill") |
| Export sheet page preview (88x150) | MISSING; **owner to decide** (see below) |
| Everything else | kept, moved, or changed per a recorded decision |

## Table

| Feature | dev location | HEAD status |
|---|---|---|
| **Home** | | |
| Start a memory | HomeView "Start a memory" | kept |
| Ask-the-past field (opens chat with matching pages) | HomeView `quick.field`, `quick.send` | kept |
| Open a collection | HomeView `collection.<title>` | kept |
| New collection (name prompt) | HomeView `collection.new` + alert | kept |
| Recently deleted link | HomeView `home.trash` | kept |
| "N notes" on each card | HomeCollectionCard | changed per "Home" (count dropped) |
| **Collections / journals** | | |
| Open a note in Reading | CollectionDetailView `note.<title>` | kept |
| Long-press: Change date (date sheet) | CollectionDetailView context menu, `date.done` | kept |
| Long-press: Move to another collection | same menu | kept |
| Long-press: Delete (to the bin) | same menu | kept |
| + New memory | CollectionDetailView `note.add` (added an empty record) | changed per "New memory in a journal" (opens the canvas) |
| **Recently Deleted** | | |
| Restore | RecentlyDeletedView `trash.restore.<title>` | kept |
| **Reading** | | |
| Back / Share / Edit | ReadingView `reading.back`, `reading.share`, `reading.edit` | kept |
| Play a sound marker | PageRendering `reading.sound.play` | kept |
| **Export** | | |
| Save to Photos / Files / Print / Share | ExportSheet `export.photos/files/print/share` | kept (Print is a tile; Share is a header glyph per "Export entry") |
| Format PNG/JPG/PDF, PDF page layout | `export.format.*`, `export.pdf.*` | kept (always visible per "Export tiles") |
| Quality | `export.quality.*` | kept; Original added, default High per "Export quality" |
| "Advanced" fold with summary line | `export.advanced` | changed per "Export tiles" (no fold) |
| Inline confirmation text | `export.confirmation` | changed per "Save toast" (`export.toast`) |
| "Sound plays in MiraNote only" note | ExportSheet `hasSound` | kept |
| Rendered page preview (88x150) | ExportSheet `preview` | **MISSING** (owner to decide) |
| **Canvas elements** | | |
| Tap to select; tap selected text to edit; paper tap deselects | CanvasBoardView `handleTap` | kept |
| Drag to move; drag empty paper to scroll | `moveGesture` | kept |
| Two-finger rotate | `rotateGesture` | kept |
| Corner-handle resize | `resizeGesture` | kept (restyled per "Selected photo") |
| Drop below the canvas to delete, toast Undo | `canvas.deleteZone`, `toast.undo` | kept |
| Menu: Edit text / note / photo / sticker | CanvasBoardView+Menu `editEntry` | kept |
| Menu: Favorite ("Saved to Favorites") | `favoriteEntry` | kept |
| Menu: Duplicate / Bring to front / Send to back / Delete | `contextMenu(for:)` | kept |
| First-selection gesture hint | CanvasScene `gesture-basics` | kept |
| Breathing lock while Mira works on an element | `BreathingLock` | kept |
| Empty-page hint | CanvasBoardView | changed per "Blank page empty state" |
| "Tap where it should go" + Cancel | `canvas.place.hint/cancel` | kept |
| Header Home / undo / Done | EditorScaffold | changed per "Header trailing label" (Save, still files the page) |
| **Text** | | |
| Text tool adds a block | `addTextBlock` | kept (per "Page while writing") |
| Font row + S/M/L | `style.font.*`, `style.size.*` | kept per "Font row" |
| Text color swatches + custom | `style.color.*` | kept; custom via CustomColorSheet per "Custom color + eyedropper" |
| Text background | `style.highlight.*` | changed per "Text background none", "Swatch check / custom slot" |
| Alignment | `style.align` | kept per "Align tool" |
| AI Clean up / Expand | `style.ai` | changed per "AI rewrite" (in place) |
| Dictation into the block | `style.mic` | kept per "Dictation" |
| Keyboard Done | `keyboard.done` | moved to the header trailing pill (same id) |
| **Voice** | | |
| Armed: Cancel / Record | `recorder.cancel`, `recorder.record` | kept per "Voice armed state" |
| Recording: Discard / Stop | `recorder.discard`, `recorder.stop` | kept |
| Review: note / Re-record / Keep | `recorder.note`, `recorder.rerecord`, `recorder.keep` | changed per "Voice result" |
| Marker play; note edit | `sound.play`, `sound.note` | kept; tap-to-play per "tap to play" |
| **Image** | | |
| Library (multi-select) | ImagePanelScene `image.library.pick` | moved to Choose photos `image.library.open` + Recents grid (per "Image tool placement", "Multi-select grid") |
| Camera | `image.camera.open` | kept |
| Samples (debug) | `image.library.samples` | kept |
| Background describe; sway placement | `describeInBackground`, `add` | kept (PhotoPlacer) |
| AI image: prompt, generate, pick a result | `image.source.generate`, `image.prompt`, `image.generate.run`, `image.result.*` | was MISSING; **restored** (6075639) per "Image sheet third pill" |
| AI image style chips (Photo / Illustration / Watercolor) | `image.style.*` | changed per "Image sheet third pill" (no style chips; not drawn) |
| **Photo edit** | | |
| Filters (Match page / Warm / Film / B&W) | `photo.filter.*` | kept per "Photo edit tiles", "Photo edit extra tiles" |
| Frames White / Polaroid | `photo.frame.*` | kept as toggle tiles |
| Make sticker (cutout then outline) | `photo.makeSticker` | changed per "Photo edit tiles" (Cutout and Outline are separate tiles; the Sticker tool's `sticker.fromPhoto` still does both) |
| Ask AI | `photo.ai.instruction`, `photo.ai.run` | kept as the AI Editing tile + composer |
| Hold to compare | `photo.compare` | kept; split per "Photo compare" |
| Revert to the original, any time | `photo.revert` | changed per "Photo edit Cancel", "Photo editor visit" |
| Done | `photo.done` | moved to the header Done |
| **Sticker** | | |
| Generate | `sticker.prompt`, `sticker.generate.run` | kept |
| Pick a result to place | `sticker.result.N` | changed per "Sticker Add" (Add, then tap to place) |
| Favorites: tap to place, long-press to remove | `library.item.*` | kept |
| Tap the page to leave (not mid-work) | page tap | kept (scrim tap) |
| AI edit of a placed sticker | StickerEditPanel `sticker.ai.*` | kept |
| **Background** | | |
| Paper kinds | `background.paper.*` | kept |
| Page color swatches | `background.color.<hex>` | kept per "Swatch hexes" |
| Custom page color | `background.color.custom` | changed per "Custom / Pick" |
| Default chip | `background.default` | changed per "Background Default" |
| Mood chips | `background.mood.*` | changed per "Background controls" (Apply to this page) |
| Font sets | `background.fontSet.*` | changed per "Curated sets" |
| One-tap layout | `background.layout` | kept |
| **Mira** | | |
| Inline ask + Go | `mira.input`, `mira.go` | changed per "Mira chat composer" |
| Idle suggestion chips | `mira.suggestion.*` | changed per "Idle suggestion chips", "Mira chat quick actions" |
| Reply chips, dismiss | `mira.chip.*`, `mira.dismissReply` | kept |
| Failure + Retry; Stop | `mira.failure`, `mira.retry`, `mira.stop` | kept |
| Receipt with Revert | `mira.receipt`, `mira.revert` | changed per "Mira result", "Result sheet" |
| Image choices | `mira.imageChoice.*` | kept |
| **Chat** | | |
| Home | `chat.home` | kept per "Chat header" |
| Send | `chat.send` | kept (plus voice and photos, P3 rows) |
| Page hits; draft card | `chat.hit.*`, `chat.draft.open` | kept |
| **Onboarding** | | |
| Skip / Choose background / escape | `onboarding.skip`, `onboarding.background` | changed per "Onboarding" (escape kept) |

## MISSING with no recorded decision

### Export sheet page preview: owner to decide

- **On dev:** `ExportSheet.preview` in `e67a4d3:App/Sources/Screens/Reading/ReadingView.swift`
  showed an 88x150 thumbnail of the rendered page beside the destinations. It
  followed the quality setting.
- **On HEAD:** the sheet still renders the page (`rendered`), but only as the
  ShareLink preview. No view in the sheet shows it.
- **Docs:** no decision row mentions it.
- **Why not restored:** screen 37 draws the export sheet over the live page,
  which stays visible behind it. Adding a thumbnail would depart from the
  drawn sheet. Restoring it is cheap (about 20 lines in `ExportSheet.body`),
  but it is a design call.

## Observations (not missing; recorded decisions cover them)

- The photo editor's Cutout no longer adds the white outline in the same
  step, because Outline is its own tile. A one-tap outlined sticker from a
  photo is still the Sticker tool's "from photo" shortcut.
- The Favorites tab's "Tap to place. Long-press to remove." hint line is gone.
  Both gestures still work.
- From a painted page, returning to the default backdrop takes two dot taps
  (choose a dot, tap it again) where dev had one Default chip.
