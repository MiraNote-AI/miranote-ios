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
| Clean up / Expand chips, shorten via Mira | 8001 |
| Mira chat, drafts, AI titles and captions | 8003 |
| AI image, cutout / make sticker, Ask-AI photo edits, photo vision | 8002 |
| Voice dictation | 8005 |

The retrieval POC (:8004, quote corpus) runs server-side but has no app
client yet -- it is on the roadmap, not in the feature set.

Backends down = calm failure cards in the app, nothing breaks.

## Using the app (60-second tour)

1. Home -> **Start a memory**: a blank canvas page opens.
2. The bottom bar has four modes: **Sound** (record, auto-transcribed),
   **Text** (type in place; while editing, AI chips offer **Clean up**
   and **Expand**), **Image** (photo library / camera / **AI image**
   with Photo, Illustration, Watercolor, and Sticker styles), and
   **Saved** (your favorites shelf -- tap to place on the page).
3. **Long-press any element** for its menu: Edit, Favorite (saves it to
   the Saved shelf), Duplicate, layer order, Delete.
4. The **Ask Mira** bar drives everything in words: "clean up the
   text", "make it shorter", "make it a sticker", "tidy the layout",
   or just chat -- when Mira suggests words in quotes, a one-tap chip
   places exactly those words on the page.
5. **Done** files the page into your journal on Home.

## Layout

- `MiraNoteKit/` -- Swift package: models, services (mocked in v1), view models, tests.
- `App/Sources/` -- SwiftUI app target: screens, design system.
- `docs/specs/`, `docs/plans/` -- design specs and loop plans.
