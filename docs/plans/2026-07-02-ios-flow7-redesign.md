# MiraNote iOS -- Flow 7 visual redesign

**Date:** 2026-07-02
**Design source (Rule 6 reference):** Figma "MiraNote" file, section
`MiraNote Mobile UX Flow 7`
(https://www.figma.com/design/RzbhtW6CIWRThwJJ0hSxHo/MiraNote?node-id=0-1),
provided by Meng as a full-fidelity screenshot of all 11 scenes.
**Supersedes:** the sketch-based `docs/specs/2026-06-10-ios-app-v1-design.md`
interaction model (free canvas + long-press menu + modal sheets).

## Deviations from the run-loop default (recorded up front)

- **No GitHub issue, no PR.** Meng chose local-only delivery: build the whole
  flow in the working tree, verify green, QA every screen against Figma, then
  hand off for human review. Terminal state is HANDOFF-to-Meng, not
  `create-pr`. Nothing is committed or pushed by the loop.
- **Iteration cap raised to 40** (default 5). Rationale: 11 screens + a design
  system + test reconciliation, each screen needing its own act->screenshot->
  fix sub-cycles. The real guard here is the no-progress rule (2 consecutive
  no-progress iterations -> stop + handoff), not the numeric cap.
- **Visual fidelity is a `HUMAN:` criterion.** No command can assert "matches
  the Figma"; Meng is the reviewer. The loop asserts the mechanical criteria
  (build/lint/test/screens-render) and produces the screenshots Meng judges.

## Goal -- acceptance criteria

- G1 `HUMAN:` All 11 Flow 7 scenes are implemented and read as the Figma
  design (palette, editorial-serif type, page layout, component shapes),
  judged by side-by-side simulator screenshots vs the Figma.
- G2 App builds: `xcodebuild -project MiraNote.xcodeproj -scheme MiraNote
  -destination 'platform=iOS Simulator,name=iPhone 17' build` exits 0.
- G3 `swiftlint --strict` -> 0 violations.
- G4 Tests green: `(cd MiraNoteKit && swift test)` AND the xcodebuild `test`
  action (MiraNoteTests + MiraNoteUITests) exit 0.
- G5 Every one of the 11 scenes is reachable in a `#if DEBUG` screen catalog
  (launch arg `-MIRANOTE_SCREEN <id>`) so each renders deterministically for
  QA screenshots.
- G6 No CJK/emoji in any source or scratch file inside the repo (Rule 3).
- G7 `MiraNoteKit` public API (models, services, the 5 view models) and its
  tests are preserved -- the redesign is view-layer + additive kit, not a
  rewrite of tested logic.

## Design tokens (the build derives every value from here)

Palette (warm earthen; forest-green + near-black are the accents, NOT
terracotta -- this is the client's delivered identity, followed as-is):

| token | hex (start; refine in QA) | use |
|---|---|---|
| ink | #1E1B16 | primary text, primary (black) pills |
| onInk | #F5F1E9 | text/icons on ink |
| forest | #333D2C | dark accent card (Travel Scrapbook), active depth |
| taupe | #8C8073 | secondary card, muted brown-gray |
| tan | #C9B295 | warm wheat card / accent fill |
| sage | #8E8D77 | muted green-gray (swatch 2) |
| paper | #F3EFE6 | screen background |
| cardFill | #E7DFD1 | image-area / page card fill (warm greige) |
| sheetFill | #DCD6C8 | rising context card background |
| hairline | #E0D9CB | dividers, page strokes |
| textSecondary | #8A8478 | captions, inactive labels |

Type:
- Display / titles / dates -> **Fraunces** (variable, bundled; SIL OFL),
  weight + optical size pinned via CoreText. Closest free match to the
  Figma editorial serif. Fallback: system `.serif` (New York) if the
  variable face misrenders.
- UI / body / labels / captions -> **system SF Pro** (native, no asset).

Shared components (built once, reused across scenes):
1. TopBar -- leading context button | centered serif title | trailing black
   "Save" pill.
2. SubToolbar -- Page / Spread / Undo / zoom% segmented row.
3. MemoryPageCard -- serif title + caption + gradient image area + text lines;
   overlay variants (text, sticker, filter tint).
4. InputModeBar -- bottom segmented Voice / Text / Image / Sticker, active =
   dark pill.
5. ContextCard -- the card that rises above InputModeBar (per-scene body) +
   an action row (hint text + black "Go"/primary pill).
6. Pills -- primary (ink), secondary (light), chip/segment.
7. HomeCollectionCard -- the 2x2 memory cards (one forest).

Image areas / photo tiles / stickers are rendered with SwiftUI gradients and
shapes (the Figma itself uses gradient placeholders) -- no bundled photos.

Signature element: the editorial serif set on warm paper, paired with the
forest/ink "instrument panel" (the Voice/Text/Image/Sticker segmented bar +
rising context card). Boldness spent there; everything else stays quiet.

## Scene checklist (Flow 7)

- [ ] S01 Home -- hero "Your memory, beautifully made.", Start a memory, date,
      quick pill, 2x2 collection grid (Daily Log / Travel Scrapbook forest).
- [ ] S02 Canvas -- page + InputModeBar + "Choose voice, text, image, or
      sticker" hint + Go.
- [ ] S03 Voice input -- voice-memory waveform card + Convert to text; bottom
      recorder waveform + 0:12.
- [ ] S04.1 Text input -- Font/Color/Effect/Bubble row + "Type or polish your
      memory" + Go.
- [ ] S04.2 Text story input -- dimmed state, entered text, system keyboard up.
- [ ] S05 Image input start -- Choose photos card (Photo Library / Camera).
- [ ] S06 Photo Library -- My Photos, Recents, selectable grid w/ number
      badges, Preview selected + Go.
- [ ] S07 Filter preview -- Change filter: Original / Warm / Soft / Film +
      Apply + Go.
- [ ] S08 AI Sticker -- Create sticker card: prompt + Generate; chips.
- [ ] S09 Sticker Library -- Stickers card: Favorites/AI Made/Cutouts/Trending
      tabs + items, Add + Go.
- [ ] S10 Export -- Export & save: PNG/PDF/JPG/Print + Standard/High/Original +
      Save to Photos.

## Test reconciliation (the old UI tests assert the retired interaction model)

- `testEmptyStateHintShownOnFirstLaunch` -> rewrite for the new Home (hero +
  Start a memory + collection cards).
- `testSaveKeepsCanvasAndFilesCollection` -> rewrite to drive the new
  step-based flow's save/round-trip (keep the Save-does-not-wipe regression
  intent, now against the new editor).
- `testLongPressMenuAppearsAtTouchPoint` -> retire (no long-press menu in Flow
  7); replace with an InputModeBar tab-switch assertion.
- Any new view-layer regression ships with mutation evidence per the repo's
  xcuitest ledger convention.

## Iterations

(append one line per act+verify cycle; cap = 40; no-progress after 2)

1. Built design system (Palette, Typography w/ bundled Fraunces via CoreText,
   Metrics, Pills, 6 shared components), all 11 scene views, DEBUG screen
   catalog + launch-arg harness, wired Fraunces into project.yml. Deleted the
   retired views (CanvasView/Toolbar, 3 sheets, old Theme). Fixed one
   `.frame` arg-order error. `xcodebuild build` -> SUCCEEDED (G2). Home
   snapshot QA'd: Fraunces renders (not the fallback), warm palette correct,
   layout matches Figma S01. Criteria: G2 pass, G5 pass, G1 1/11 verified.
2. Snapshotted all 11 scenes; every one reads as its Figma frame (fonts,
   palette, layout). Fixed 3 label-wrapping defects: InputModeBar labels
   (fixedSize + lineLimit + tighter padding), Chip never-wrap + a `compact`
   variant for the sticker tabs, and the photo-library sheet double-padding
   the instrument bar. Build SUCCEEDED. G1 11/11 first-pass verified; fixes
   pending re-snapshot of canvas / imageStart / photoLibrary / stickerLibrary.
3. Re-snapshotted the 4 fixed scenes -> wrapping gone, all read cleanly.
   Wired the interactive flow: EditorActions closures on every scene (default
   no-op so the catalog stays static), EditorFlowView state machine (Home ->
   Start a memory -> canvas; instrument panel swaps scenes; Go advances
   image->photos->filter and sticker->library; Save -> Export -> Save to
   Photos returns Home), HomeFlow fullScreenCover, root -> HomeFlow. Added
   accessibility ids to mode buttons. Rewrote the 3 retired XCUITests as 4
   new-flow tests (hero+start, start->canvas, mode switching, save round-trip).
   VERIFY: xcodebuild build test -> TEST SUCCEEDED (unit + 4 UITests);
   swiftlint --strict -> 0; MiraNoteKit swift test -> pass; text files ASCII.
   G2/G3/G4/G5/G6/G7 pass. G1 is HUMAN (Meng's visual review). Next:
   fresh-context code review, then handoff.
4. Fresh-context subagent review (given only criteria + diff): no blockers,
   no majors; independently confirmed MiraNoteKit untouched, state machine has
   no traps/dead-ends, CoreText font path + fallback correct, no
   force-unwraps / retain cycles / OOB. Applied 2 of its minor UX notes:
   canvas "Go" now opens Text (was inert); voice "Convert to text" now a live
   button. Re-verified: swiftlint --strict -> 0; xcodebuild build test ->
   TEST SUCCEEDED. Re-snapshotted all 11 from the final build for handoff.

5. Feedback from Meng: the Home "what I eat..." quick-capture pill was a
   static placeholder, not a usable input. Made it a live TextField (send
   button appears on input; submit opens the editor via onQuickCapture ->
   HomeFlow). Added UITest testQuickCaptureFieldOpensEditor (types -> send ->
   editor). Re-verified: swiftlint --strict -> 0; xcodebuild build test ->
   TEST SUCCEEDED (now 5 UITests). Open question raised to Meng: whether the
   field should open the editor (current) or drive a dedicated AI chat screen
   (new; needs a real chat backend -- currently only mock services exist), and
   whether the typed text should carry into the editor content.

6. Meng chose a real AI chat page for the quick-capture field. Built it:
   additive Kit (ChatMessage, ChatService + MockChatService with warm
   deterministic replies, ChatViewModel; chat added to ServiceContainer with a
   defaulted param so nothing breaks). MiraChatView in the app -- bubbles,
   typing indicator, input bar, "New memory" hand-off, in the MiraNote design
   language. Home quick-capture now opens the chat seeded with the typed text
   (HomeFlow route enum); chat -> New memory -> editor. Added FlowScene.chat to
   the catalog. UITests updated: testQuickCaptureOpensChat + a new
   testChatNewMemoryOpensEditor (6 UI tests total). Re-verified: swiftlint
   --strict -> 0 (49 files); xcodebuild build test -> TEST SUCCEEDED; Kit tests
   still green (ServiceContainer change was additive). Snapshotted the chat.

7. Meng chose to wire the real chat backend. Made ChatService session-aware
   (ChatReply{text,sessionID}; server keeps the transcript keyed on session_id,
   so the client only carries the id). Added LiveChatService posting to
   `:8003/chat`, chatBaseURL in config, ChatViewModel now tracks the session id,
   .live wired to LiveChatService, chat errors surface the real BackendError
   (spec D9). Tests: 3 LiveChatServiceTests (StubURLProtocol) + a
   .live-wires-chat assertion. Verified: MiraNoteKit swift test (incl. new
   chat tests) pass; swiftlint --strict 0 (51 files); xcodebuild build test ->
   TEST SUCCEEDED (chat UITests hold since they assert header+user bubble, not
   the reply). END-TO-END: started the chatbot POC on :8003 (DeepSeek
   v4-flash), curl /chat returned a real reply through the exact
   {session_id,reply,tool_trace} contract -> integration confirmed. Note: the
   retrieval tool (:8004) is offline, so doc-lookup tool calls fail gracefully
   inside the LLM turn; core chat is unaffected. Added a DEBUG MIRANOTE_CHAT_LIVE
   flag to eyeball live replies from the catalog chat scene.

8. Meng: turn the 4 placeholder notebook cards into real, persisted note
   collections. Kit (additive): Memory/MemoryCollection made Codable (+
   Hashable); CollectionStore protocol + FileCollectionStore (JSON in
   Documents, seeds 4 default collections on first run) + InMemoryCollectionStore;
   HomeViewModel reworked to be store-backed (designated init(store:), the
   existing init(collections:)/file()/startMemory() preserved) with
   addCollection/addNote and persist-on-change. App: Home grid now data-driven
   from the real collections (live note counts, tappable, cycled card colors,
   a New-collection card with a name prompt); new CollectionDetailView lists a
   collection's notes with Add note; HomeFlow wraps a NavigationStack, owns the
   persistent VM, pushes the detail, and files a memory when the editor
   finishes or the chat's New memory fires (chat now files the conversation and
   returns Home). Catalog gets a `collection` scene + seeded Home; UI tests use
   `-UITEST` for a fresh in-memory seed and offline mocks. Tests: CollectionStore
   round-trip + seed, HomeViewModel add/persist-through-file-store,
   testOpenCollectionAndAddNote, testChatNewMemoryFilesToCollection (7 UI tests).
   Verified: MiraNoteKit swift test pass; swiftlint --strict 0 (54 files);
   xcodebuild build test -> TEST SUCCEEDED.

9. Meng: make each note openable. Added Memory.body (Codable). HomeViewModel
   gained note(_:in:) and updateNote(_:in:title:body:) (persist + stamp
   savedAt). NoteDetailView: editable serif title + body TextEditor, loads by
   id, saves on exit. CollectionDetailView rows are now buttons -> open the
   note. HomeFlow switched to a NavigationPath (Home -> Collection -> Note) with
   a NoteRef value. Catalog gains a `note` scene. Tests: updateNote edits,
   note-edits-persist-through-file-store, UITest testOpenNoteOpensEditor.
   Verified: MiraNoteKit swift test pass; swiftlint --strict 0 (55 files);
   xcodebuild build test -> TEST SUCCEEDED (8 UI tests).

## Terminal state: HANDOFF to Meng for visual acceptance

Per the local-only choice, the loop stops here (not create-pr). Everything is
built + green in the working tree; nothing committed or pushed. Mechanical
criteria G2-G7 all pass; G1 (Figma fidelity) is Meng's to accept. Deliverables:
a review contact sheet (11 screens + status, published as a claude.ai artifact)
and the live app installed on the iPhone 17 simulator. Since then Meng added
two features (both done, verified, snapshotted): a usable Home quick-capture
field, and a MiraNote AI chat page wired to the live :8003 backend. Follow-ups
noted for a later loop: run the retrieval POC (:8004) so in-chat doc lookups
work; carry chat text into the editor as the memory's starting content;
optionally strip emoji from LLM replies (they render as missing-glyph boxes);
optional italic Fraunces for the hero's second line; confirm the exact Figma
typeface to replace the Fraunces substitute.
