# Text tool opens without a stall Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

Refs #162 (the Text half; the Image / Sticker half is Jason's and is done).

**Goal:** After a tap on Text the screen ends up exactly as it does today
(new block, keyboard, text tools, dictation strip), but the keyboard and
the tools come up at once and move smoothly, with no wait and no stutter.

**Architecture:** Instrument the tap-to-settled path first (signposts, a
`textOpen` entry in the `-UITEST` debug probe, a final-layout test) and
take a baseline. Then remove what the code adds: the 250 ms "Text beat"
sleep, the light-to-dark keyboard swap mid-rise, and -- if the numbers
point at it -- the re-render and follow-up scroll that ride the rise.

**Tech Stack:** SwiftUI (iOS 26.5 simulators), OSSignposter / Logger,
XCUITest, Instruments (Animation Hitches) on a phone, xcodegen.

**Spec:** issue #162 ("Text tools appear without a visible delay (measure
before and after)"); Discord #general 2026-10-29 (the Text button opens
with a delay; no numbers, no device); the owner's requirement below.

## Owner's requirement and decisions (2026-11-14)

- The UI after the tap stays as it is today: where the block lands, the
  keyboard, the tool rows, the strip, and the page scrolling the block
  clear of the tools. Only the stall ("ka ke") while the keyboard and the
  tools come up goes away.
- D1 (the Text beat, screen 10): **A -- default 0.** The only visible
  change is that the Text button no longer sits lit for 250 ms before the
  keyboard starts. `-TEXT_MODE_BEAT <ms>` still stretches it for design
  shots and the beat tests.
- Execution: native (one session, task by task), one reviewer on the
  whole branch at the end.

## Diagnosis (origin/dev 8adad30)

From the tap to a settled screen, in order:

1. `CanvasScene.handleTool(.text)` -> `armTextMode()`
   (`CanvasSceneTools.swift:94`): the Text button lights up (0.15 s), then
   `Task.sleep(textModeBeat)` -- **250 ms**. Nothing else moves.
2. `addTextBlock()`: `editor.addText` + `startEditingText` +
   `textFocus = id`. The block's `Text` swaps to a vertical `TextField`
   (a `UITextView` underneath); the scaffold switches to
   `.ignoresSafeArea(.keyboard, edges: .bottom)` (`CanvasScene.swift:243`);
   `textAccessory` mounts; the keyboard starts to rise.
3. `DarkKeyboard.apply()` (`CanvasElementView.swift:183`) runs on the NEXT
   main-queue turn: the field is already first responder with a light
   keyboard, so it sets `.dark` and calls `reloadInputViews()` -- the
   keyboard is swapped while rising. Every open (each session mounts a
   fresh field).
4. While the tools ride up, `onGeometryChange` writes `textToolsTop`
   (`CanvasScene.swift:255`), an `@State` of the 1500-line `CanvasScene`:
   each write re-runs the whole scene body, and `CanvasBoardView`'s
   `onChange(of: textToolsTop)` starts `keepWrittenBlockClear`, which waits
   120 + 20 ms and then scrolls the page for 0.2 s
   (`CanvasBoardView.swift:378`) -- a second motion after the keyboard has
   landed.

| # | Cause | Expected cost | Where handled |
|---|---|---|---|
| H1 | The Text beat sleep | 250 ms of nothing, every open | Task 2 |
| H2 | Dark keyboard reload mid-rise | the keyboard re-laid-out while animating; possible light flash or restarted rise | Task 3 |
| H5 | Scene body re-runs on every `textToolsTop` write during the rise | dropped frames while the keyboard rises | Task 4 (if measured) |
| H6 | The keep-clear scroll starts 140 ms after the tools land | a second jump that reads as a stutter | Task 4 (if measured) |
| H3 | Cold system keyboard (first focus after launch) | system time, first open only | measured, not fixed |
| H4 | Accessory first render (7 font chips in their own faces) | expected under one frame | measured |

## Gates

- **After Task 1:** go on only if H1 + H2 are visible in the baseline:
  warm `accessoryMs` >= 230 and `darkReloads` == opens. Otherwise stop and
  report the numbers.
- **After Task 3:** do Task 4 only if, on the phone, the open still shows
  hitches (Instruments Animation Hitches: any hitch > 16 ms in the open
  interval) or `clearScrolls` > 0 for a new block. Otherwise skip it and
  say so in the PR.

## Risks

| Risk | Impact | Mitigation |
|---|---|---|
| R1 UI drift: any change moves the block, the tools or the scroll result | Breaks the owner's "same UI" requirement | `testTextOpenFinalLayoutUnchanged` pins today's frames (Task 1) and runs after every task |
| R2 Focus before mount: with no sleep, `textFocus = id` could run before the `TextField` exists, and no keyboard comes up (`finishToolsOnboarding` notes "focus needs its field on screen") | Text opens with no keyboard | Keep the existing `Task { }` main-actor hop (one turn, no sleep); every latency run asserts the keyboard came up |
| R3 Appearance leak: `prepare()` sets the global `UITextView` / `UITextField` appearance proxy | Mira bar / sticker / photo prompts get a dark keyboard | Release at one choke point (`editingTextItemID` -> nil, every exit goes through it); leak test on the Mira bar |
| R4 The proxy may not take on SwiftUI's backing `UITextView` | Task 3 has no effect | Probe counts real reloads; fallback in Task 3 Step 3; drop Task 3 if neither works |
| R5 Task 4 touches the keep-clear scroll, which already took five fixes (3b03391, 558d20a, 2b12b48, ee5fa9a, 8e1ba86) | A regression in "block hidden under the tools" | Task 4 changes only when the scroll starts and how often the state is written, never the target; the existing text editor UI suites must stay green |
| R6 Simulator timing noise; hitch metrics are only meaningful on a phone | Flaky thresholds, false "smooth" | Warm median over 4 opens with a threshold between before and after; hitches judged on the phone only |
| R7 Hardware keyboard connected in the simulator | No `keyboardDidShow`; the end event never fires | Setup turns it off; the test `XCTSkip`s when no software keyboard shows |
| R8 H3 cold keyboard is what people notice first | "Still slow" on the first tap after launch | Report cold separately everywhere; say plainly it is system time |
| R9 Conflicts: #163 edits `TextAccessory.swift` (FontChipRow); the local `dev` clone is 605 commits behind and dirty | Merge pain, testing stale code | Work in this worktree off `origin/dev`; do not touch FontChipRow; rebase before the PR |

## Validation plan

Automated (local only -- CI runs governance checks, never tests):

1. `TextToolLatencyUITests` on iPhone 17: warm median `ms` under T; one
   `keyboardWillShow` per open; `darkReloads == 0`; the Review Focus tests.
2. `testTextOpenFinalLayoutUnchanged`: the settled frames match the
   values recorded on dev before any change (R1). Runs after every task.
3. Mutation evidence (verify-repo rule): beat back to 250 -> the latency
   test fails; no `prepare()` -> the reload assertion fails; no `release()`
   -> the Mira bar test fails. Ledger below.
4. Regression: `TextEditorUITests`, `CanvasEditorUITests`,
   `DictationOwnershipUITests` (incl. `testLeavingDuringTheTextBeatStartsNoSession`),
   `TextEditorDesignShotsUITests`, `KeyboardDismissUITests`,
   `BackgroundUITests`, then full verify-repo (`swift test`,
   `swiftlint --strict`, `xcodebuild ... build test`).
5. Before and after numbers on iPhone SE (3rd generation), iPhone 17,
   iPhone 17 Pro Max simulators, cold and warm, with `sceneBodies` per open.

On a phone (HUMAN):

6. Dev build on a physical iPhone, before and after: Console.app (subsystem
   `ai.miranote.app`, category `TextTool`) for times; Instruments Animation
   Hitches over 1 cold + 5 warm opens for hitches.
7. Feel check: the tools follow the tap with no pause and no jerk; the
   keyboard is dark from its first frame; the screen settles where it does
   today; the Mira bar keyboard is still the default color after Done.

Hand-off: the table and the ledger go on #162 and in the PR body --
drafted, shown to the user, posted only on their OK.

## Measurements

ms = tap -> keyboardDidShow. Filled in by Task 1 (before) and Task 5 (after).
Simulator rows: median of 3 runs (cold = open 1, warm = median of opens
2-5), dev 8adad30 plus the Task 1 instrumentation, iOS 26.5, Xcode 26.6.
Warm focusMs was ~380 on all three: the keyboard then takes ~520 ms more
to land. keyboardShows was 1 on every open (the dark reload does not
restart the rise as a second show). On a full page the block settled at
top 136 in 9 runs of 10 and at 253.4 once, before any change.

| Device | Build | Cold ms | Warm median ms | Warm accessoryMs | darkReloads / opens | sceneBodies / open | clearScrolls / open | Hitches (phone) |
|---|---|---|---|---|---|---|---|---|
| iPhone SE (3rd gen) sim | before | 1603 | 885 | 312 | 5 / 5 | 6 | 0 | - |
| iPhone 17 sim | before | 1559 | 903 | 319 | 5 / 5 | 6 | 0 | - |
| iPhone 17 Pro Max sim | before | 1419 | 902 | 314 | 5 / 5 | 6 | 0 | - |
| phone (model?) | before | | | | | | | |
| iPhone SE (3rd gen) sim | after | 1440 | 587 | 43 | 5 / 5 | 6 | 0 | - |
| iPhone 17 sim | after | 1228 | 620 | 45 | 5 / 5 | 6 | 0 | - |
| iPhone 17 Pro Max sim | after | 1476 | 653 | 45 | 5 / 5 | 6 | 0 | - |
| phone (model?) | after | | | | | | | |

After rows: commit 8ca8c26, same method. The first run after switching
simulators was slower on two devices (757 warm on iPhone 17 and on 17 Pro
Max). On a full page (low block): clearScrolls 3 before, 1 after.

Task 3 outcome (dropped, per its Step 3 rule): no way found to make the
keyboard rise dark without the swap.
- Appearance proxy (`UITextView.appearance().keyboardAppearance`): crashes.
  `keyboardAppearance` is not an appearance property; UIKit throws when it
  applies the proxy as SwiftUI adds the field to the window
  (`_UIAppearance _applyInvocationsTo` -> `objc_exception_throw`).
- Set `.dark` in `textDidBeginEditing`: it takes (read back 1), but SwiftUI
  writes `.default` back on the field (`VerticalTextView`, a `UITextView`)
  in the same update; it is 0 again one main-queue turn later.
- `.environment(\.colorScheme, .dark)` on the field: no effect on the trait.
- Cost of the swap, measured: with `apply()` removed entirely (light
  keyboard), warm medians 675 / 609 / 605 ms against 636 / 620 ms with it on
  the iPhone 17 sim -- within noise. The ~500 ms from focus to
  keyboardDidShow is the system rise itself. Whether the swap causes a
  hitch only a phone can show (Instruments, `darkReload` signpost event).
- Untested lead, for a follow-up only if the phone shows a hitch at
  `darkReload`: one main-queue turn after `textDidBeginEditing`, SwiftUI
  has finished and `keyboardWillShow` has not fired yet (trace:
  begin, set=1, nextTurn=0, willShow, apply); setting `.dark` there without
  a reload could beat the rise. It races the keyboard, so it needs a
  fallback reload when willShow came first.

Threshold T (iPhone 17 sim) = after median + (before median - after
median) / 2, rounded up to the next 50 ms: 620 + 141.5 = 761.5 -> **800**.

Mutation ledger:
- Task 2: default beat back to 250 -> `testTextToolOpenLatency` FAILS (warm median 919 > 703); reverted -> PASS (636).
- Task 4: `clearScroll?.cancel()` removed -> `testLowBlockScrollsClearOnce` FAILS (3 scrolls); restored -> PASS (1).

Task 4 outcome: on a full page one open made 3 keep-clear scrolls (one per
step of the tools' rise), each a 0.2 s ease-out restarted 140 ms after its
step; now 1, same target. H5 refuted: 6 scene bodies per open, constant.
Open item: `TextVisibilityUITests.testDoneScrollsThePageBackToWhereItWas`
failed once on iPhone 17 Pro after the change (reopened block at 686 under
the tools at 416); 0 of 12 repeats failed after, 0 of 12 before.

## Rounds 2-5: the owner's simulator review

The owner watched each round in the Simulator and on 1/4-speed films
(`simctl io recordVideo`, scenes in `TextMotionRecordingUITests`). The
gate was the look: nothing splits, flashes or jumps; the settled UI is
unchanged.

- Round 2 (b76d3f6): an empty exit shrank the page above the falling
  keyboard (301 pt on iPhone 17) and grew it back. The page now keeps
  its height until `keyboardDidHide`; the flag is off SwiftUI state.
- Round 3 (81fc691): the Task 3 outcome above is superseded. The field
  asks SwiftUI for the dark color scheme (as the Mira chat field does),
  so the keyboard rises dark from its first frame and is never reloaded.
  Filmed before: 5 of 12 opens froze 80-365 ms mid-rise at the swap.
- Round 4 (44490a9): the tools showed ~140 ms before the keyboard. They
  now show in the `keyboardWillShow` frame (8 of 8) and ride up with it.
  The font row (a UIKit-backed scroll view that ignores SwiftUI offsets)
  rides as a static copy of its chips, offset to where the real row
  scrolls (pixel rounded), and hands over on `keyboardDidShow`.
  Film: font row and tool bar 0-1 pt apart on every frame; no chip
  shift at the hand-over. Accepted: a 1 px glyph nudge for one frame at
  the hand-over; the ~20 pt gap above the keyboard early in the rise
  (as before).
- Round 5 (c0ee30c): after Done the page went back in steps (probe:
  dropped 691 -> 483 as the writing room went, still 178 ms, then
  scrolled to 242). It now keeps the room until one 0.35 s slide lands
  (probe: one move, 75 -> 410 ms, 6 of 6; film: 1 phase against 2 on
  dev).

Deferred (minor, from the branch review):
- M1: `TextKeyboard.up` can go stale on a reopen during the keyboard's
  fall.
- M2: `noteDarkReload` has no caller since round 3.
- M6: the probe's `textToolsTop` reads 34 pt low while the tools wait
  hidden.
- M8: the `TextOpenTiming` probes are not DEBUG-gated.

## Global Constraints

- Committed text is ASCII only (org rule 3): code, comments, this doc, PR text.
- PR into `dev`; title `fix(ios): ...`, imperative, <= 72 chars, no `#N`; body references #162.
- The settled UI after a Text tap does not change (owner, 2026-11-14).
- No per-device constants in app code (issue #162).
- Simulators: iOS 26.5; iPhone SE (3rd generation), iPhone 17, iPhone 17 Pro Max.
- `-TEXT_MODE_BEAT <ms>` keeps working (design shots, beat tests, docs/testing/adversarial-harness.md).
- A new view-layer regression test ships with mutation evidence (verify-repo).
- FontChipRow and the size control are #163's; out of scope.
- Undo unchanged: one undo point per new block (`addText` records it).

## Review Focus

1. Double tap on Text (second tap inside the main-actor hop): one block, one session. Test in Task 2.
2. Text, then Sticker right away: back on the canvas, no session, no empty block. Test in Task 2.
3. Reopening an existing block by tapping it: dark keyboard, no reload. Test in Task 3.
4. After a session ends (Done or Cancel), the Mira bar keyboard is not dark. Test in Task 3.
5. A new block on a full page (placed low, so the keep-clear scroll must run): it still ends clear of the tools. Test in Task 4 (and in Task 1's layout test as the second case).

---

## Setup (once, before Task 1)

```bash
cd miranote-ios.worktrees/text-tool-delay        # branch fix/text-tool-delay
xcrun simctl create "iPhone SE (3rd generation)" \
  com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation \
  com.apple.CoreSimulator.SimRuntime.iOS-26-5   # not installed locally yet
defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false
xcodegen generate
```

Expected: `xcrun simctl list devices available` lists the SE; the build
succeeds on iPhone 17.

### Task 1: Instrument the Text open, pin today's layout, take the baseline

**Files:**
- Create: `App/Sources/Screens/Editor/TextOpenTiming.swift`
- Modify: `App/Sources/Screens/Editor/CanvasScene.swift` (`handleTool` `.text` case ~line 800; `debugState` ~line 1472)
- Modify: `App/Sources/Screens/Editor/CanvasSceneTools.swift` (`textAccessory` ~line 143)
- Modify: `App/Sources/Screens/Editor/CanvasElementView.swift` (focus `onChange` line 88; `DarkKeyboard.apply` line 185)
- Modify: `App/Sources/Screens/Editor/CanvasBoardView.swift` (`keepWrittenBlockClear` ~line 378: count the scroll)
- Create: `App/UITests/TextToolLatencyUITests.swift`
- Modify: this doc (before rows)

**Interfaces:**
- Produces:
  ```swift
  @MainActor enum TextOpenTiming {
      static func begin()              // Text tool tapped
      static func markAccessoryShown() // textAccessory onAppear
      static func markFocused()        // the block's field took focus
      static func noteDarkReload()     // DarkKeyboard actually reloaded
      static func noteClearScroll()    // keepWrittenBlockClear scrolled
      static var snapshot: [String: Any] { get }
  }
  ```
  `snapshot` keys: `opens` (Int, completed opens since launch), `ms`,
  `accessoryMs`, `focusMs`, `keyboardMs` (Int ms since `begin()`, -1 until
  seen), `keyboardShows` (Int, `keyboardWillShowNotification`s in this
  open), `clearScrolls` (Int, in this open), `darkReloads` (Int, since
  launch), `darkArmed` (Bool, false until Task 3).

- [ ] **Step 1: Write the tests** in `TextToolLatencyUITests` (launch `-UITEST`, "Start a memory"; read the `debug.state` probe the way `DictationOwnershipUITests:93` does).
  - `testTextToolOpenLatency`: 5 opens. Each: tap `mode.text`; wait up to 5 s for `app.keyboards.firstMatch` (`XCTSkip("hardware keyboard connected")` if none); poll until `textOpen.opens == i`; record `textOpen` and the probe's `sceneBodies` delta; tap `text.cancel`; wait for `mode.text`. Assert per open: `keyboardMs > 0`, `keyboardShows >= 1`, `accessoryMs >= 0`. Attach `text-open-ms` (cold = open 1, warm = 2-5) and print it.
  - `testTextOpenFinalLayoutUnchanged`, iPhone 17 only (`XCTSkip` on other models, read from the window size): two cases -- an empty page, and a page with three blocks written first so the new one lands low. Each: tap `mode.text`, wait for the keyboard, wait 1 s to settle, read the frames of `canvas.textEditor`, `style.mic`, `style.font.Josefin`, `keyboard.done`, `text.cancel`, and the keyboard. Assert each equals a recorded constant within 0.5 pt. In Step 2 the constants are placeholders; Step 4 records them from dev.

- [ ] **Step 2: Run them.**

Run: `xcodebuild -project MiraNote.xcodeproj -scheme MiraNote -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:MiraNoteUITests/TextToolLatencyUITests`
Expected: FAIL (no `textOpen` key; placeholder frames).

- [ ] **Step 3: Implement `TextOpenTiming`.** `OSSignposter(subsystem: "ai.miranote.app", category: "TextTool")`; `beginAnimationInterval("TextOpen")` at `begin()`, ended at `keyboardDidShow`, events at each mark (Instruments then shows hitches inside the interval). Times from `CACurrentMediaTime()`. Keyboard notifications are observed once (lazily, first `begin()`) and count only while an open is in flight. On `keyboardDidShow`: `keyboardMs`, `ms = keyboardMs`, `opens += 1`, end the interval, `Logger(...).info("text open ms=... accessory=... focus=... shows=... reloads=...")` for Console.app on a phone. `clearScrolls` counts calls until the next `begin()`. Call sites: `begin()` in the `.text` case before `armTextMode()`; `markAccessoryShown()` in `.onAppear` of the `textAccessory` VStack; `markFocused()` beside `DarkKeyboard.apply()`; `noteDarkReload()` in both reload branches of `DarkKeyboard.apply`; `noteClearScroll()` right before `proxy.scrollTo` in `keepWrittenBlockClear`; `debugState["textOpen"] = TextOpenTiming.snapshot`. No behavior change; on in Release too.

- [ ] **Step 4: Record today's layout.** Run `testTextOpenFinalLayoutUnchanged` once, read the frames it prints, write them as the constants (comment: "recorded on dev 8adad30, iPhone 17, iOS 26.5"). Run again: PASS. Run 3 more times: PASS every time (no flake from the caret or the scroll).

- [ ] **Step 5: Baseline.** `testTextToolOpenLatency` on the SE, 17 and 17 Pro Max simulators (3 runs each, median), and the phone (Console.app + Instruments Animation Hitches, 1 cold + 5 warm). Fill in the before rows. Apply the first gate.

- [ ] **Step 6: Commit**

```bash
git add App/Sources/Screens/Editor App/UITests/TextToolLatencyUITests.swift docs/plans/2026-11-14-text-tool-delay.md
git commit -m "test(ios): measure the Text tool open and pin its settled layout"
```

### Task 2: Open the text tools without the beat

**Files:**
- Modify: `App/Sources/Screens/Editor/CanvasSceneTools.swift:91-110` (`armTextMode`, `textModeBeat`)
- Modify: `App/UITests/TextToolLatencyUITests.swift`

**Interfaces:**
- Consumes: `textOpen` probe keys (Task 1).
- Produces: `textModeBeat` default 0; `-TEXT_MODE_BEAT` > 0 still wins.

- [ ] **Step 1: Write the tests.**
  - `testTextToolOpenLatency`: add `XCTAssertLessThanOrEqual(median(warm.ms), T)`; provisional T = before median - 200 until Task 5 sets the rule's value.
  - `testDoubleTapOnTextOpensOneSession`: two `mode.text` taps with no wait; type "one"; Done; exactly one static text "one", and the probe lists one text item.
  - `testTextThenStickerLeavesNoBlock`: `mode.text` then `mode.sticker` with no wait; `sticker.tab.make` exists; `nav.leading`; no `canvas.textEditor`, no `text.cancel`, no text item in the probe.

- [ ] **Step 2: Run them.** Expected: the latency assertion FAILS (beat still 250). Record whether the other two pass on dev.

- [ ] **Step 3: Default `textModeBeat` to 0** and skip the `Task.sleep` when it is 0; keep the `Task { }` hop and `guard textModeArming`, so Cancel or another tool inside the hop still calls it off (R2). Animate the button tint only when the beat > 0. Update the doc comments on `armTextMode` and `textModeBeat`.

- [ ] **Step 4: Run** `TextToolLatencyUITests` (incl. the layout test), `TextEditorUITests`, `CanvasEditorUITests`, `DictationOwnershipUITests`, `TextEditorDesignShotsUITests`. Expected: all PASS; the design shots still show screen 10 (`-TEXT_MODE_BEAT 2500`).

- [ ] **Step 5: Mutation evidence.** Default back to 250 -> `testTextToolOpenLatency` FAILS; revert -> PASS. Ledger.

- [ ] **Step 6: Commit**

```bash
git add App/Sources/Screens/Editor/CanvasSceneTools.swift App/UITests/TextToolLatencyUITests.swift docs/plans/2026-11-14-text-tool-delay.md
git commit -m "fix(ios): open the text tools without waiting out the Text beat"
```

### Task 3: Dark keyboard from its first frame

**Files:**
- Modify: `App/Sources/Screens/Editor/CanvasElementView.swift:183-198` (`DarkKeyboard`)
- Modify: every `editor.startEditingText` call site in `App/Sources` (known: `CanvasSceneTools.swift:129`, `CanvasBoardView.swift:639`; `git grep -n startEditingText App/Sources` for the rest)
- Modify: `App/Sources/Screens/Editor/CanvasScene.swift` (`onChange(of: editor.editingTextItemID)`, `editing == nil` branch ~line 480)
- Modify: `App/Sources/Screens/Editor/TextOpenTiming.swift`
- Create: `App/Tests/DarkKeyboardTests.swift`
- Modify: `App/UITests/TextToolLatencyUITests.swift`

**Interfaces:**
- Consumes: `TextOpenTiming.snapshot` (Task 1).
- Produces: `DarkKeyboard.prepare()`, `DarkKeyboard.release()`, `DarkKeyboard.isPrepared: Bool` (`@MainActor static`); `apply()` stays as the safety net. Snapshot gains `firstResponderDark` (Bool, read at `keyboardDidShow`); `darkArmed` mirrors `isPrepared`.

- [ ] **Step 1: Write the tests.**
  - `DarkKeyboardTests.testPrepareThenReleaseRestoresDefault`: after `prepare()`, `UITextView.appearance().keyboardAppearance == .dark`, same for `UITextField`; after `release()`, both `.default` and `isPrepared == false`.
  - Latency test: every open `keyboardShows == 1`; after 5 opens `darkReloads == 0`.
  - `testReopenedBlockGetsDarkKeyboardWithoutReload`: write "reopen me", Done, tap "reopen me"; keyboard shows; `darkReloads == 0`.
  - `testMiraBarKeyboardIsNotDarkAfterASession`: Text, Done; focus the Mira bar field (its identifier is in `MiraBar`); keyboard shows; `darkArmed == false`, `firstResponderDark == false`.
  - `testCancelRightAfterTapReleases`: `mode.text`, then `text.cancel` as soon as it exists; `darkArmed == false`.

- [ ] **Step 2: Run them.** Expected: the unit test does not compile (no `prepare`); `darkReloads == 0` FAILS (one per open today).

- [ ] **Step 3: Implement.** `prepare()` sets `keyboardAppearance = .dark` on `UITextView.appearance()` and `UITextField.appearance()` and sets `isPrepared`; `release()` puts both back to `.default`. Call `prepare()` right before each `startEditingText`, so the field SwiftUI creates in that update picks it up on entering the window. Call `release()` in the `editing == nil` branch beside `resetTextTools()`. If `darkReloads` is still > 0 (R4): observe `UITextView.textDidBeginEditingNotification` and set `.dark` there synchronously, without `reloadInputViews`. If neither reaches 0, drop this task's code, keep the data, say so in the PR.

- [ ] **Step 4: Run** the new tests, the layout test, `KeyboardDismissUITests`, `TextEditorUITests`. Expected: PASS.

- [ ] **Step 5: Mutation evidence.** No `prepare()` in `addTextBlock` -> `darkReloads == 0` FAILS; no `release()` -> the Mira bar test FAILS; restore both. Ledger.

- [ ] **Step 6: Commit**

```bash
git add App/Sources App/Tests/DarkKeyboardTests.swift App/UITests/TextToolLatencyUITests.swift docs/plans/2026-11-14-text-tool-delay.md
git commit -m "fix(ios): raise the writing keyboard dark instead of swapping it"
```

### Task 4 (gated): Smooth the rise

Only if the second gate says so. Each change keeps the scroll's target
and the settled layout; it changes only how often state is written and
when the scroll starts.

**Files:**
- Modify: `App/Sources/Screens/Editor/CanvasScene.swift:255` (`textToolsTop` write)
- Modify: `App/Sources/Screens/Editor/CanvasBoardView.swift:160,378` (`keepWrittenBlockClear`)
- Modify: `App/UITests/TextToolLatencyUITests.swift`

**Interfaces:**
- Consumes: `sceneBodies` and `clearScrolls` from the probe (Task 1).

- [ ] **Step 1: Write the test** `testRiseRerendersSceneAtMostTwice`: per warm open, `sceneBodies` delta <= 2 more than the count the Task 1 baseline shows for steps 1-2 alone (write the exact number from the before table into the assertion). Review Focus 5 is the layout test's low-block case; it must stay green.
- [ ] **Step 2: Run it.** Expected: FAIL if H5 is real (one body per `textToolsTop` write).
- [ ] **Step 3: Write `textToolsTop` only when it moves by >= 1 pt and only once the tools stop moving** (compare with the stored value in the `onGeometryChange` action; the final value is the same as today). If the phone still shows the follow-up jump (H6), start `keepWrittenBlockClear`'s scroll from the keyboard's final frame (`keyboardWillShow` end frame minus the accessory height) with the keyboard's own duration and curve, in place of the 120 + 20 ms wait; the anchor math is unchanged.
- [ ] **Step 4: Run** the new test, the layout test (both cases), `TextEditorUITests`, `CanvasEditorUITests`. Expected: PASS. Then the phone: no hitch > 16 ms in the open interval.
- [ ] **Step 5: Mutation evidence.** Remove the 1 pt filter -> `testRiseRerendersSceneAtMostTwice` FAILS; restore. Ledger.
- [ ] **Step 6: Commit**

```bash
git add App/Sources/Screens/Editor App/UITests/TextToolLatencyUITests.swift docs/plans/2026-11-14-text-tool-delay.md
git commit -m "fix(ios): keep the canvas still while the text tools rise"
```

### Task 5: After numbers and the full check

**Files:**
- Modify: this doc (after rows, T, ledger)

- [ ] **Step 1: After numbers.** Repeat Task 1 Step 5 on the same simulators and the same phone. Fill in the after rows; set T by the rule. Expected: warm median down by at least ~250 ms; `darkReloads` 0; no hitch > 16 ms on the phone.
- [ ] **Step 2: Full verify-repo:** `(cd MiraNoteKit && swift test)`, `swiftlint --strict`, `xcodegen generate && xcodebuild -project MiraNote.xcodeproj -scheme MiraNote -destination 'platform=iOS Simulator,name=iPhone 17' build test`. Expected: all green, 0 violations.
- [ ] **Step 3: HUMAN feel check on the phone** (Validation plan item 7). Note it in the doc.
- [ ] **Step 4: Commit**, rebase on `origin/dev`, rerun Step 2 if anything came in.

```bash
git add docs/plans/2026-11-14-text-tool-delay.md
git commit -m "docs(ios): record the Text tool open times before and after"
```

- [ ] **Step 5: Draft the #162 comment and the PR body** (table, ledger, what is still system time per R8). Show both to the user; push, open the PR, or post only after they say yes.
