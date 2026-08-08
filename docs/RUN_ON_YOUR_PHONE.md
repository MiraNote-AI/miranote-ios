# Run MiraNote on your iPhone (team beta)

Free-account sideload: the app runs on your own phone, talking to the
shared backend on Jason's Mac over Wi-Fi. Nothing is uploaded anywhere;
no paid Apple account needed.

## How it fits together

- The app's backend URLs live in ONE place:
  `MiraNoteKit/Sources/MiraNoteKit/MiraNoteConfig.swift` (`Backend`).
  Simulator builds use localhost; a real device uses
  `Jasons-MacBook-Pro-2.local` (the Mac's Bonjour name -- note the `-2`;
  check yours with `scutil --get LocalHostName` if the host Mac changes).
  Switching to a cloud deployment later = edit that one enum.
- The backend Mac runs all four POC servers bound to `0.0.0.0` via
  `miranote-api/scripts/start_backends.sh` (stop:
  `stop_backends.sh`). The script also keeps the Mac awake.

## One-time phone setup (per person, ~10 min)

0. Fresh clone? Generate the Xcode project first (it is gitignored):
   `brew install xcodegen` once, then `cd miranote-ios && xcodegen generate`.
1. Plug your iPhone into your Mac. Trust the computer when asked.
   No "Trust this computer" prompt? Unlock the phone FIRST, then
   replug. Xcode says "unpaired"? Same fix.
2. iPhone: Settings > Privacy & Security > Developer Mode > on
   (reboots the phone).
3. Xcode: open `miranote-ios/MiraNote.xcodeproj`, Settings > Accounts >
   add your (free) Apple ID.
4. Target `MiraNote` > Signing & Capabilities: check "Automatically
   manage signing", pick your Personal Team. If the bundle id
   collides, append your name (e.g. `ai.miranote.app.meng`).
5. Product > Scheme > Edit Scheme > Run > Build Configuration:
   **Release** (this is what makes it feel like a real app; Debug is
   noticeably less smooth).
6. Select your phone as the destination, press Run. First launch:
   iPhone Settings > General > VPN & Device Management > trust your
   developer certificate, then launch again.
7. On first backend call iOS asks for Local Network permission --
   tap Allow.

After this, unplug. The app lives on your home screen like any other.

## Every week

Free signing expires after 7 days -- the app icon stops opening.
Plug in, press Run once, done. (A paid $99/yr account extends this
to a year; revisit if the weekly tap gets old.)

## Using it

- Be on the SAME Wi-Fi as the backend Mac.
- Jason (or whoever hosts): `cd miranote-api && scripts/start_backends.sh`.
  Cold start takes a few minutes (image server preloads ML models);
  the script prints per-service health when ready.
- Off that Wi-Fi the app still opens and existing pages remain
  readable/editable; AI features show "can't reach the server".
- Text and chat answer in ~1-2 s. Sticker cutout and image generation
  take ~15-30 s on an idle host -- the working bar ("Cutting the
  sticker...") means it IS working; don't retry-spam, requests queue.
- The host Mac's spare CPU is the product's speed: before a demo,
  quit video-meeting apps and stray dev servers (a forgotten
  `--reload` uvicorn once tripled our cutout times).

## Zoom demo (mirror the real phone)

1. Phone plugged into the Mac via USB.
2. QuickTime Player > File > New Movie Recording > click the arrow
   next to the record button > Camera: your iPhone.
3. A live, lossless portrait mirror of the phone appears. Share THAT
   window in Zoom.
4. The mirror is exactly as smooth as the phone itself and does not
   depend on the network or the backend.

Tip for live demos: text/chat features answer in about a second;
image generation and cutout legitimately take 30-60 s. Plan the
narration around it or show those from the pre-rendered demo film
(`miranote-demo/final.mp4`) and do the fast features live.

## Troubleshooting

| Symptom | Fix |
|---|---|
| "Couldn't reach the server" on phone | Same Wi-Fi? Backends up? Open `http://Jasons-MacBook-Pro-2.local:8001/health` in phone Safari -- if that loads, restart the app. |
| Safari can't load the health URL either | The Wi-Fi may block mDNS (common on guest networks). Fallback: hotspot from a phone, connect the Mac to it; or temporarily set `Backend.host` to the Mac's LAN IP and rebuild. |
| Health loads on the Mac but not the phone | Servers must be bound to 0.0.0.0 -- always start them via `start_backends.sh`, not by hand. Also check macOS firewall (System Settings > Network > Firewall): allow incoming for Python. |
| App icon won't open after a while | The 7-day signature expired. Plug in, Run once. |
| Image ops time out | Cold model load on first call can exceed the app's timeout. The script prewarms health but not models; retry once, the second call is fast. |
