# miranote-ios

SwiftUI app for MiraNote. Design source of truth:
`docs/specs/2026-06-10-ios-app-v1-design.md`.

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
  -destination 'platform=iOS Simulator,name=iPhone 16' build test

# lint
swiftlint --strict
```

## Layout

- `MiraNoteKit/` -- Swift package: models, services (mocked in v1), view models, tests.
- `App/Sources/` -- SwiftUI app target: screens, design system.
- `docs/specs/`, `docs/plans/` -- design specs and loop plans.
