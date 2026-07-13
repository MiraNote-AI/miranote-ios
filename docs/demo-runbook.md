# Demo-day runbook (AI competition, week of 2026-07-12)

Refs MiraNote-AI/miranote-ios#34. Verified end to end on 2026-07-12
against the integration of main + PR #29 + PR #31 (sweep evidence in
docs/plans/2026-07-12-demo-readiness-sweep.md).

## 0. Prerequisites

- Mac with Xcode + an iOS simulator runtime (demoed on iPhone 17 Pro).
- `miranote-api` cloned, each POC set up once:
  `cd poc/<name> && python3 -m venv .venv &&
  .venv/bin/pip install -r requirements.txt && cp .env.example .env`
  then fill `LLM_API_KEY` in each `.env` (our keys -- decision
  2026-07-07: demo runs on our keys).
- `miranote-ios` on main AFTER #29 and #31 merge.

## 1. Backends (start FIRST, keep a terminal visible)

```bash
cd miranote-api && bash start-all.sh
```

| Port | Service | Demo features |
|---|---|---|
| 8001 | text-clean-expand | Polish / Expand / Tighten |
| 8002 | image-generation | AI image, sticker cutout, Ask-AI edits, backgrounds |
| 8003 | chatbot | Mira chat, drafts, titles, captions |
| 8004 | retrieval | (server-side only, no app client) |
| 8005 | voice-to-text | dictation |

Sanity: `curl -s localhost:800{1,2,3,5}/health` -> all 200.
IMPORTANT: after any `git pull` on miranote-api, RESTART start-all.sh
-- a stale server on an old port reads as "the feature is dead" in the
app (this exact skew caused the 07-11 "recording unresponsive" report).

## 2. App build + install

```bash
cd miranote-ios
xcodegen generate
xcodebuild -project MiraNote.xcodeproj -scheme MiraNote \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
APP=$(ls -td ~/Library/Developer/Xcode/DerivedData/MiraNote-*/Build/Products/Debug-iphonesimulator/MiraNote.app | head -1)
xcrun simctl install booted "$APP"
xcrun simctl launch booted ai.miranote.app
```

(Glob the NEWEST DerivedData tree; stale trees shadow fresh builds.)

## 3. Simulator prep (avoids mid-demo permission popups)

```bash
xcrun simctl privacy booted grant microphone ai.miranote.app
xcrun simctl privacy booted grant photos ai.miranote.app
xcrun simctl privacy booted grant photos-add ai.miranote.app
```

- photos-add is SEPARATE from photos; without it the export beat
  stalls on an alert.
- Simulator setting "Connect Hardware Keyboard" OFF if you want the
  software keyboard on screen (typing then happens via the Mac
  keyboard either way).
- Chinese input in a live demo: paste it
  (`echo '<text>' | xcrun simctl pbcopy booted`, then long-press ->
  Paste) or enable the CJK keyboard in simulator Settings beforehand.

## 4. Reset to a clean demo state (between rehearsals)

```bash
APPDATA=$(xcrun simctl get_app_container booted ai.miranote.app data)
rm -rf "$APPDATA/Documents/"*
xcrun simctl terminate booted ai.miranote.app
xcrun simctl launch booted ai.miranote.app
```

Relaunch re-seeds the four starter collections.

## 5. A demo path that is verified to work (10 beats)

1. Home -> quick capture "note this down: ..." -> Mira drafts a page ->
   open in editor (works in Chinese too, via paste).
2. Home -> quick capture "find my note about ..." -> tap the cover ->
   read -> back returns to the conversation.
3. Canvas: Text tool, type a stub -> sparkles -> Expand -> live result
   with real bullets; Revert available on the receipt.
4. Image -> AI image -> prompt -> ~30s -> tap result to place.
5. Long-press photo -> Edit photo -> filter chip (instant) -> Ask AI
   ("make it watercolor", ~60-90s) -> Make sticker (cutout, panel
   closes itself -- expected).
6. Library (4th toolbar slot) -> tap a saved sticker/photo -> it lands.
7. Sound tool -> Record -> stop -> Keep -> marker on canvas.
   Mic in the text keyboard = dictation (:8005).
8. Prompt bar: "give this page a sunset background" -> two candidates
   -> tap one.
9. Prompt bar: "add a title" / "write a few words" / "tidy the layout".
10. Done -> Home -> open the page -> share -> Save to Photos.

## 6. Known rough edges (do not demo into these)

- Live generation latency: AI image ~30s, Ask-AI edit up to ~90s --
  narrate over the wait or pre-generate a page before going on stage.
- The retrieval POC (:8004) has no app client; do not promise
  quote-recall on stage.
- Sticker conversion closes the edit panel by design; do not look for
  a Done button afterwards.
- If a feature shows a calm failure card, the matching backend is down
  or stale -- check the start-all.sh terminal, restart, retry; the app
  recovers without a rebuild.
