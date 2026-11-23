# Mira chat: one bottom input with a mic

Refs #248. Decision page (option B):
https://claude.ai/artifact/9QMM4F7Kx3kFYGJNwcALTd

**Goal:** The Mira canvas chat asks from one box at the bottom -- the
canvas writing chat box, reused -- with its mic on the right; the
"Mira Dictation" strip and the dark capsule under the header are gone.

## Acceptance criteria

1. No dictation strip; the field is below Mira's panel, its box just
   above the keyboard, and above the home indicator with the keyboard
   down (CanvasMiraFidelityUITests
   testTheQuestionBoxSitsAtTheBottomWithItsMic).
2. The box is `WritingChatBox` (light pill, placeholder "Ask Mira
   anything", dark round mic), not a copy.
3. Mic: hold to talk and tap to toggle (testHoldToDictateFillsTheQuestion,
   testATapTogglesTheMic, DictationTakeOrderUITests,
   DictationOwnershipUITests); words turn the mic into Go, clearing
   brings it back, Go sends (testTheMicBecomesGoWithWordsAndGoSends).
4. The transcriber-unreachable hint (a 503) shows over the box by the
   mic, as the writing box shows its own (testAnUnreachableTranscriber
   SaysSoByTheMic).
5. Panel, quick actions, Canvas / Done header unchanged (existing
   CanvasMiraFidelityUITests, KeyboardDismissUITests).
6. HUMAN: the team lead approves the recorded video and screenshots
   before the PR opens.

## Decisions

- Scope: only the canvas chat (`MiraChatOverlay`) showed the strip. The
  chat Home opens (`MiraChatView`) has its own WeChat-style composer
  and no strip, so it is unchanged.
- `WritingChatBox.Names` carries the placeholder and identifiers; the
  chat keeps the old ids (`mira.input`, `mira.dictation`), and its Go is
  `mira.ask`.
- The box's caption (Listening, words on their way, or why none landed)
  sits over the box like the writing box's caption over its rows; the
  mic's VoiceOver value says the same.
- The chat keeps its field while the mic listens (it passes no
  recorder, so the box shows no waveform): the words land in this field, and taking
  it away for the writing box's waveform dropped the keyboard mid-hold
  and broke the #150 "keyboard comes back" behavior. The writing box is
  unchanged.
- With words in the box Go replaces the mic (as in the writing box);
  take-order tests that read the mic's value after words landed read the
  caption or the debug probe's micLive instead.
- `DictationStrip` is gone; `holdToTalk` stays (HoldToTalk.swift).
  Catalog entries only the strip used are removed.

## Iterations
1. WritingChatBox reused at the bottom of MiraChatOverlay, strip gone --
   CanvasMiraFidelity: layout test 125 pt off, the tap toggle lost the
   field; 3 take-order tests read the mic after Go took its place.
   Root cause of the layout number: the simulator had no software
   keyboard in the editor (Simulator default ConnectHardwareKeyboard
   unset; origin/dev the same). Set it false.
2. Field kept while listening, "Listening..." caption; layout test
   tolerates iOS 26's keyboard frame (reports lower than drawn) --
   CanvasMiraFidelity 14/14, DictationTakeOrder 14/14,
   DictationOwnership + KeyboardDismiss + MiraImageAsk + TextChatBox 44/45
   (TextChatBox testTheGoKeySendsWithAnAutocorrectionPending fails the
   same on origin/dev and on #249). Mutation: the box moved back under
   the header fails the layout test ("the box is under Mira's panel").
3. Fresh-context review: DONE, taken -- the mic stays (never Go) while a
   press is in progress, so an earlier take's words landing cannot pull
   it from under the finger; the "no strip" check measures the mic (the
   old assertion could not fail); the overlay passes one caption (no
   separate status) and no recorder instead of a flag; doc comments.
   Not taken: removing the "Ask Mira" catalog entry (#249 uses it).
   Noted for the team lead: with words in the box Go replaces the mic,
   so a second take cannot be added to typed words (the strip allowed
   it). CanvasMiraFidelity + DictationTakeOrder 28/28,
   DictationOwnership + KeyboardDismiss Mira + TextChatBox 31/32 (the
   pre-existing autocorrection test).
