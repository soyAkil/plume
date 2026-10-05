# Plume

Voice dictation and meeting transcription for the Mac. Free, open source, and entirely on your machine.

![A MacBook with Plume in the notch, the words appearing in a note as they are dictated](docs/assets/dictee.png)

**[Download for macOS →](https://github.com/soyAkil/plume/releases/latest/download/Plume.dmg)** · Apple Silicon · macOS 15 or later · free · about 12 MB, plus a 600 MB speech model fetched once

Or build it yourself in two commands, without Xcode — see [For developers](#for-developers).

---

## What it is

Plume is dictation with nothing in the way. Press `⌃⇧`, talk, press `⌃⇧` again: the text lands where your cursor is. During a meeting it listens to your microphone *and* to the sound of the computer, then writes down who said what. The words appear in the notch while you speak, and the app lives there and in the menu bar, showing itself only when you are talking.

Everything happens on the Mac. The speech model runs on the Neural Engine — Parakeet Ultra, a 2026 retraining of NVIDIA's Parakeet TDT, converted to Core ML by [Fluid Inference](https://github.com/FluidInference/FluidAudio) — and turns five minutes of speech into text in under two seconds. Speaker separation, echo cancellation and the optional language model are local too. There is no account, no subscription, and nothing to send anywhere.

It started as a free alternative to Superwhisper, designed around what people actually complain about in dictation apps: modes to configure before you can talk, an AI that quietly rewrites your numbers, a subscription for work the Mac does itself, a pause button that never shipped. Here the raw transcript is always kept, anything cleverer is a switch that is off by default, and there is nothing to choose before you speak.

## What it does

- **One shortcut.** `⌃⇧` starts a dictation; `⌃⇧` again pastes it into the active field. Hold the keys instead and Plume listens for as long as you hold them, then pastes when you let go. `esc` cancels (or any key or combination you like, such as `⇧esc`), and a cancelled recording is kept aside for a week so a slip of the finger costs nothing: restore it from the history or a shortcut. Hover the notch for pause, meeting, cancel and done. Pause really closes the microphone — the orange light goes off — and the gap is filled in when you resume.
- **Meetings, both sides.** `⌃⇧⌘`, or the Meeting button on the island in the middle of a dictation. Plume records your microphone and the computer's audio (Meet, Zoom, Teams, FaceTime, anything that makes sound), separates the voices once the recording ends, labels yours "Me" from a voiceprint it learns on your own dictations, and files the dialogue in the history instead of pasting it. No headset? The speakers leak back into the mic; Plume detects that echo and removes it before transcribing, so the other side isn't written down twice. Click a name to rename it everywhere, click a timestamp to listen from there.
- **It notices the call.** When Zoom, Teams, FaceTime, Webex, Slack, Discord or a browser takes the microphone, the island offers to record. It only reads which processes hold the mic; nothing is heard until you click Record. The offer goes away by itself after twenty seconds.
- **Live.** The text appears in the notch as you talk, from the same model that produces the final result, so what you see is what you get.
- **Voice commands.** "new line", "new paragraph", "bullet point", "scratch that", "press enter" — and their French equivalents — are applied after the fact, on the finished text, so the model never has to guess. "Line 42" is not a command.
- **A rule per app.** Each application gets its own style — *Standard*, *Message* (no final period), *Casual* (no capital, no period) — plus, if you want, send with Return (Slack, Messages, a terminal), type the text instead of pasting it (for the few apps that refuse `⌘V`), and a local-AI clean-up with its own instructions. Plume looks at the frontmost app when the dictation starts. There is nothing to pick before talking.
- **Text that fits where it lands.** Plume reads what surrounds the cursor (through accessibility, where the app allows it) and adds a space if the cursor touches a word, drops the capital if the sentence has already begun, drops the final period if it continues after the cursor.
- **Vocabulary.** Replacements for names and jargon. An entry whose "Written" column spans several lines becomes a voice snippet: say "my signature", get your signature.
- **Local AI, if you ask.** On a Mac with Apple Intelligence (macOS 26 or later), Apple's on-device language model can clean up a dictation (punctuation, false starts, "no sorry, at four"), summarise a meeting into key points, decisions and actions, and rewrite a selection on instruction: select text anywhere, press a shortcut, say "translate to English" or "make it shorter". All of it is off by default, nothing leaves the Mac, and if an answer looks wrong — empty, far longer or shorter — Plume keeps the deterministic text. The raw transcript stays in the history either way.
- **A history that is a folder.** Every transcription is a Markdown file, a JSON file and the audio, in `~/Plume`, one folder per month. Search it in the window or with `grep`. Give it a title, export to Markdown, plain text, SRT, WebVTT or JSON, or re-transcribe the kept audio with a newer model. Audio can be kept 90, 30 or 7 days; the text stays.
- **Made for agents.** `plume last`, `plume search budget`, `plume transcribe meeting.m4a`. An MCP server, wired into Claude Code or Claude Desktop from Settings in one click, with a `listen` tool: the agent opens the mic, you answer out loud, it gets the text. `plume://dictee` and friends drive the app from Shortcuts, Raycast or a Stream Deck.
- **The clipboard is yours.** It is restored after every paste, and the dictation is marked transient so clipboard managers don't keep it.
- **Light.** The island in the notch and one window: home, history, vocabulary, applications, settings. A sound at the start and end of each recording, with a few packs to choose from. If the app quits mid-recording, the audio is already on disk and is transcribed at the next launch.
- **Updates itself, quietly.** It checks the GitHub release feed for a newer build, verifies the signature, and installs it for the next launch.

<p align="center">
  <img src="docs/assets/historique.png" width="800" alt="The history window: a list of dictations and meetings on the left, a three-person meeting transcript on the right">
</p>

The interface is in English, with French one click away in Settings; the model handles 25 European languages, and voice commands work in both. More translations are very welcome: the whole interface is one table, `Sources/PlumeKit/L10nTable.swift`.

## What it doesn't do

On purpose:

- No account, no subscription, no cloud. The models run on the Neural Engine. There is nothing to sign in to and nothing to pay for.
- No AI in the middle unless you ask. The text you get is what you said, after a deterministic pass (clean-up, voice commands, vocabulary, style, insertion). Apple Intelligence is a switch, off by default, and the raw transcript is always kept.
- No modes. One shortcut; the app in front decides how the text is shaped.
- No telemetry, no analytics, no crash reports. The only things that leave your Mac are one model download from Hugging Face, the first time, and one small request to GitHub to see whether there is a newer version.
- No Intel, no Windows. Apple Silicon and macOS 15 or later.

## Privacy, concretely

| What | Where it is | Who can read it |
|---|---|---|
| Transcriptions and audio | `~/Plume/`: Markdown, JSON and `.m4a` files, one folder per month, plus `dernier.md` (the latest) and `index.jsonl` | You, `grep`, and any app or AI you point at the folder. |
| Settings, vocabulary, per-app rules | macOS defaults under `studio.brigode.plume`, and small files in `~/Library/Application Support/Plume/` | You. |
| Your voiceprint | One JSON file in that same folder | Plume, to label "Me" in meetings. |
| Speech models | `~/Library/Application Support/FluidAudio/Models/`, about 600 MB, downloaded once | — |
| The log | `~/Library/Logs/Plume/plume.log`. It can contain excerpts of your dictations: read it before attaching it to an issue. | You. |
| Anything else | Nowhere. There is no server. | — |

Three permissions, each asked when first needed: **Microphone** (to hear you), **Accessibility** (to press `⌘V` for you and read around the cursor; without it the text is only copied), **System audio recording** (for the other side of a meeting). The app is signed with a stable certificate, so the permissions survive updates.

Audio is written to disk as it is recorded, for dictations and meetings alike. Delete a transcription from the history and its text and audio go to the Trash together.

## Keyboard

| | |
|---|---|
| `⌃⇧` start · `⌃⇧` again paste · hold `⌃⇧` talk while held · `⌃⇧⌘` meeting · `esc` cancel | Hover the notch: pause, meeting, cancel, done |
| In the window: `1`–`5` home, history, vocabulary, applications, settings · `T` light or dark · `S` sounds | Three more, unassigned by default: paste the last dictation again, restore the last cancelled recording, and transform the selection |

Shortcuts are changed in Settings. A shortcut can be a chord of modifiers alone (`⌃⇧`) or a key with modifiers (`⌥Space`). A chord only fires when it is "clean": `⌃⇧Tab` or `⌃⇧` + click do nothing.

The full tour of settings — microphone, sounds, applications, local AI, model, library — is in the [guide](docs/GUIDE.md) (French).

---

## For developers

### Why the source is here

So anyone can read exactly what an app that hears everything you say does with it, build it themselves, or fix what bothers them. It is about 13,000 lines of Swift, two dependencies (FluidAudio for the models, Sparkle for updates), one file per concern, and no Xcode project.

### Building it

- An Apple Silicon Mac, macOS 15 or later, and the Command Line Tools (Swift 6). Xcode is not needed.
- `swift build -c release` — compiles the app and the `plume` command. With only the Command Line Tools and the macOS 27 SDK, SwiftUI's macros are missing: point `SDKROOT` at an installed macOS 26 SDK (the scripts below do it for you).
- `./scripts/build.sh` — assembles a double-clickable `build/Plume.app`, signed with a local certificate kept in its own keychain so macOS permissions survive rebuilds. `./scripts/build.sh --install` puts it in `/Applications`, links `plume` into `~/.local/bin` and relaunches it.
- `./scripts/test.sh` — the tests (Swift Testing; the script finds the framework without Xcode). The same compile-and-test runs on every pull request.

A build you make yourself is not notarized, so the first launch needs an allow in System Settings › Privacy & Security. Published releases aren't notarized yet either — that needs an Apple Developer account and is on the list — so they get the same one-time "Open Anyway". `./scripts/release.sh <version>` makes the signed `.dmg` and the update feed; `publish.sh` uploads them. Those only matter for the project's own releases; see [docs/PUBLIER.md](docs/PUBLIER.md) (French).

### How it's put together

- **Two targets.** `PlumeKit` is the core with no interface — engine, pipeline, formatting, library, settings — and is what the tests cover; it is kept separate so an iOS app can reuse it. `Plume` is the Mac app: the island, the window, hotkeys, audio capture, sounds, the CLI, the MCP server, updates.
- **The engine** (`Engine.swift`) is FluidAudio on Core ML: Parakeet Ultra for words, pyannote community-1 for voices, both on the Neural Engine. The original Parakeet TDT v3 is there too, selectable in Settings.
- **Live text** (`LiveTranscriber.swift`) re-transcribes a sliding window about twice a second with the same model as the final pass, for 6–7 % of real time. Validated text freezes at sentence ends.
- **Voices** are separated offline, at the end, per channel: the microphone and the system audio are diarized separately and merged by timestamp, which is more reliable than streaming diarization. Speaker changes are snapped to the nearest pause or sentence end, and voices that merely sound alike are never merged. "Me" is a voiceprint learned on dictations, which by definition contain only your voice.
- **The formatting chain** is deterministic and runs in a fixed order — clean-up → voice commands → vocabulary → style → smart insert (`TextCleanup`, `VoiceCommands`, `Replacements`, `Styles`, `SmartInsert`). The language model (`LocalAI.swift`, Apple's FoundationModels) comes after, optionally; its 4,096-token window is why long meetings are summarised in chunks and merged.
- **System audio** comes from a Core Audio process tap, which needs the "system audio" permission and not screen recording. Echo cancellation is LocalVQE, a neural model, applied to the mic with the system audio as reference and only when echo is actually detected.
- **Hotkeys**: the modifier chord is read by polling the keyboard state, so it needs no special permission, and it doesn't fire on `⌃⇧` + key. Quit Superwhisper if you run both, they share `⌃⇧`.
- **Call detection** reads the list of Core Audio processes holding an input (`kAudioHardwarePropertyProcessObjectList`). Nothing is captured.
- **Pausing** stops the microphone for real; the missing silence is filled in on resume. Muting the Mac during a dictation uses Core Audio's default-output mute, not the private MediaRemote framework.
- **Pasting** (`Paster.swift`) reads the active field through accessibility (`AXSelectedTextRange`, `AXStringForRange`) when the app exposes it; web and Electron apps often don't, and then the text is pasted as is.
- **The library** (`Library.swift`) is a folder of Markdown and JSON, not a database. `Recovery.swift` transcribes whatever was being recorded when the app last stopped.
- **The look** is in `Design.swift` — colours as light/dark pairs, Geist and Geist Mono — and `Icons.swift` (Lucide, drawn from SVG paths). Sounds are synthesised in `Sounds.swift` or come from the recorded packs in `Resources/Sounds`.
- `Sources/Plume/` is one file per concern: `Island.swift` is the notch, `Hotkeys.swift` the shortcuts, `MeetingDetector.swift` the call detection, `MCPServer.swift` and `CLI.swift` the agent side, `Updates.swift` the update. The full map is in [docs/DEVELOPPEMENT.md](docs/DEVELOPPEMENT.md) (French).

### Testing it without a microphone

Environment variables replay files in place of the real inputs, on a command channel separate from the installed app, with their own settings and library:

```sh
export PLUME_LIBRARY=/tmp/trial PLUME_CHANNEL=trial PLUME_HEADLESS=1   # invisible, no hotkeys
export PLUME_DEFAULTS=trial PLUME_SUPPORT=/tmp/trial-support             # settings, vocabulary, rules kept apart
PLUME_FAKE_MIC=me.wav PLUME_FAKE_SYSTEM=them.wav PLUME_NO_PASTE=1 PLUME_VERBOSE=1 .build/release/Plume &
.build/release/Plume toggle dictee     # start
.build/release/Plume pause             # pause, then resume
.build/release/Plume toggle reunion    # switch to meeting
.build/release/Plume stop
.build/release/Plume listen            # a dictation that comes back on stdout instead of being pasted
```

Always set `PLUME_DEFAULTS` for a trial: without it, a development binary shares the settings of the installed app. `PLUME_FAKE_CALL=zoom.us` simulates a call starting five seconds after launch, to see the offer in the island.

`plume doctor` reports permissions, model, local AI and screens. `plume transcribe mic.wav --system computer.wav` runs a two-channel meeting from files; `plume diarize file.wav` shows the voices it finds; `plume format "raw text"` shows what the formatting chain does without any audio; `plume render <folder> --demo` draws the whole interface off-screen with an invented library, which is how the screenshots above were made. Test dictations come from the Mac's own speech synthesis: `say -v Jacques -o d.aiff "Bonjour, à la ligne, …"`, then `afconvert -f WAVE -d LEI16@16000 -c 1 d.aiff d.wav`.

### Contributing

Issues and pull requests are welcome — bugs, ideas, code, translations. [CONTRIBUTING.md](CONTRIBUTING.md) says how things are reviewed; the short version: small changes, no new dependency without an issue first, nothing that phones home, and a screenshot or a short video when the interface changes. Code, comments and the interface are in French; match the file you are in.

What's next is in [docs/PLAN.md](docs/PLAN.md): an iOS app on the same engine, acoustic vocabulary for proper nouns, vocabulary learned from your corrections, an offer to end the meeting when the call ends, notarization, translations.

### License

MIT — see [LICENSE](LICENSE). Do what you want with the code. The models, fonts, icons and sound packs have their own licenses (CC BY 4.0, Apache 2.0, OFL, ISC), listed with their authors in [Resources/LICENCES.md](Resources/LICENCES.md). Please give a fork its own name and icon before distributing it.
