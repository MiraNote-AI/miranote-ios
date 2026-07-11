# Image-text intents -- design

Approved by Meng on 2026-07-11 (both directions, in the PR-B design
proposal; the on-device repro "Add a text to describe the picture"
sharpened the image-to-text half). Refs issue #26. Pairs with
miranote-api#31 (the art command, merged).

## Goal

1. **Words about a picture land as words.** "Add a text to describe
   the picture" / "describe the photo" / "描述一下照片" route to the
   existing addCaption ability (a warm sentence about the page and its
   photo, placed on the canvas) -- never to a photo restyle.
2. **Pictures from words use the page's words.** "Turn this text into
   a picture" / "把这段文字画成图" generate two candidates whose
   prompt IS the targeted text block's content, landing exactly like
   any generated picture.
3. **Object generation stops masquerading as background.** Mira's
   non-sticker generation switches from the background command to the
   api's new art command, so "draw a paper crane" yields a crane
   illustration, not crane wallpaper.
4. **Zero-photo photo asks stop lying.** The clarify copy for a
   photo-flavored ask with no photo on the page becomes "No photo on
   this page yet -- add one first?" (today it says "More than one
   photo here").

## Non-goals

- No OCR ("type out the words inside the photo") -- the describe
  pipeline yields a sentence about the photo, not its glyphs.
- No LLM routing (standing deferral).
- Backend untouched in this PR (the art command shipped in api#32).

## Intent grammar

- **Words-wanting guard (fix 1)**: `wantsWords` cues -- "describe",
  "add a text", "add text", "caption", "write about", "in words",
  "描述", "写一段", "配文", "写几句". When present, the photo family's
  free edit DECLINES (filters/frames/conversion still run: "describe"
  never co-occurs with them in practice, and they are checked first),
  so classify falls through to the caption branch. captionCues gain
  "describe", "add a text", "写几句", "描述" so the fall-through
  lands on addCaption.
- **illustrateText(prompt) (fix 2)** -- cues: a text mention ("this
  text", "the text", "my text", "这段文字", "这段话", "文字") AND an
  into-picture phrase ("into a picture", "into an image", "as a
  picture", "画成", "变成图"). Checked BEFORE generation (the 画 in
  "画成图" would otherwise be claimed) and before the photo family
  (the word "picture" would otherwise read as a photo mention).
  Target: the selected text block, else the longest (the existing
  targetTextBlock); prompt = "An illustration of: " + the block's
  words. No text on the page -> the existing clarifyNoText. Performs
  through the art kind, lands as a normal picture (placement
  .picture, two candidates, tap to place).
- **Art kind (fix 3)**: `GeneratedImageKind` gains `.art` (rawValue
  "art" -- the api command name). generateImage's non-sticker path and
  illustrateText use `.art`; the background family keeps
  `.background`. Sticker unchanged.
- **clarifyPhoto grows a question (fix 4)**:
  `clarifyPhoto(question: String)`. Zero photos: "No photo on this
  page yet -- add one first?". Several unselected: the existing
  "More than one photo here -- tap the one you mean and ask again."

## Component changes

- `MiraNoteKit/ImageStudio.swift`: the `.art` case.
- `MiraNoteKit/ViewModels/MiraIntent.swift`: captionCues additions;
  clarifyPhoto payload; illustrateText case + verb ("Painting...")
  + perform delegation.
- `MiraNoteKit/ViewModels/MiraIntent+Image.swift`: wantsWords guard in
  photoIntent's freeEdit; illustrateTextIntent checked from
  classifyImageOrStyle before generativeIntent; clarifyPhoto call
  sites carry questions; performSlowImage handles illustrateText via
  generateChoices(.art) and throws clarifyPhoto's carried question.
- No coordinator/UI changes: everything reuses the placement pipeline.

## Error handling

- illustrateText with no text: clarifyNoText (existing card).
- Everything else inherits the turn machinery (Stop, timeout, calm
  failure).

## Testing

- Kit classification: Meng's exact phrase "Add a text to describe the
  picture" (photo on canvas) -> addCaption; "describe the photo" ->
  addCaption; "turn this text into a picture" -> illustrateText with
  the block's words in the prompt; Chinese variants of both; "draw a
  paper crane" still generateImage; filter/frame/conversion asks
  unaffected; zero-photo filter ask -> clarifyPhoto with the no-photo
  question; ambiguous keeps the old question.
- Kit perform: a recording studio stub asserts generateImage
  (non-sticker) and illustrateText request kind .art and sticker
  requests .sticker; illustrateText outcome is imageChoices placement
  .picture.
- UITests (mock studio): sample photo + "Add a text to describe the
  picture" -> receipt "Added a few words." and a text element appears;
  a typed text block + "turn this text into a picture" -> two choices
  -> tap -> element.image lands.
- Gates: swiftlint --strict 0, full Kit + app suites on the shadow
  simulator, live film-strip against :8002 (crane illustration via
  Mira; text-to-picture from a real sentence) before install.
