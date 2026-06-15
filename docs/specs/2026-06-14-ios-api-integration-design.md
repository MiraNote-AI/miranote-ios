# MiraNote iOS <-> API Integration v1 -- Design

**Date:** 2026-06-14
**Source:** Brainstorming session with Meng. Builds on
`docs/specs/2026-06-10-ios-app-v1-design.md` and **resolves its open
question Q3** (when sheets call live POC endpoints vs mocks). Scope and
environment decisions (text + voice, simulator-only) by Meng, 2026-06-14.

## Goal

Replace the iOS app's mock services with live HTTP clients that call the
`miranote-api` POC servers, so the app does real work instead of returning
canned strings. v1 wires two features end to end:

- **Text** -- clean / expand / polish -> `text-clean-expand` POC (`:8001`).
- **Voice** -- record + transcribe -> `voice-to-text` POC (`:8000`).

Target environment is the **iOS Simulator** talking to the POCs on
`localhost` (via `start-all.sh`). AI stickers and style transfer stay on
mocks: they have no backend POC yet.

## Current state (the seam we build on)

`MiraNoteKit/Sources/MiraNoteKit/Services.swift` already defines four
service protocols and ships `Mock*` implementations. View models receive a
service through their initializer, defaulting to the mock:

```swift
public init(
    text: String = "",
    textService: TextTransformService = MockTextTransformService(),
    voiceService: VoiceTranscriptionService = MockVoiceTranscriptionService()
) { ... }
```

The protocols were written so "swapping the mocks for HTTP clients later
does not touch view models" (Services.swift comment). This design honors
that for the text path; the voice path needs one small, contained change
(see D7).

## Scope

**In scope (v1):**

- Live `TextTransformService` -> `:8001` `/clean`, `/expand`, `/polish`.
- Live `VoiceTranscriptionService` -> `:8000` `/transcribe`, including
  on-device audio recording.
- A networking foundation (URLSession-based, no third-party packages).
- Backend address configuration (localhost base URLs).
- A composition root that wires live services into the running app while
  tests and previews keep the mock defaults.
- User-visible error states when the backend is unreachable or errors.

**Out of scope (v1):**

- AI sticker and style-transfer wiring (no backend POC exists).
- Real-device networking (LAN address, ATS for non-localhost). Simulator
  only.
- Persistence, auth, accounts.
- Surfacing the backend's extra voice data (emotion, per-segment timings).
- The Home "What is in your mind?" pill routing to the chatbot POC
  (`:8003`) -- still open as Q4 in the v1 spec.
- `retrieval` POC (`:8004`) integration.

## Architecture

New code lives in `MiraNoteKit` (the app already depends on it). Plain
`Foundation` URLSession; no new Swift packages.

1. **HTTP foundation** -- a small helper that builds requests, performs
   them on URLSession, checks the status code, and decodes JSON, turning
   transport and non-2xx responses into typed errors.

2. **Backend config** -- extend `MiraNoteConfig` with base URLs:
   `text` = `http://localhost:8001`, `voice` = `http://localhost:8000`.
   Defaults target the simulator; no global mock/live runtime flag (see D6).

3. **LiveTextTransformService** -- maps the mode to an endpoint and reads
   the matching response field:

   | mode   | POST endpoint | request body            | response field |
   |--------|---------------|-------------------------|----------------|
   | clean  | `/clean`      | `{"text": ...}`         | `cleaned`      |
   | expand | `/expand`     | `{"text": ..., "context"?}` | `expanded` |
   | polish | `/polish`     | `{"text": ...}`         | `polished`     |

4. **Audio recording + LiveVoiceTranscriptionService** --
   - An `AudioRecorder` (AVFoundation) records mic input to a file
     (e.g. m4a) and returns the recorded bytes.
   - `LiveVoiceTranscriptionService` uploads those bytes as
     `multipart/form-data` to `:8000/transcribe` with query
     `correct=true`, `with_emotion=false`, `lang=zh` (default; see D8/D9),
     and returns `corrected_text ?? raw_text`.

5. **Composition root** -- a single place (built once in the App from
   `MiraNoteConfig`) that vends the live services and injects them where
   the sheets construct their view models (`TextInputViewModel`,
   `AIStickerViewModel`). Tests and SwiftUI previews construct view models
   without arguments and therefore keep the mock defaults.

6. **Error handling** -- live services throw typed errors; existing view
   model `catch` blocks already store `error.localizedDescription` in
   `lastError`, which the sheets show. No silent fallback to mock output:
   a failed call surfaces a clear message ("Couldn't reach the server" vs
   a server error), so a demo failure is visible, not disguised as success.

## Data flow

- **Text:** TextInputSheet -> `TextInputViewModel.apply(mode)` ->
  `LiveTextTransformService.transform(text, mode:)` -> POST `:8001/<mode>`
  -> editor text replaced with the result; `isProcessing` drives the
  existing spinner.
- **Voice:** mic control -> start recording -> stop -> bytes ->
  `LiveVoiceTranscriptionService.transcribe(...)` -> POST `:8000/transcribe`
  -> transcript appended to the editor text.

## The one interaction change (voice)

Real transcription needs audio, and audio needs a start and a stop. Today
`VoiceTranscriptionService.transcribe()` takes no input and is called as a
single await. v1 changes the **voice path only**:

- The mic glyph in the Text input sheet (and AI Sticker sheet) becomes a
  **record toggle**: tap to start, tap to stop. A safety cap auto-stops
  after a maximum duration (proposed 60s).
- `VoiceTranscriptionService` is extended so the implementation receives
  the recorded audio; the mock ignores the audio and returns mock text.
- The text path (`apply(mode:)`) and all other view-model behavior are
  unchanged.

On the Simulator the microphone is the Mac's microphone, so recording
works without hardware.

## Configuration and setup

- `project.yml`: add `INFOPLIST_KEY_NSMicrophoneUsageDescription`
  (required, or the app crashes on first record). Add an App Transport
  Security localhost exception only if plain-`http://localhost` is blocked
  at runtime (verify during implementation; recent iOS exempts loopback).
- Backend must be running: `cd miranote-api && ./start-all.sh` (text and
  voice POCs need their `.env` with `LLM_API_KEY` -- already present).
- First `/transcribe` call loads the Whisper model and is slow; later
  calls are fast.

## Testing and verification

- **Unit tests** (`MiraNoteKitTests`) use a stubbed `URLProtocol` so the
  live services are tested without a running server: verify request URL /
  method / body for each text mode, multipart assembly for voice, response
  field extraction, and error mapping for non-2xx and transport failures.
  Deterministic and offline -- safe for an autonomous build loop.
- **Build + test gate:** `xcodebuild -scheme MiraNote -destination
  'platform=iOS Simulator,name=iPhone 17 Pro' build` and the test action
  must pass each loop iteration.
- **Manual end-to-end (together):** `start-all.sh` up, app in the
  Simulator -- type a note and clean/expand/polish it; record voice and
  confirm a transcript. This is the one check the loop cannot fully judge
  alone.

## How we build it

writing-plans produces a step-by-step plan; an autonomous loop (run-loop +
verify-repo as the stop condition) executes it -- **text first** (smaller,
proves the whole pipeline), checkpoint with Meng, **then voice**. Work
follows the MiraNote-AI flow: file a tracking issue (create-ticket), do the
work on a feature branch, and land via PR (the spec + plan + code travel
together; PR references the issue per Rule 6). No direct commits to `main`.

## Decisions log

| #  | Decision | By | Date |
|----|----------|----|------|
| D4 | Scope = text + voice; AI sticker and style transfer stay on mocks (no backend POC) | Meng | 2026-06-14 |
| D5 | Simulator-only; localhost base URLs; real-device networking deferred | Meng | 2026-06-14 |
| D6 | (resolves Q3) App composition root injects live services; tests/previews keep mock defaults. No global runtime mock/live flag in v1 | Meng | 2026-06-14 |
| D7 | Voice mic becomes a record start/stop toggle; `VoiceTranscriptionService` extended to take recorded audio; text path and other view models unchanged | Meng | 2026-06-14 |
| D8 | Voice request uses `correct=true`, `with_emotion=false`, `lang=en` (Q7 resolved -- English demo default; `zh` still available via the service `language` param); emotion and per-segment data are not surfaced | Meng | 2026-06-14 |
| D9 | Service errors shown via existing `lastError`; no silent fallback to mock output | Meng | 2026-06-14 |

## Open questions

| #  | Question | Owner |
|----|----------|-------|
| Q3 | Resolved by D6 (live in app, mock in tests; localhost) | -- |
| Q6 | Resolved: tap-to-stop. The 60s safety cap was deferred (concurrency complexity for little demo value); revisit if needed | Meng |
| Q7 | Resolved: `en` (English) default for the demo; configurable per call | Meng |
| Q4 | Home "What is in your mind?" pill -> chatbot POC (`:8003`)? Still open, out of v1 scope | Jason |

## Non-goals for v1

- Real-device networking and non-localhost ATS.
- Persistence, auth, accounts.
- Sticker / style-transfer backend.
- Emotion / per-segment transcription UI.
- Chatbot (`:8003`) and retrieval (`:8004`) integration.
