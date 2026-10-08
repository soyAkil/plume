# Changelog

One line per PR or PR stack, grouped by date, newest first. A version takes the date it was released. The detail is in the PR.

## 1.0.2

### 2026-10-08

- Recovery: a meeting recovered after a crash keeps its two channels in time, including one switched from a dictation (#21)

### 2026-10-06

- Library: English file and setting names (latest.md, README.md, .cancelled, replacements.json, voiceprint.json); older names still read, but 1.0.1 no longer sees the vocabulary, voiceprint, cancelled recordings or appearance and sound choices (#16)
- Repo: code, comments and docs in English; English is the interface's source language, system dialogs follow the Mac's language (#15)
- Tests: release.sh stops if a test fails; tests stay clear of the installed app's settings and library, no longer fail at random, and cover the clipboard, re-reading released versions' files, the command line, the MCP server and dictation text (#9)

## 1.0.1 — 2026-10-05

### 2026-10-05

- Home: during a dictation, the "Dictate" button shows the incoming voice and the elapsed time; latest transcriptions show their words and duration
- Window: the top-right corner gets lighter ("Ready" is no longer shown, What's new becomes an icon)
- Release: partial updates are attached, a few MB instead of the whole image

## 1.0.0 — 2026-10-05

### 2026-10-05

- Home: a "Dictate" button that tucks the window away and starts dictation, and the latest three transcriptions (copyable in one click) next to the activity (#7)
- What's new: this changelog reads in the app, from the top-right button (#7)
- Cancel: a cancelled recording stays recoverable for a few days, and the cancel shortcut is configurable (#7)
- Plume 1.0: voice commands, per-app rules, cursor-aware insertion, pause, call detection, local AI (Apple Intelligence), exports, English interface (#7)
- `plume` command: launched through its `~/.local/bin/plume` link, it finds the app's sounds and fonts (#4)
- Changelog: this file, one line per PR (#5)
- Paste: dictation is marked transient, so clipboard managers no longer keep it (#2)
- Scripts: the build falls back to the macOS 26 SDK when SwiftUI asks for Xcode (#1)

### 2026-10-02

- README: in English, with a header visual

## 0.9.0 — 2026-10-02

### 2026-10-02

- First public release: voice dictation and meeting transcription, 100% local
