# Run MiraNote on your iPhone

Two ways in, depending on who you are:

- **Testers** install from TestFlight. Nothing to build, no Wi-Fi
  requirement, no weekly ritual.
- **Developers** build to their own device from Xcode, which still needs
  the free-signing dance below.

Either way the app talks to the same backends, over public HTTPS through
a Cloudflare tunnel. The Wi-Fi-and-Bonjour path this file used to
describe is gone: the backends now bind loopback and the tunnel is the
only way in.

## How it fits together

- Every service URL comes from one place,
  `MiraNoteKit/Sources/MiraNoteKit/MiraNoteConfig.swift` (`Backend`).
  Device builds use the four tunnel hosts; simulator and macOS test
  hosts use `localhost`.

  | Service | Device | Simulator |
  | --- | --- | --- |
  | text | `https://beta-text.miranote.app` | `http://localhost:8001` |
  | image | `https://beta-image.miranote.app` | `http://localhost:8002` |
  | chat | `https://beta-chat.miranote.app` | `http://localhost:8003` |
  | voice | `https://beta-voice.miranote.app` | `http://localhost:8005` |

- **Every request needs a bearer token**, `/health` excepted. It is
  compiled into the build from an untracked file (next section), and a
  build without one reaches the server and is refused.
- The backends run on one Mac, bound to `127.0.0.1`, started by
  `miranote-api/scripts/start_backends.sh`. **Do not change that bind.**
  It is the whole security posture: the tunnel reaches them over
  loopback, and `0.0.0.0` would expose four services that spend API
  credits to every network the Mac ever joins.
- The tunnel is a launchd job on that Mac, so it comes back after a
  reboot on its own. `miranote-api/scripts/start_tunnel.sh` is the
  manual path.

## Build setup: the token (one time, required)

Without this your build compiles, installs, and then fails every AI
request. The build warns you, but only if you read it.

```bash
cd miranote-ios
cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig
# then fill in BETA_API_TOKEN
```

`Config/Secrets.xcconfig` is gitignored and must stay that way. Ask
whoever runs the backends for the current token and take it out of band
-- not in a PR, an issue, or a chat channel.

Signing for TestFlight? Set `DEVELOPMENT_TEAM` in that same file to the
shared account's Team ID. Do not put it in `project.yml`: that file is
tracked, and `xcodegen generate` would reset your team on every run.
For an ordinary on-device debug build, leave it out -- the default free
personal team is already in `Config/App.xcconfig`.

If `xcodebuild` prints `warning: BETA_API_TOKEN is empty`, stop. That
build cannot talk to the backends.

## One-time phone setup for a developer build (~10 min)

0. Fresh clone? Generate the Xcode project first (it is gitignored):
   `brew install xcodegen` once, then `xcodegen generate`.
1. Plug your iPhone into your Mac. Trust the computer when asked.
   No prompt? Unlock the phone FIRST, then replug.
2. iPhone: Settings > Privacy & Security > Developer Mode > on
   (reboots the phone).
3. Xcode: open `MiraNote.xcodeproj`, Settings > Accounts > add your
   (free) Apple ID.
4. Target `MiraNote` > Signing & Capabilities: check "Automatically
   manage signing", pick your Personal Team. If the bundle id
   collides, append your name (e.g. `ai.miranote.app.meng`).
5. Product > Scheme > Edit Scheme > Run > Build Configuration:
   **Release**. Debug is noticeably less smooth.
6. Select your phone, press Run. First launch: iPhone Settings >
   General > VPN & Device Management > trust your developer
   certificate, then launch again.

The app no longer asks for Local Network permission. It does not use
the local network.

### Every week

Free signing expires after 7 days and the icon stops opening. Plug in,
press Run once. TestFlight builds do not have this problem; they expire
after 90 days instead.

## What the error messages mean

Each one names a different failure and a different fix. They are worth
reading literally rather than reporting as "the app is broken".

| On screen | What happened | Who fixes it |
| --- | --- | --- |
| "cannot get into the beta -- its access was never set up, or has since been replaced" | 401. The build has no token, or an old one | whoever built it: set `BETA_API_TOKEN`, rebuild, redistribute |
| "AI server is not running" | 502. Tunnel up, backends down | run `start_backends.sh` on the host Mac |
| "link to MiraNote's AI server is down" | 530. The tunnel is down, or its Mac is asleep or offline | check the host Mac; the launchd job restarts the tunnel itself |
| "sending requests faster than the beta allows" | 429. Our own per-token rate limit | wait about a minute |
| "image service has used up its quota" | 503. The upstream image provider refused us | nothing on the phone; the backend team has to raise quota |
| "took longer than the server allows" | Client timeout | try once more, then report it |
| "Couldn't reach MiraNote's AI server" | No answer at all | check your connection first, then whether the tunnel is up |

## Using it

- Text and chat answer in ~1-2s. Image generation takes ~15-40s on an
  idle host, and so does a cutout where you typed what to keep -- that
  one needs the big models on the Mac. The working bar means it IS
  working; do not retry-spam. There is deliberately no automatic retry,
  and concurrent generations are capped, so extra taps only queue.
- Turning a photo into a sticker without naming a subject is now
  near-instant: it runs on the phone (Apple Vision), never leaves the
  device, and works with the backend down.
- A generated sticker whose background could not be removed comes back
  with the background still on and says so, rather than failing. The
  picture is already paid for, so it is offered either way.
- The host Mac's spare CPU is the product's speed. Before a demo, quit
  video-meeting apps and stray dev servers -- a forgotten `--reload`
  uvicorn once tripled cutout times.
- Off the network the app still opens and existing pages stay readable
  and editable; most AI features fail. Turning a photo into a sticker
  is the exception -- see above.

## Zoom demo (mirror the real phone)

1. Phone plugged into the Mac via USB.
2. QuickTime Player > File > New Movie Recording > click the arrow next
   to the record button > Camera: your iPhone.
3. A live, lossless portrait mirror appears. Share THAT window.

The mirror is as smooth as the phone and does not depend on the network
or the backend. Plan narration around the slow features, or show those
from the pre-rendered film (`miranote-demo/final.mp4`) and do the fast
ones live.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| Every AI feature says the build cannot get into the beta | The build has no token. `Config/Secrets.xcconfig`, then rebuild. This is the most common first-build failure. |
| `xcodegen generate` fails on a config file path | You are on an old checkout. `Config/App.xcconfig` is tracked and uses an optional include, so a missing secrets file is fine. |
| Your signing team keeps reverting | You set it in `project.yml`. Put it in `Config/Secrets.xcconfig` instead. |
| Health check from a phone browser | `https://beta-text.miranote.app/health` needs no token and should return JSON. If that fails, the tunnel or the backend is down, not your build. |
| App icon won't open after a while | Free signature expired. Plug in, Run once. |
| First image op after a restart is slow | Cold model load on the host. The second call is fast. |
