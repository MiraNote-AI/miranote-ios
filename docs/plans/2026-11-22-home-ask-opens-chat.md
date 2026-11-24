# Home ask bar opens the Mira chat

Refs #247.

**Goal:** One tap anywhere on Home's ask bar opens the Mira chat at once,
with the caret in the chat's own field and the keyboard up. Home has no
field and raises no keyboard.

## Acceptance criteria

1. A tap on the bar (its text or its star) opens the chat; the chat field
   has keyboard focus within 1 s (KeyboardDismissUITests Home cases).
2. No text field and no keyboard on Home before the tap (same tests).
3. VoiceOver: one button, label "Ask Mira", hint "Opens the Mira chat".
   The label and button type are tested; HUMAN: the hint (XCUITest cannot
   read it).
4. The Home prompt state (`prompt`, `promptFocused`, `submitPrompt`,
   `quick.field`, `quick.send`, the page tap and scroll that lowered the
   bar's keyboard) is gone; every UI test that typed into the bar opens
   the chat by the bar and types in the chat instead.
5. Kit tests, `swiftlint --strict` and the touched UI test classes pass.

## Decisions

- The chat opened by the bar has no seed; with no seed the composer takes
  the keyboard once on appear (a camera cover bringing it back does not
  raise it again). The debug and catalog chat screens keep their seeds
  and open without the keyboard, as before.
- `Theme.promptTint` (the bar field's caret) went with the field.

## Iterations
1. Bar becomes a button, chat focuses its field on open, tests moved to
   the new flow -- 41/46 touched UI tests green; the new 1 s focus check
   failed (predicate expectation polls ~1 s); OwnerTour chat overlap
   false positive (keyboard up scrolls chips under the header pills).
2. 50 ms focus poll; tour lowers the keyboard before its overlap check;
   VoiceOver test asserts button + label only (XCUITest lists a button's
   subviews though VoiceOver does not) -- touched tests green. Mutation:
   without the focus line the three focus tests fail (after 1.0 s).
   swiftlint --strict: 231 violations, origin/dev has 232, none in new
   lines.
3. Fresh-context review: DONE with minor findings, all taken -- the
   vacuous leave test became "focuses the field every time" (re-open);
   comments; demo runbook beats 1-2. Timing measured: XCUITest's tap
   returns 0.6-1.0 s after it starts, the field focused within 0.12 s
   of that; the 1 s budget counts from the tap's return.
   KeyboardDismissUITests 12/12 + OwnerTour chat green.
4. Full suite (xcodebuild test-without-building, iPhone 17 Pro iOS
   26.3): unit 211 green; UI 465 run, 24 skipped, 4 failed. Caught a
   real regression: SwipeBackUITests.testSwipeOnHomeLeavesHomeUsable --
   the edge swipe ends on the bar and a SwiftUI Button fires on a drag
   that ends on it, opening the chat. The bar is a tap gesture again,
   with button trait, label, hint and activation for VoiceOver. The
   other 3 (BackgroundPaint testTheCardHoldsStillUnderTheApplyKeyboard,
   TextChatBox testTheGoKeySendsWithAnAutocorrectionPending,
   TextVisibility testTypingOnTheSameLineBringsTheBlockBack) fail the
   same way on an origin/dev build: pre-existing. After the fix:
   SwipeBack 3/3, StarJar 17/17, OwnerTour 3/3, the Home ask tests and
   the chat-from-Home tests green.
5. Second fresh-context review (tap-gesture change): DONE; taken --
   Voice Control input labels (the bar's words), a factual comment, and
   SwipeBack asserts directly that the swipe opens no chat. Not taken:
   press feedback (the old bar had none either); other Home Buttons
   under a swipe (out of scope, noted in the PR). SwipeBack + Home ask
   tests green.
