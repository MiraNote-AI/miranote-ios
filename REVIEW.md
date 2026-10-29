# REVIEW.md -- guidance for reviewers of miranote-ios (human or AI)

Read by the run-loop fresh-context check and pre-merge review, and by
anyone reviewing a pull request here. The rules live in `CONTRIBUTING.md`
and the verify-repo skill; this file says what failure looks like in this
app and where to look hardest.

## What failure looks like here

Most damaging first.

1. **A user's page lost or unreadable.** A change to a saved model, a
   store or its file layout that breaks the Save round-trip, or stops
   older saved data from decoding.
2. **UI behaviour claimed without a UI test.** A claim about what the user
   sees or taps that only unit tests back. The v1 merge blockers were
   invisible to every unit test; UI claims need `App/UITests`.
3. **UI state touched off the main actor.** View-model or view state
   changed from a background task, or a main-actor-only value read off it.
4. **A regression test that proves nothing.** A new view-layer regression
   test without mutation evidence that it fails when the bug comes back.
5. **A client out of step with the api.** Request or decoding code that
   assumes a field, status or error shape miranote-api does not send.
6. **Text the user cannot read.** A user-facing string that bypasses the
   String Catalogs (`App/Resources/*.xcstrings`), or CJK anywhere outside
   them (Rule 3).

## Sensitive paths (review at `high` + `/security-review`)

- `MiraNoteKit/Sources/MiraNoteKit/Models.swift`,
  `MiraNoteKit/Sources/MiraNoteKit/*Store.swift`,
  `MiraNoteKit/Sources/MiraNoteKit/AppSettings.swift`,
  `MiraNoteKit/Sources/MiraNoteKit/LocalProfile.swift` -- what is saved on
  the device
- `MiraNoteKit/Sources/MiraNoteKit/Networking/` -- every call to the api
- `Config/`, `MiraNoteKit/Sources/MiraNoteKit/MiraNoteConfig.swift`,
  `project.yml`, `.github/workflows/` -- build settings, secrets wiring, CI

## Skip

- `App/Resources/Assets.xcassets/`, `App/Resources/Fonts/`
- The generated `MiraNote.xcodeproj` (gitignored; `xcodegen generate`
  rebuilds it)

## How to report

- Every finding cites file:line evidence; never a guess from a name.
- Tag each finding IMPORTANT (breaks or misleads), NIT (preference) or
  PRE-EXISTING (not introduced by this diff). At most 3 NITs.
- Formatting is swiftlint's job: do not report it.
- Start the summary with the count; say plainly when there is nothing to
  fix.
