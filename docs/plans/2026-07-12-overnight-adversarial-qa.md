# Overnight adversarial QA -- plan & ledger

REQUIRED SUB-SKILL: run-loop
Refs MiraNote-AI/miranote-ios#36
Probing branch: `integration/demo-sweep` (local worktree
`miranote-ios-wt-demo`, main + #29 + #31). Fixes (if any) go on
`fix/overnight-qa` off main as ONE PR.
Night of 2026-07-12, started 02:49 CDT.

## Goal

Five persona rounds (issue #36) against the live demo build; every
finding FIXED (locking test) / FLAGGED (repro + owner) / BY-DESIGN.

## Stop conditions

- Iteration cap: 5 per finding; no-progress after 2 -> FLAG and move on.
- Budget: fixes FREEZE at 07:00 CDT; 07:00-08:00 clean suites +
  fresh-context review (if code changed) + morning report; Discord
  post by 08:30. Jason is asleep: anything needing his authorization
  is FLAGGED, never worked around.
- Escalation triggers per run-loop (protected paths, check weakening,
  scope growth) -> morning report.

## Environment

- Backends 8001-8005 live at start. P3 kills and revives them one at a
  time (local uvicorn processes only; nothing outside this machine).
- Shadow sim iPhone 17 (0DB498B2) for all probes; user sim untouched
  tonight (it carries Jason's rehearsal install).
- Probes throwaway, deleted before any commit; film under
  /tmp/filmstrip-qa-*.

## Iterations

1. P1 impatient tapper: send-spam during a chat turn -> one user bubble,
   reply lands; toolbar mash during a live title turn -> turn completed,
   each tap did its normal job (the "two Done buttons" the probe saw =
   scaffold Done + keyboard accessory Done, normal editing state);
   backgrounding mid-generation -> settles on return. All OK.
2. P2 maximalist: 970-char paste lands complete and files complete
   (first probe run failed on its own long-press gesture; isolation
   rerun + on-disk verification confirmed END-MARKER filed); 20 blocks
   + tidy instant; blank canvas unaffected. All OK.
   FINDING F-QA1 (from inspecting the filed pages): a page titled
   "Thanks for watching!" -- the classic Whisper SILENCE HALLUCINATION
   from probe C's quiet dictation, saved as if the user said it.
   FIXED backend-side: miranote-api#33 -> PR api#34 (drop segments
   with no_speech_prob > 0.6 and avg_logprob < -1.0; 3 locking tests
   with mutation evidence; 14/14 voice tests green).
3. P3 unlucky one: :8001 and :8003 killed -> Expand and title asks both
   produce calm failure notices, the user's words untouched; revived ->
   same actions succeed with no app relaunch. All OK.
4. P4 undo abuser: live expand -> Revert restores the exact original;
   10x undo spam past the stack bottom -> no crash, editor usable;
   ask-revert-ask race fine; an edit mid-receipt dismisses Revert (by
   design, honest). All OK.
5. P5 minimalist: whitespace-only capture does not open the chat;
   untouched blank page files nothing; empty-canvas expand clarifies.
   FINDING F-QA2: after a clarify/failure the prompt REFILLS the input
   (by design); typing the next ask without clearing concatenates the
   two prompts and re-triggers the first cue ("expand the texttidy the
   layout" classifies as expand -> clarify loop). With the refill
   cleared, the next ask works. BY-DESIGN + UX FLAG for Gloria/Meng:
   select-all the refilled text so the next keystroke replaces it.

## Morning report

- 5/5 personas toured; ONE real defect found and FIXED on the backend
  (api#34, silence hallucinations); ONE UX observation flagged
  (refill should arrive selected); everything else held up -- including
  the failure taxonomy under killed backends, which is demo-day gold.
- No iOS code changes were needed; no fix branch on miranote-ios.
- Backends all healthy at close; shadow sim carries QA debris pages
  (harmless; reset per the runbook before rehearsal).
- PR queue for the morning: ios#29, ios#31, ios#35 (docs), api#34,
  plus proposal ios#33 awaiting a direction pick (issue #32).
