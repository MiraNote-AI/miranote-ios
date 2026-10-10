# Redesign phase A: visual system and five-tool editor

Refs #81

Source: 2026-10-07 design handoff (38 screens), local copy at
`MiraNote/resources/design-2026-10-07/` (not in this repo).

## Goal (acceptance criteria)

Each PR is a stacked step; the loop is done when all three are open with CI
green and a fresh-context review recorded.

A1 -- foundations (`feat/design-foundations`)
1. Josefin Sans is bundled and registered; UI text roles use it.
2. Palette values match DESIGN_TOKENS.md; muted text >= 4.5:1 on light surfaces.
3. No app text below 11 pt (`grep` for `size: [0-9]\b` / `size: 10` on Text).
4. `PrimaryPill` / `SoftPill` hit-test at >= 44 pt.

A2 -- shared chrome (`feat/design-chrome`, stacked on A1)
5. Top bar: canvas shows Home / undo / Save; panels show Cancel / Done.
6. Tool bar: five icon capsules (40 pt drawn, 44 pt hit), active = selectedTool fill.
7. Composer: glass field + "Go" pill, same accessibility ids as today.

A3 -- five tools (`feat/five-tools`, stacked on A2)
8. `EditorMode` = background, voice, text, image, sticker.
9. Sticker panel holds AI generation + favorites; Image panel no longer
   generates stickers; the Saved tab is gone.
10. Background panel offers default backdrop + ask Mira.

For every PR:
- `xcodebuild` Release (generic iOS, unsigned) succeeds.
- Full app test suite (`MiraNoteTests` + `MiraNoteUITests`) passes on iPhone 17 Pro.
- `checks.no_cjk_or_emoji` exits 0.
- HUMAN: visual match against the handoff screens (screenshots in the PR).

## Stop conditions

- Success: criteria above pass + fresh-context subagent review says done.
- Cap: 5 iterations per PR.
- No progress for 2 iterations -> handoff.
- Escalate: protected path edit needed, a test would need weakening, or the
  work outgrows #81.
- Never self-merge: PRs wait for a human reviewer (run-loop terminal state).

## Iterations

1. A1 written: Josefin Sans + OFL, palette tokens, muted #68665B, 11 pt floor
   (4 sub-11 labels + 9 hardcoded system-font labels), minimumHitTarget on
   pills -- Release build OK; MiraNoteTests 9/9 + MiraNoteUITests 13/13 OK;
   CJK check exit 0; full suite: 9 unit + 41 UI tests, 0 failures (3 skipped,
   pre-existing).
2. Fresh-context review: NOT DONE -- ContextCard compact label still SF;
   minimumHitTarget's 44 pt frame grew every header ~10 pt. Fixed both: Sans
   on the compact label; hit area now padding(+5)/contentShape/padding(-5) so
   layout is untouched. Kept: InputModeBar "T" glyph (icon, replaced in A2);
   unused ActionRow is pre-existing, left alone. Release build OK; full suite
   9 unit + 41 UI, 0 failures. Re-review: DONE. A1 criteria 4/4 -> PR #82.
3. A2 written (stacked): TopBar NavPill + bare undo, icon-capsule tool bar
   from handoff SVGs (template vectors in a new Assets.xcassets), glass
   composer. DEVIATION: canvas keeps "Done" instead of the handoff "Save" --
   editing autosaves, a UI test pins "no Save", and the handoff Save opens
   export (phase C). Catalog forces APPICON_NAME "" until the icon can be
   committed. Full suite 9 + 41, 0 failures; Release OK. Review: DONE with
   nits; fixed the misleading APPICON comment, a11y-hidden leading symbol,
   stale doc comment. Skipped: Go pill disabled look (system dimming already
   visible in the simulator screenshot). A2 criteria 3/3 -> PR.
