# Contributing

Plume is a small, mostly solo project. Help is welcome in every form — a bug report, an idea, code, a translation — and a few things make a change land faster.

## Before writing code

For anything beyond a small fix, open an issue first saying what you want to change and why. It saves a rewritten pull request later if the direction doesn't fit.

## Reporting a bug or proposing an idea

Open an [issue](https://github.com/soyAkil/plume/issues/new/choose): a form guides you through it (bug or idea). If you attach Plume's log, `~/Library/Logs/Plume/plume.log`, read it first — it can contain excerpts of your dictations. It never leaves your Mac unless you paste it somewhere yourself.

## Proposing a change

1. Fork the repository and make a branch (`git switch -c my-feature`).
2. Build it and try it: `./scripts/build.sh --install` (an Apple Silicon Mac, macOS 15 or later, the Command Line Tools; Xcode is not needed). The app then shows as `<version>-dev+<commit>`. If it offers a Plume release, accepting replaces your build with the maintainer-signed app, and macOS asks for Microphone, Accessibility and System Audio Recording again. The same happens when you go back to your own build.
3. Run the tests: `./scripts/test.sh`. The same compile-and-test runs on every pull request.
4. Open a pull request that explains *why*, with a screenshot or a short video if the interface changes.

## What tends to get merged

- **Small, focused changes.** One thing per pull request, easy to read start to finish.
- **No new dependencies** without an issue first. The whole list is FluidAudio and Sparkle, and the app compiles without Xcode because of it.
- **Matches the existing style.** Code, comments, commit messages, pull request descriptions and docs are in English. Interface text is written in English inside `tr("…")`, with its French translation in `Sources/PlumeKit/L10nTable.swift` (French text uses the informal "tu"). Comments explain *why*, not what the next line does. Read the file you are in before adding to it. Settings go through `PlumeSettings` (PlumeKit) and `SettingsModel` (app).
- **Nothing that phones home.** What leaves the Mac today is one model download and one update check; a change to that boundary needs a discussion, not a pull request.
- **Nothing personal in the repository.** No recording, no transcription, nothing from `~/Plume`. Tests use invented sentences, and a `plume render` is only published with `--demo`.
- **A changelog line.** Add `- Area: effect, in a few words (#number)` at the top of `CHANGELOG.md`, under today's date; [AGENTS.md](AGENTS.md) has the details.
- **Builds clean, tests pass.**

## Finding your way

- `Sources/PlumeKit/` is the core with no interface — engine, pipeline, formatting, library — and is what most tests cover.
- `Sources/Plume/` is the Mac app: the island in the notch, the window, hotkeys, sounds, the CLI, the MCP server.
- The file-by-file map is in [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md), with a section on testing without a microphone.

## Ideas to start with

- an iOS app that reuses `PlumeKit` (see [docs/PLAN.md](docs/PLAN.md));
- new sound packs (`SoundPack` in `Sources/Plume/Sounds.swift`);
- support for other transcription models;
- translations of the interface.

## Review

Pull requests are reviewed by the maintainer. This isn't anyone's full-time job, so a review can take a while; pinging a quiet pull request after a couple of weeks is completely fine.
