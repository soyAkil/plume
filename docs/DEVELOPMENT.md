# Developing Plume

Build, test, understand the code and release a version. To contribute, see also
[CONTRIBUTING.md](../CONTRIBUTING.md).

## Commands

```sh
./scripts/build.sh             # builds and assembles build/Plume.app
./scripts/build.sh --install   # … then installs into /Applications and relaunches
./scripts/test.sh              # logic tests
./scripts/release.sh 1.0.1     # releasable version, or one for testers (see docs/RELEASING.md)
./scripts/icon.sh              # rebuilds the app icon from Resources/Icon.jpg
```

No Xcode required: SwiftPM and the Command Line Tools are enough. You need an Apple Silicon Mac
on macOS 15 or later.

With the macOS 27 SDK, SwiftUI macros (`@State`) only ship with Xcode: without it, the scripts
fall back on their own to an installed macOS 26 SDK (`scripts/sdk.sh`). For a hand-run
`swift build`:
`SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk swift build -c release`.

## Code map

```
Sources/PlumeKit/      core independent of the interface (reusable for an iOS app)
  Engine.swift           local engine: transcription + speaker separation (FluidAudio / CoreML)
  LiveTranscriber.swift  live transcription with a sliding window
  Pipeline.swift         final processing: dictation, multi-channel meeting, voiceprint
  TranscriptBuilder.swift timestamped words + diarization → speaker turns
  TextCleanup.swift      light clean-up (hesitations, stuttered words)
  VoiceCommands.swift    "new line", "scratch that", "press enter"… run after the fact
  Styles.swift           text style (standard, message, casual) and per-app rules
  SmartInsert.swift      space, lowercase and final period adapted to what surrounds the cursor
  Replacements.swift     vocabulary: word replacements and snippets
  LocalAI.swift          the local AI (Apple Intelligence): polish, summary, transform
  Exporter.swift         export to Markdown, text, SRT, WebVTT, JSON
  SettingsBackup.swift   backup and restore of all settings as JSON
  Localization.swift, L10nTable.swift   interface language: `tr("…")` and the English → French table
  Library.swift          on-disk library (md + json + index), audio maintenance
  Stats.swift            home page figures
  Recovery.swift         recovery of interrupted recordings
  Cancelled.swift        cancelled recordings kept aside (~/Plume/.cancelled), purge, restore
  Importer.swift         transcription of an existing file
Sources/Plume/         the macOS app
  SessionController.swift conductor of a recording (dictation ↔ meeting, pause, AI instruction)
  AudioCapture.swift     microphone and system audio, read directly by Core Audio
  AudioDevices.swift     list of microphones, choice of the one to use
  MeetingDetector.swift  spots a video-call app opening the microphone (meeting offer)
  SystemVolume.swift     mutes the computer's sound for the length of a dictation
  Paster.swift           pasting, typing, Return, reading the active field through accessibility
  Hotkeys.swift          global shortcuts
  Island.swift           the notch island
  Sounds.swift           the sounds: synthesis ("Wood" kit) and recorded packs
  Design.swift           colors, typography (Geist, Geist Mono), components and motion
  Icons.swift            portfolio icons (Lucide at 1.6 stroke) and SVG path reader
  Updates.swift          automatic updates (Sparkle)
  Integrations.swift     `plume` command, connection to Claude Code and Claude Desktop
  AppShell.swift, AppPages.swift, AppRulesPage.swift, AppModels.swift   the window: home, history, vocabulary, applications, settings
  AppDelegate.swift      menu bar, window, plume:// links, wiring
  MCPServer.swift, CLI.swift, Remote.swift, Doctor.swift   AI and script side
Read aloud (`plume read-aloud`): a selection read word for word, or a summary written by a local model
  Sources/PlumeKit/ReadAloud/
    ReadAloudPipeline.swift    text → events (language, sentences, progress); word for word or summary
    SpokenText.swift           what a listener expects to hear: no URLs, markdown or code; language choice
    SentenceSplitter.swift     cuts streamed text into sentences so the voice starts on the first one
    Voice.swift                `Voice` protocol and the Supertonic-3 voice (FluidAudio); digits spelled out first
    SummaryService.swift       model-neutral summary request → stream of text
    SummaryPrompt.swift        the summary prompt: sentence budget, language, input truncation
    SummaryCleaner.swift       drops a model's reasoning and markup from the stream before it is spoken
    LlamaSummaryService.swift  GGUF model run in process by llama.cpp, on one serial queue
    PromptRenderer.swift       applies the model's chat template; the selection is tokenized apart
    EngineCatalog.swift        pinned models and voices: repository, revision, size, SHA-256, markers
    ReadAloudModels.swift      download, delete and one-at-a-time lock for the model files
    ModelFileDownloader.swift  resumable download checked by size and SHA-256
    ReadAloudOptions.swift     summary length, language, keep-in-memory and speed settings
    ReadAloudError.swift       the errors the command and the app show
    ReadAloudEval.swift        quality eval: every selection summarized by every engine, with timings
  Sources/Plume/
    ReadAloudCommand.swift     the command: reads, summarizes, downloads, prints `--json`
    ReadAloudPlayer.swift      plays sentences in order through a pitch-preserving time-stretch
    ReadAloudEvalCommand.swift `plume read-aloud --eval`: runs the eval and writes the results file
  bench/read-aloud-eval/     README, and the blind judge page (judge.html, judge.js) for the eval results
```

## Releasing

`./scripts/release.sh <version>` builds the signed app (and notarized, once the Apple Developer
account is in place), the disk image and the update feed; `./scripts/publish.sh <version>`
publishes them to this repository's releases. Automatic updates go through Sparkle. Full
procedure: [RELEASING.md](RELEASING.md).

## Changing or updating the model

The model is chosen in Settings, from the whole Parakeet TDT family in FluidAudio
(`AsrModelVersion`) or a custom folder. To pick up a new model published by FluidAudio: bump
the version in `Package.swift`, add a case to `EngineModel` (`Engine.swift`) with its label,
description and `version`, then `./scripts/build.sh --install`. Models are cached in
`~/Library/Application Support/FluidAudio/Models`. A custom folder is loaded by
`AsrModels.loadLocal`; its family (v2, v3, TDT-CTC) is guessed from the vocabulary size and
whether there is a separate encoder. FluidAudio's other engines (Cohere Transcribe,
SenseVoice, Paraformer, Parakeet Unified) each have their own pipeline: plugging them in takes
an abstraction above `AsrManager`, not just one more case.

## Testing without a microphone

Environment variables replay files in place of the real inputs, on a command channel separate
from the installed app:

```sh
export PLUME_LIBRARY=/tmp/trial PLUME_CHANNEL=trial PLUME_HEADLESS=1   # invisible, no hotkeys
export PLUME_DEFAULTS=trial PLUME_SUPPORT=/tmp/trial-support             # settings, vocabulary and rules kept apart
PLUME_FAKE_MIC=me.wav PLUME_FAKE_SYSTEM=them.wav PLUME_NO_PASTE=1 PLUME_VERBOSE=1 .build/release/Plume &
.build/release/Plume toggle dictee    # start
.build/release/Plume pause            # pause, then resume
.build/release/Plume toggle reunion   # switch to meeting
.build/release/Plume stop
.build/release/Plume listen           # dictation without pasting, the text comes back on standard output
```

`PLUME_DEFAULTS=trial` makes settings read and write in a separate set
(`studio.brigode.plume.trial`): without it, the development binary shares the installed app's
settings. `PLUME_FAKE_CALL=zoom.us` simulates a call that starts five seconds after launch, to
see the meeting offer in the island.
`PLUME_SCREEN=notch|alternate|external` forces the screen the island appears on (the notched one,
each screen in turn, the one without a notch); `plume drawer-open` and `plume drawer-close` open and
close the island's drawer without the mouse.

`plume transcribe mic.wav --system computer.wav` processes a two-channel meeting from two
files; `plume aec mic.wav computer.wav clean.wav` isolates echo cancellation. `plume live
file.wav` replays a file through live transcription; `plume diarize file.wav` shows the
detected voices; `plume render folder/` produces PNG previews of the interface. `plume format
"raw text" [--style message]` shows the formatting without audio; `plume polish`, `plume
transform "instruction"` and `plume summarize <id>` try the local AI; `plume calls` lists the
apps holding the microphone. Test dictations are made with the Mac's speech synthesis: `say -v
Jacques -o d.aiff "Bonjour, à la ligne, …"` then `afconvert -f WAVE -d LEI16@16000 -c 1 d.aiff
d.wav`. The app log is in `~/Library/Logs/Plume/plume.log`.

## Screenshots for the README

`plume render <folder> --demo` draws the interface off-screen with an invented library and a
fictional first name: nothing personal appears. The README images are in `docs/assets/`.
Without `--demo`, the render shows your real library: don't publish it. `home.png` and
`history.png` are `app-home-dark.png` and `app-history-dark.png` as rendered; `notch.png` is a
900×210 crop of `island-4-meeting-hover-notch.png` at x 170, y 0 (an offset chosen to match the old framing):
`sips --cropToHeightWidth 210 900 --cropOffset 0 170 <render>/island-4-meeting-hover-notch.png
--out docs/assets/notch.png`. `dictation.png` is a composited mockup, not a render.
