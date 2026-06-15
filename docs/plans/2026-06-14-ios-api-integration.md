# Plan: MiraNote iOS <-> API integration v1 (text + voice)

**REQUIRED SUB-SKILL:** run-loop (loop contract) + verify-repo (verification)
**Refs:** #9 | spec: docs/specs/2026-06-14-ios-api-integration-design.md

Replaces the iOS mock services with live HTTP clients calling the
`miranote-api` POCs: text (clean/expand/polish -> `:8001`) and voice
(record + transcribe -> `:8000`). Simulator + localhost only. Sticker and
style-transfer stay on mocks (no backend POC). Builds on the seam in
`MiraNoteKit/Sources/MiraNoteKit/Services.swift`.

## Loop contract

**Goal -- acceptance criteria:**

- [ ] AC1: `MiraNoteKit` gains a URLSession-based HTTP helper and typed
      errors. No new SwiftPM dependencies (Package.swift unchanged except
      possibly a new test resource). `swift build` / app build clean.
- [ ] AC2: `LiveTextTransformService: TextTransformService` POSTs to
      `<textBaseURL>/clean|/expand|/polish` with body `{"text": ...}` and
      returns the matching response field (`cleaned`/`expanded`/`polished`).
      Unit tests with a stubbed `URLProtocol` assert request URL+method+body
      and response parsing for all three modes, plus error mapping for a
      non-2xx status and a transport failure. Tests pass.
- [ ] AC3: Voice path implemented:
      - `AudioRecording` protocol + `AudioRecorder` (AVFoundation) records
        mic to an m4a temp file and returns the bytes; a `MockAudioRecorder`
        returns canned bytes for tests.
      - `LiveVoiceTranscriptionService` uploads bytes as
        `multipart/form-data` to `<voiceBaseURL>/transcribe?correct=true&with_emotion=false&lang=zh`
        and returns `corrected_text ?? raw_text`.
      - Unit tests assert multipart assembly (boundary, filename, field
        name `file`), query string, response parsing, and error mapping.
- [ ] AC4: D7 interaction change applied to the voice path only:
      `VoiceTranscriptionService` becomes
      `func transcribe(audio: Data, filename: String) async throws -> String`;
      `MockVoiceTranscriptionService` updated; `TextInputViewModel` and
      `AIStickerViewModel` gain `isRecording` + `toggleDictation()` (start
      recording -> stop -> transcribe -> append) with a 60s safety auto-stop;
      their sheets' mic buttons reflect `isRecording`. `apply(mode:)` and all
      other view-model behavior unchanged. Existing dictate tests rewritten
      to the new API stay green.
- [ ] AC5: `MiraNoteConfig.Backend` exposes `textBaseURL`
      (`http://localhost:8001`) and `voiceBaseURL` (`http://localhost:8000`).
      A composition root vends live services; `TextInputSheet` and
      `AIStickerSheet` build their view models from it. Tests and previews
      use the mock defaults (no global runtime flag -- D6).
- [ ] AC6: `project.yml` adds `INFOPLIST_KEY_NSMicrophoneUsageDescription`;
      an ATS localhost exception is added only if a runtime check shows plain
      `http://localhost` is blocked. `xcodegen generate` succeeds; app builds.
- [ ] AC7: `xcodebuild build` and `xcodebuild test` are green on the
      `iPhone 17 Pro` simulator; SwiftLint clean on changed files; governance
      checks green (verify-repo from a clean `origin/main` checkout of
      `MiraNote-AI/.github`).
- [ ] HUMAN AC8: End-to-end on the simulator with `start-all.sh` up -- typing
      then clean/expand/polish returns real AI output; recording voice yields
      a transcript. Meng + Claude together.
- [ ] HUMAN AC9: Q6 (voice tap-to-stop + 60s cap) and Q7 (voice language
      default) confirmed by Meng before the demo.

**Stop conditions:** iteration cap 6; 2 consecutive no-progress iterations
-> handoff; escalate (do not proceed) if the work would need protected-path
edits, weakened checks, scope beyond the tracking issue, or a real-device /
non-localhost networking change.

**Budget:** interactive session loop (not scheduled).

**Checkpoints:** after T4 (text works end-to-end) pause for Meng to try the
text demo before starting voice (T5+). Final E2E (AC8) is done with Meng.

## File structure

- Create `MiraNoteKit/Sources/MiraNoteKit/Networking/HTTPClient.swift`
  -- request building, URLSession call, status check, JSON decode, typed
  `BackendError` (`.unreachable`, `.server(status:detail:)`, `.decoding`).
- Create `MiraNoteKit/Sources/MiraNoteKit/Networking/LiveTextTransformService.swift`.
- Create `MiraNoteKit/Sources/MiraNoteKit/Networking/AudioRecorder.swift`
  -- `AudioRecording` protocol, `AudioRecorder`, `MockAudioRecorder`.
- Create `MiraNoteKit/Sources/MiraNoteKit/Networking/LiveVoiceTranscriptionService.swift`
  -- including the `multipart/form-data` body builder.
- Create `MiraNoteKit/Sources/MiraNoteKit/ServiceContainer.swift`
  -- composition root that builds live services from `MiraNoteConfig`.
- Modify `MiraNoteKit/Sources/MiraNoteKit/MiraNoteConfig.swift` -- add
  `Backend` base URLs.
- Modify `MiraNoteKit/Sources/MiraNoteKit/Services.swift` -- change the
  `VoiceTranscriptionService` protocol + `MockVoiceTranscriptionService`.
- Modify `MiraNoteKit/Sources/MiraNoteKit/ViewModels/TextInputViewModel.swift`
  and `.../AIStickerViewModel.swift` -- recorder dependency + toggle API.
- Modify `App/Sources/Screens/Sheets/TextInputSheet.swift` and
  `.../AIStickerSheet.swift` -- inject live services, mic toggle UI.
- Modify `project.yml` -- mic usage string (+ ATS if needed).
- Create tests under `MiraNoteKit/Tests/MiraNoteKitTests/` -- one file per
  live service + a shared `StubURLProtocol`.

## Tasks (text first, then voice)

- [x] T0: File the tracking issue (create-ticket). Create feature branch
      `feat/ios-api-integration` off `main`. Commit the spec and this plan.
- [x] T1: HTTP foundation. `HTTPClient` + `BackendError`. Test target gets a
      reusable `StubURLProtocol` (registers a per-test handler returning a
      canned `(HTTPURLResponse, Data)` or throwing). Tests: a 200 decodes a
      sample struct; a 500 maps to `.server`; a thrown transport error maps
      to `.unreachable`. TDD: write tests, see them fail, implement, green,
      commit.
- [x] T2: Backend config. Add `MiraNoteConfig.Backend.textBaseURL` /
      `voiceBaseURL`. Test: the two URLs are the expected localhost:port
      values. Commit.
- [x] T3: `LiveTextTransformService`. Endpoint+field map:

      | mode   | POST path | response field |
      |--------|-----------|----------------|
      | clean  | /clean    | cleaned        |
      | expand | /expand   | expanded       |
      | polish | /polish   | polished       |

      Body `{"text": <input>}`. Tests (StubURLProtocol): each mode hits the
      right path with the right body and returns the field; a 502 surfaces
      `BackendError.server`. TDD + commit.
- [x] T4: Wire live text into the app. Add `ServiceContainer` (vends
      `LiveTextTransformService(baseURL: MiraNoteConfig.Backend.textBaseURL)`).
      `TextInputSheet` builds `TextInputViewModel(textService:voiceService:)`
      from the container (voice stays mock for now). Build + launch on the
      simulator. **CHECKPOINT: Meng tries clean/expand/polish against
      `start-all.sh`.** Commit.
- [x] T5: D7 protocol + view-model change. Change
      `VoiceTranscriptionService.transcribe(audio:filename:)`; update
      `MockVoiceTranscriptionService` (ignores audio, returns mock text).
      Add `AudioRecording` protocol + `MockAudioRecorder`. Give
      `TextInputViewModel` and `AIStickerViewModel` an injected
      `AudioRecording` (default real) and replace `dictate()` with
      `isRecording` + `toggleDictation()` (start; on second call stop, read
      bytes, `transcribe`, append; auto-stop after 60s). Rewrite the two
      dictate unit tests to drive the toggle with a `MockAudioRecorder` +
      mock voice service. TDD + commit.
- [x] T6: `AudioRecorder` (AVFoundation). `start()` configures an
      `AVAudioSession` (record), writes m4a to a temp URL; `stop()` finalizes
      and returns the file bytes; `isRecording` tracks state. No unit test
      for the live mic (covered by AC8 manual). Build clean. Commit.
- [x] T7: `LiveVoiceTranscriptionService`. Build the `multipart/form-data`
      body (field name `file`, given filename, `audio/m4a`); POST to
      `voiceBaseURL/transcribe` with query `correct=true&with_emotion=false&lang=zh`;
      decode and return `corrected_text ?? raw_text`. Tests (StubURLProtocol):
      multipart boundary+filename+field present, query string correct,
      response parsing, 422 maps to `BackendError.server`. TDD + commit.
- [x] T8: Mic permission + wire live voice. Add
      `INFOPLIST_KEY_NSMicrophoneUsageDescription` to `project.yml`; run a
      localhost runtime check and add an ATS exception only if needed.
      `ServiceContainer` now also vends `LiveVoiceTranscriptionService`;
      `TextInputSheet` + `AIStickerSheet` get it and show the recording
      state on the mic button. `xcodegen generate`, build + launch. Commit.
- [ ] T9: Integration + verify pass. Full `xcodebuild build` + `test` green
      on iPhone 17 Pro; SwiftLint clean; verify-repo governance green.
      **Final E2E (AC8) with Meng:** `start-all.sh` up, text + voice
      exercised in the simulator. Open PR referencing the T0 issue
      (create-pr). Commit / push per the no-stale-approval batching rule.

## Iterations

```
0. 2026-06-14 contract written; awaiting go to start T0 -- criteria 0/9
1. 2026-06-14 T0: issue #9 filed; branch feat/ios-api-integration cut;
   spec+plan committed (docs-only, verify-repo gates) -- criteria 0/9
2. 2026-06-14 T1-T4 text path: HTTPClient+BackendError, config base URLs,
   LiveTextTransformService, ServiceContainer wired into app. swift test
   30/30 green; app BUILD SUCCEEDED on iPhone 17 Pro. AC1+AC2 pass, AC5
   text-half done (voice half pending T8) -- criteria 2/9; text checkpoint next
3. 2026-06-14 ATS + mic (pulled forward from T8): app target switched to an
   explicit Info.plist with NSAllowsLocalNetworking + localhost exception
   (else iOS blocks http://localhost) and NSMicrophoneUsageDescription;
   AC6 partially met. App rebuilt + relaunched on sim, Home renders; backend
   :8001 verified via curl (/clean returns real AI). -- criteria 2/9; paused
   at text checkpoint with Meng
4. 2026-06-14 voice path T5-T8: AudioRecording + AudioRecorder, voice protocol
   takes recorded audio, tap-to-stop dictation in both sheets,
   LiveVoiceTranscriptionService (multipart, lang=en). Q6 resolved (tap-to-stop,
   60s cap deferred), Q7 resolved (en). swift test 35/35; app BUILD SUCCEEDED.
   -- criteria: AC3+AC4 pass, AC5 full, AC6 met; T9 verify next
```

## Deviations

- ATS + mic permission (part of T8) pulled forward into the text phase: the
  text demo cannot work without the localhost ATS exception, so it was added
  before the T4 checkpoint rather than during T8. Switched the app target from
  a generated Info.plist to an explicit XcodeGen `info:` plist (gitignored,
  like the project) to carry the nested NSAppTransportSecurity dict.
- Q6 (60s auto-stop cap) deferred: tap-to-stop only for v1. The timer added
  concurrency complexity for little demo value; revisit if a forgotten
  recording becomes a real problem.
- Voice language default is `en` (Q7), set via the service `language` param;
  `zh` remains available.
