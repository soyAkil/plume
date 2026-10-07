# User guide

Everything Plume can do, in detail. For the essentials, see the [README](../README.md).

## Gestures

| Gesture | Effect |
|---|---|
| `⌃⇧` (short press) | Starts a recording. Second press: the text is pasted into the active field. |
| `⌃⇧` (held) | Talks for as long as the keys are held; release to paste. |
| Hover the notch | The **Meeting** key (it latches and stays lit), cancel, finish. |
| `⌃⇧⌘` | Starts a meeting directly (or switches to one mid-dictation). |
| `Esc` | Cancels the current dictation (the shortcut can be changed). The cancelled recording can be restored, see [Cancelled recordings](#cancelled-recordings). |
| Hover the notch › `⏸` | Pauses the recording (the microphone closes); `▶` resumes. |
| Click the menu bar icon | Opens the Plume window (right-click: short menu, with the latest dictations to copy again). |
| `1` `2` `3` `4` `5`, `T`, `S` in the window | Home, history, vocabulary, applications, settings; light / dark theme; sounds. |

With no shortcut: the **Dictate** button on Home steps the window aside (focus returns to the
previous app, the one the text will be pasted into) and starts the dictation in the notch;
during a dictation, it finishes it. Home also shows the three latest transcriptions, and
**What's new**, at the top right of the window, opens the changelog (`CHANGELOG.md`), with a dot
while there is something new.

Three more shortcuts, with no default key (set them in **Settings › Shortcuts**): **Paste the
last dictation again** (when the paste failed, or to reuse it elsewhere), **Restore the last
cancelled recording** and **Transform the selection** (see [Local AI](#local-ai)).

The **Cancel the dictation** shortcut accepts a single key or one with modifiers, Esc included
(`⎋`, `⇧⎋`, `⌃⎋`…): a combination avoids cutting off a dictation by pressing Esc out of reflex
in another app. It is only intercepted during a dictation; the rest of the time, the key keeps
its role.

Shortcuts are changed in **Settings**. A shortcut can be a chord of modifiers alone (`⌃⇧`) or a
key with modifiers (`⌥Space`). A chord only fires when it is "clean": `⌃⇧Tab` or `⌃⇧` + click
do nothing.

## What happens to the dictated text

In order, at the end of each dictation:

1. **Clean-up**: hesitations ("um") and stuttered words removed. The model's raw text is kept
   in the history.
2. **Voice commands** (Settings › Dictation): "new line", "new paragraph", "new bullet",
   "question mark", "exclamation mark", "open / close quote", "open / close parenthesis",
   "scratch that" (removes the preceding sentence), "delete everything", and "press enter" at the very end to send the message. In French:
   « à la ligne », « nouveau paragraphe », « nouvelle puce » (or « tiret » after a line break),
   « point d'interrogation », « point d'exclamation », « deux points » (followed by a pause),
   « points de suspension », « ouvrez / fermez les guillemets », « ouvrez / fermez la
   parenthèse », « efface ça », « efface tout », and « appuie sur Entrée ». Plume doesn't mistake
   "a new line of products" or "line 42" for a command.
3. **Vocabulary**: the replacements from the Vocabulary page. An entry whose "Written" column
   spans several lines (`⌥↩`) makes a voice snippet: "my signature" becomes your full
   signature.
4. **The app's style** (Applications page): *Standard*, *Message* (no final period), *Casual*
   (no capital at the start of a sentence, no final period).
5. **Clean up with the local AI**, if requested (see below).
6. **Write as you speak** (Settings › Dictation, off by default, marked "beta"): words are
   typed into the field while you talk, five times a second, as live transcription hears them;
   when the model corrects itself, Plume erases the few characters that change and retypes. The
   last word heard waits for the next one (it is the least certain). On stop, what is left is
   typed right away. The text goes through clean-up, voice commands ("scratch that" also erases
   what is already typed), vocabulary and the app's style; AI clean-up doesn't apply, and the
   history keeps the full version transcribed in one block. Don't move the cursor while it
   writes.
7. **Smart insert** (Settings › Dictation): Plume looks at what surrounds the cursor (through
   accessibility, when the app allows it) and adds a space if the cursor touches a word, uses
   lowercase if the sentence has already begun, drops the final period if it continues after
   the cursor.

## Applications

The **Applications** page gives each app its own dictation rule: the text style, **Send with
Return** (the message goes out as soon as it is pasted — for Slack, Messages, a terminal), **Clean
up with the local AI** with its instructions ("be formal", "no emojis"), and **Type
the text instead of pasting it** for the few apps that refuse `⌘V` (remote desktop, some
terminals). "All other applications" sets the default rule. Plume recognizes the frontmost app
at the moment the dictation starts.

## Local AI

On a Mac with Apple Intelligence (macOS 26 or later, Apple Intelligence turned on in System
Settings), Plume can use Apple's language model, which runs on the device: nothing leaves the
Mac. Everything is optional, off by default.

- **Clean up dictations** (Settings › Local AI, or per app): punctuation, false starts and
  self-corrections ("no sorry, at 4 pm") fixed, without changing the meaning. If the answer
  looks doubtful (empty, much longer or shorter), Plume keeps the deterministic text. The raw
  text stays in the history.
- **Summarize a meeting**: in the history, the **Summarize** button writes the key points,
  decisions and actions, and suggests a title. The summary is stored in the transcript's
  Markdown file (a "Summary" section), so AIs that read the library can see it. **Settings ›
  Local AI › Summarize every meeting** does it automatically.
- **Transform the selection** (shortcut to set): select text in any app, press the shortcut,
  say an instruction ("translate to English", "shorter", "make it a list", "make it more
  formal"); the AI rewrites it and the result replaces the selection. With no selection, it
  writes from the instruction ("a message to tell Marc I'll be late").

Without Apple Intelligence, these settings are greyed out and explain why.

## Meetings

When **Zoom, Teams, FaceTime, Webex, Slack, Discord** or **a browser** (Meet, Teams web) starts
using the microphone, the notch offers to record the meeting: one click on **Record** is enough.
The offer goes away on its own after twenty seconds. Settings › Meeting › *Offer to record when
a call starts* turns it off. Plume only reads the list of audio processes: nothing is heard
before you ask.

During a recording, if the microphone picks up nothing for fifteen seconds, the notch's
waveform goes out and a bluish "zZ" settles on it: microphone muted, wrong device. Everything
returns to normal as soon as sound arrives.

Audio is written to disk as it goes, for a meeting as for a dictation: if the app stops in the
middle of a recording, it is transcribed at the next launch.

In meeting mode, Plume also captures the system audio, separates the voices at the end, and
files the dialogue in the history instead of pasting it. Without headphones, the speakers' sound
leaks back into the microphone: Plume detects it and removes that echo before transcribing,
otherwise the remote voices would appear twice and drown out yours. If the voices are still
poorly separated, "Redo speaker separation" (in the history) listens to the audio again,
forcing the number of people. "Me" is your voice: Plume learns it from your dictations (a
voiceprint stored locally). In the history, a click on a name renames it everywhere; a click on
a timestamp starts playback from there.

Plume doesn't listen to the system's default audio input but to the microphone chosen in
**Settings › Microphone & sounds** — by default the Mac's. So connecting earbuds or a Bluetooth
speaker changes nothing; to dictate with their microphone, you have to choose it yourself.

**Settings › Dictation › Mute the computer while dictating** mutes music or video playing while
you talk, then restores it (never in a meeting).

## History

Each transcription can get a **title** (click the title); otherwise the date stands in. The
**Export** button saves it as Markdown, plain text, SRT or WebVTT subtitles (for meetings) or
JSON. **Transcribe again** redoes the transcription from the kept audio, with the current model.
The clipboard is always restored after pasting, and the dictation is marked "transient":
clipboard managers (Paste, Maccy, Raycast…) don't keep it in their history.

**Settings › Library › Keep from each dictation**: *Text and audio* (default), *Text only*, or
*Nothing* — the dictation is pasted then forgotten, with no text, no audio, no safety file
(meetings, which have nowhere else to go, stay in the history). **Keep audio** limits how long
recordings are kept (90, 30 or 7 days): older audio is deleted at launch, the text stays.

### Cancelled recordings

A cancelled dictation or meeting (shortcut, notch button, menu) isn't thrown away right away:
it is set aside in `~/Plume/.cancelled/`, out of the history and the index. It can be found with
the `↶` button at the top of the history (you can listen to it, copy it, restore it or delete
it), with the **Restore the last cancelled recording** shortcut, the menu bar menu,
`plume restore` or `plume://restore`. A cancelled dictation is transcribed in the background
(restoring it pastes it right away, from the notch or the shortcut); a meeting is only
transcribed when you restore it. **Settings › Library › Keep cancelled recordings**: *Don't
keep*, 1 hour, 24 hours, 7 days (default) or 30 days; after that delay, they are deleted. A
press shorter than one second isn't kept.

**All settings › Export…** writes shortcuts, options, vocabulary and per-app rules to a JSON
file, to import on another Mac.

## Language

The interface is in English by default; **Settings › General › Language** switches it to French
(or back), regardless of the system language. macOS system dialogs (permission prompts, open/save
panels, update dialogs) follow the Mac's language. The choice applies to the window, the notch,
the menus, transcript titles ("Meeting, Oct 2, 2026 at 11:30 AM" / "Réunion du 2 oct. 2026 à
11:30"), speaker names ("Me", "Speaker 1" / "Moi", "Interlocuteur 1") and the meeting notes
written by the local AI. Voice commands work in both languages whatever the setting. Command-line
messages follow the setting; some saved keys stay French whatever the setting (see
[Field names](#field-names)).

## Transcription models

**Settings › Model** offers the whole Parakeet family that FluidAudio can run on the Neural
Engine, each with its languages, size and accuracy: Parakeet Ultra (recommended, 25 languages),
Parakeet TDT v3, Parakeet Redux (compact, 220 MB), Parakeet TDT v2 and Phonon-2 (English),
Parakeet TDT-CTC 110M (English, the fastest), Parakeet Japanese. Each model is downloaded once
from Hugging Face, then everything happens offline. **Custom folder…** loads your own model: a
folder in Parakeet format (four `.mlmodelc` — Preprocessor, Encoder, Decoder, JointDecision —
and `parakeet_vocab.json`), for example a Parakeet retrained on your vocabulary and converted
with FluidAudio's tools. The history's **Transcribe again** button lets you compare two models
on the same recording.

## Sounds

A sound at the start and end of each recording, chosen in **Settings › Microphone & sounds ›
Sound pack**: Pluck (default), Beeps, Clicks, Melody, Glide, or Wood. The packs are recorded
sounds (`Resources/Sounds`), shortened and softened by the app; Wood is synthesized on the fly
with the portfolio kit's recipe (a very restrained marimba, pentatonic scale). Gestures in the
window (hovers, tabs, switches) have their own synthesized notes. Volume and mute are in
**Settings › Microphone & sounds** or with the `S` key. `plume sounds <folder>` writes all the
sounds as WAV, one subfolder per pack.

## macOS permissions

| Permission | Why | When |
|---|---|---|
| Microphone | To hear you | First dictation, or from Home |
| Accessibility | To simulate ⌘V and paste the text | From Home; without it the text is only copied |
| System audio recording | To capture the system audio in a meeting | First meeting |

The app is signed with a stable local certificate: permissions survive updates.

## The library: `~/Plume`

```
~/Plume/
  README.md                            how-to for the folder, for AIs
  latest.md                            the most recent transcription
  dernier.md                           deprecated copy of latest.md, for older scripts
  index.jsonl                          one JSON line per transcription
  .cancelled/                          cancelled recordings, kept for a while
  2026-10/
    2026-10-02_14-31-05_dictee.md      text, with a header (date, duration, speakers)
    2026-10-02_14-31-05_dictee.json    full data (timestamped segments, raw text)
    2026-10-02_14-31-05_mic.m4a        original audio (mic = microphone, sys = system audio)
```

`dernier.md` is only there for scripts written before `latest.md`; it may go in a later
version (announced in the changelog), so use `latest.md`. `README.md` is written only if
missing: a `README.md` of your own is never touched. The French `LISEZMOI.md` of earlier
versions is removed only if you never edited it and `README.md` is Plume's own.

### Field names

The keys of `index.jsonl`, of the Markdown header and of `plume list` / `plume search --json`
are French and stay so: scripts read them. `plume last`, `show` and `transcribe --json` and the
per-transcript `.json` files use English camelCase keys instead, and the mode values
`dictation`, `meeting` and `imported` (see [below](#english-json-keys)).

| Key | Meaning |
|---|---|
| `id` | Transcription id, also the file name prefix (`2026-10-02_14-31-05`) |
| `date` | Start of the recording, ISO 8601 |
| `mode` | `dictee` (dictation), `reunion` (meeting) or `import` (imported audio) |
| `appareil` | Device that recorded it (`mac`) |
| `duree_s` | Duration in seconds (`index.jsonl`); the Markdown header has `duree`, the same text as a phrase ("2 min 05 s") |
| `interlocuteurs` | Speakers: names or labels such as "Me", "Speaker 1" (French UI: "Moi", "Interlocuteur 1") |
| `fichier` | Path of the `.md` file, relative to the library |
| `titre` | Title, only when one was set |
| `apercu` | Preview: the first words of the text |
| `application` | Header only: the app the text was pasted into |
| `moteur` | Header only: the transcription engine |
| `audio` | Header only: the audio files kept |

The mode also shows in file names (`_dictee`, `_reunion`, `_import`). The MCP tools' `mode`
filter and `plume --mode` accept `dictation`, `meeting` and `imported` as well as these slugs.

### English JSON keys

The per-transcript `.json` file and `plume last` / `show` / `transcribe --json` hold one
transcription with these keys:

| Key | Meaning |
|---|---|
| `id`, `createdAt` | Id and start of the recording (ISO 8601) |
| `mode` | `dictation`, `meeting` or `imported` |
| `device`, `engine` | Device and transcription engine |
| `duration` | Duration in seconds |
| `text`, `rawText` | Final text, and the model's raw output before cleanup |
| `segments` | Timestamped parts: `id`, `speaker`, `channel` (`mic` or `system`), `start`, `end`, `text` |
| `speakers` | Speaker names or labels |
| `audioFiles` | Audio file names, relative to the transcription's folder |
| `app`, `title`, `summary` | Only when set: target app, title, summary |

## Access for an AI

1. **The folder.** "Read `~/Plume/latest.md`" is enough for any agent with file access.
2. **The `plume` command line**:
   ```sh
   plume last                 # latest transcription
   plume last --mode reunion  # latest meeting
   plume list -n 10           # the last ten
   plume search budget site   # full-text search
   plume show 2026-10-02_14-31-05
   plume transcribe audio.m4a --mode reunion --save
   plume export 2026-10-02_14-31-05 --format srt -o meeting.srt
   plume summarize 2026-10-02_14-31-05       # summary by the local AI
   plume listen                              # dictates in the app, the text comes back here
   ```
   Add `--json` for structured output.
3. **The MCP server** (`plume mcp`), registered in Claude Code. Tools: `get_latest_transcript`,
   `list_transcripts`, `get_transcript`, `search_transcripts`, `summarize_transcript`, and
   **`listen`**: the agent opens the microphone, you answer out loud, you finish with your
   shortcut, it receives the text. Enough to tell Claude Code "ask me out loud" instead of
   typing.

`plume toggle dictee|reunion`, `plume stop`, `plume cancel`, `plume pause`, `plume paste`
(paste the last dictation again), `plume restore` (restore the last cancelled recording;
`plume cancelled` lists them) and `plume open` drive the running app from a script, Raycast or
a Stream Deck. The links `plume://dictation`, `plume://meeting`, `plume://stop`, `plume://pause`,
`plume://paste`, `plume://restore`, `plume://transform`, `plume://cancel` and `plume://open` do
the same from Shortcuts or any app (the French `dictee`, `reunion`, `recoller`, `recuperer`,
`transformer`, `annuler` and `ouvrir` still work). `plume doctor` shows the version and the
state of permissions, model, local AI and screens; `plume format "text"` shows what the formatting
does to raw text; `plume polish` and `plume transform` try the local AI.
