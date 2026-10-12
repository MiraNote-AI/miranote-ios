# Redesign phase C: export formats and Mira quick actions

Refs #89 (A: #81, B: #85)

Jason, 2026-10-12: the long scrolling page is the model; cutting to a page
format is an optional export choice. Phase B's fixed-ratio step was dropped.

## Goal (acceptance criteria)

C1 -- export (`feat/export-formats`)
1. Export sheet keeps destinations first: Save to Photos (images), Save to
   Files, Share, Print.
2. Advanced: format PNG / JPG / PDF; PDF as one long page or A4 pages;
   quality Standard 2x / High 3x. Print always A4 pages.
3. Files carry the page title and the right type; Photos keeps the format.

C2 -- Mira quick actions (`feat/mira-quick-actions`)
4. The handoff's page-level quick actions are offered as Mira chips through
   existing turns (no new backend).

For every PR: kit `swift test`; Release build; full app suite; CJK check;
fresh-context review. HUMAN: visual match to screens 06, 37.

## Iterations

1. C1 written: PageExporter (render once per quality, encode per format, A4
   slicing) + 6 unit tests; ExportSheet with Files / Print and Advanced
   rows. UI test failed: Advanced sat in the home-indicator zone at the sheet
   bottom with a 12 pt row and taps missed -- moved up, 44 pt hit area.
   Full suite 22 unit + 48 UI green; Release OK.
2. Fresh-context review: DONE with should-fix: Photos re-encoded (format
   lost) -> PHAssetCreationRequest with the bytes; long PDF over the
   14,400 pt limit -> scaled to fit (+test); print outputType photo ->
   general. Nits fixed: blank A4 page from pixel rounding (+test; a 1e-6
   epsilon failed it, 1 pt tolerance passes), Photos button disabled until
   rendered, per-sheet temp folder, unused field, vacuous UI assertion.
   PageExporterTests 8/8.
