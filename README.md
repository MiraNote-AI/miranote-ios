# miranote-ios

SwiftUI app for MiraNote. Design source of truth: the UI Flow v2.1
decision doc (link in any recent PR body); build history with verify
records lives in `docs/plans/`.

## Build

The Xcode project is generated, not committed:

```bash
brew install xcodegen swiftlint   # once
xcodegen generate                 # -> MiraNote.xcodeproj
open MiraNote.xcodeproj
```

## Verify (see .claude/skills/verify-repo)

```bash
# logic layer: swift build works with Command Line Tools alone;
# swift test additionally requires full Xcode (CLT ships no XCTest)
cd MiraNoteKit && swift build && swift test

# full app (requires Xcode + an iOS simulator)
xcodebuild -project MiraNote.xcodeproj -scheme MiraNote \
  -destination 'platform=iOS Simulator,name=iPhone 17' build test

# lint
swiftlint --strict
```

## Run it on the simulator

```bash
xcodegen generate
xcodebuild -project MiraNote.xcodeproj -scheme MiraNote \
  -destination 'platform=iOS Simulator,name=iPhone 17' build

# install + launch on a booted simulator (find UDID via `xcrun simctl list`)
APP=~/Library/Developer/Xcode/DerivedData/MiraNote-*/Build/Products/Debug-iphonesimulator/MiraNote.app
xcrun simctl install booted $APP
xcrun simctl launch booted ai.miranote.app
```

Or just open the project in Xcode and hit Run. Two simulator gotchas:

- With "Connect Hardware Keyboard" on, the software keyboard never
  shows -- the app's text tools now live in the bottom bar either way,
  but typing happens on your Mac keyboard.
- Old DerivedData trees can shadow fresh builds when scripting
  installs; glob for the NEWEST `MiraNote-*` if in doubt.

## Live AI features need the backend

UI tests and previews run fully mocked (`-UITEST`), but manual testing
of AI features expects the `miranote-api` POCs on localhost (see that
repo's README for setup, keys, and the image models):

| Feature | Port |
|---|---|
| Polish / expand / tighten text | 8001 |
| Mira chat, drafts, AI titles and captions | 8003 |
| AI image, cutout / make sticker, Ask-AI photo edits, photo vision | 8002 |
| Voice dictation | 8000 |

The retrieval POC (:8004, quote corpus) runs server-side but has no app
client yet -- it is on the roadmap, not in the feature set.

Backends down = calm failure cards in the app, nothing breaks.

## Layout

- `MiraNoteKit/` -- Swift package: models, services (mocked in v1), view models, tests.
- `App/Sources/` -- SwiftUI app target: screens, design system.
- `docs/specs/`, `docs/plans/` -- design specs and loop plans.
