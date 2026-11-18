# What leaves the device for AI

Source for the privacy policy, the App Store privacy label and the in-app
"How Mira uses AI" sheet (iOS #151, App Store Review Guideline 5.1.2(i)).
Checked 2026-11-11 against miranote-ios `dev` (49a3ad4) and miranote-api
`dev` (ee9f7cb): the services' code defaults and `.env.example` files. The
running beta reads its own `.env` files on the team Mac, which were not
checked; confirm the model lines there before publishing.

Every request goes from the app to our server first (`beta-*.miranote.app`,
a Cloudflare tunnel to the team Mac, bearer token), and from there to the
provider. The app asks for consent (`AIConsent`) before any of the rows below
except photo memories, which has its own switch (iOS #172).

## Data table

| Feature (app) | Sent from the phone | Server endpoint | Third party that receives it | Model | Region |
| --- | --- | --- | --- | --- | --- |
| Mood of a saved page (star jar) | Page words and photo descriptions, up to 4000 characters | text `/mood` | DeepSeek | `deepseek-chat` (code default; env `LLM_MODEL`) | China |
| Clean / Expand / Polish / Shorten | The block's words | text `/clean`, `/expand`, `/polish`, `/shorten` | DeepSeek | same as above | China |
| Mira chat (chat screen and canvas strip) | The message, up to 8 matching pages (600 characters each), the page being edited (element list, text, colors, and a rendered image of the page) | chat `/chat` | DeepSeek (text). The page image goes to Google Vertex AI `/describe` only when Mira looks at the page; picture tools call the image rows below | `deepseek-chat` (code default) | China |
| Voice dictation (canvas, chat, text) | The recording (m4a) | voice `/transcribe` | None for the audio: Whisper runs on our Mac. The transcript goes to Alibaba Cloud (DashScope) for correction | Whisper `medium` on the Mac; correction `qwen3.5-flash` | Audio: our Mac. Text: China (Beijing) |
| Stickers, backgrounds, pictures | The prompt | image `/generate` | Alibaba Cloud (DashScope) | `qwen3.8-flash` (prompt expansion), `z-image-turbo` (image) | China (Beijing) |
| Photo / sticker AI edits (restyle, "make it ...") | The image and the instruction | image `/stylize` | Google Vertex AI | `gemini-3.1-flash-lite-image` | Vertex `global` endpoint |
| Cutout of a named object | The image and the object's name | image `/cutout?prompt=` | Google Vertex AI (finds the box); GroundingDINO and SAM run on the Mac | `gemini-3.1-flash-lite` | Vertex `global` |
| Photo description (placing a photo on a page, photos in chat) | The photo | image `/describe` | Google Vertex AI | `gemini-2.5-flash` | Vertex `global` |
| Photo memories (beta, TestFlight opt-in, iOS #172) | Up to 10 photos per moment, with time, rough place and on-device labels | collections `/collections/compose` | Alibaba Cloud (DashScope) | `qwen3.7-flash`, `qwen3.8-flash` | China (Beijing) |

Not sent (runs on the phone): plain background removal (Vision), the sticker
outline (`StickerEdge`), photo filters, the library search that picks which
pages go with a chat message. The server's `/border` outline path is not used
by the shipped build (`localOutline: true`).

Not wired to a backend: `StickerGenerationService` and `StyleTransferService`
are mocks in the live container.

Possible engine switches on the server, not the default: voice
`TRANSCRIBE_ENGINE=yanyi` sends the audio to the hosted YanYi API; image
`IMAGE_MODEL` / `STYLE_MODEL` roll back to other Gemini models; text and chat
`LLM_BASE_URL` can point at Gemini or OpenAI. Any such switch changes this
table and the in-app Details list.

## What our server keeps

- Text, mood, voice, image: nothing is written to disk. Requests are handled
  in memory; the voice and Vision paths use temporary files deleted after the
  request.
- Chat: the conversation is kept in memory for `SESSION_TTL_SECONDS`
  (default 3600 s) after its last message, so follow-ups have context. Not on
  disk; a restart drops it.
- Photo memories: a job and its result stay in memory for
  `PHOTO_JOB_TTL_SECONDS` (default 3600 s). The compose log, one JSON line per
  job holding the model's text about the photos, is kept 7 days
  (`logclean.py`).
- Service logs (`logs/beta/*.log`, never rotated): request sizes and errors;
  the image service also logs the object name of a named cutout and the
  detector's raw box answer. No page text, photo or audio is logged.
- Only the mood word is stored, on the phone, with the page.

What the providers keep is governed by their own API terms (DeepSeek,
Alibaba Cloud Model Studio, Google Vertex AI); not reviewed here.

## App behavior (iOS #151)

- The consent sheet shows right before the first action that would send any
  of the above, never at launch. Continue is stored
  (`miranote.ai.consent`); Not now cancels that action only and the next AI
  action asks again. A Save before consent asks once per launch, after the
  editor closes, because the mood is read in the background.
- A cancelled action says why: "Mira needs your OK to use AI. You can turn
  it on in Settings." Dictation asks before the mic starts; Mira turns and
  sticker making ask before their time limits start.
- Background work never shows the sheet: moods and photo descriptions are
  simply not requested without consent. The mood queue's retries (#192)
  stop too while moods are not allowed.
- Settings > AI & privacy repeats the explanation, holds "Mood from my words"
  (`miranote.ai.moodFromWords`, default on; off means no `/mood` request and
  neutral stars) and "Stop sending to AI" (withdraws; the sheet shows again),
  or "Turn on AI features" (shows the sheet) while consent is not given.
- Photo memories keep their own confirmation and switch; the AI sheet does
  not ask again for them.

## For the App Store privacy label

Data types that leave the device for the features above: User Content
(other user content: page text, chat messages), Photos or Videos, Audio Data,
and coarse Location (photo memories only). Purpose: App Functionality. Not
linked to identity (no account; a shared beta token), not used for tracking.
