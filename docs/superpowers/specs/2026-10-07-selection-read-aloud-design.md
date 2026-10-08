# Read the selection aloud: design

Status: 2026-10-07, revision 15: the owner's review answers applied to revision 5 (which four
independent reviews had brought to clean), then the fifth to thirteenth reviews' findings (the thirteenth found it clean).

## Goal

Select text in any app, press a shortcut, and hear it, entirely on the Mac. Two modes, each
with its own shortcut:

- **Read aloud**: the selection, word for word. Needs only the voice (162 MB).
- **Summarize aloud**: a short spoken summary, written by a local language model (an optional
  download of about 3 GB on top of the voice). Two uses:
  - quick gist: an email, a thread, a paragraph; know in a few seconds what it says;
  - long reads, hands-free: an article or a document; the essentials while doing something
    else.

During a summary, the island offers **Read the full text**, which switches to word for word on
the same selection.

Speed comes first (time to the first sound), speech quality second.

### Performance target

The feature must be comfortable on a **base M2** (8 or 10 GPU cores, 8 GB), not only on the
M5 it was benchmarked on:

- read aloud: first sound in **≤ 0.5 s**, any length (the first sentence is capped at about 70
  characters for this; measured on the M5 only);
- summary of an email or a short thread (~500 tokens): first sound in **≤ 3 s**;
- summary of a 1,300-word article (~2,200 tokens): first sound in **≤ 10 s**;
- longer summaries: progress shown while the model reads the text, with the remaining time.

These targets assume the models are already loaded ("warm"). Loading the summary model adds
1.5 to 3 s on the M5 (more on an M2, and ~4 s more the very first time, while Metal compiles its
kernels); loading the voice adds well under a second once compiled. The "Keep the models loaded"
setting decides how often a read starts cold; the quality eval records cold and warm timings.

### Non-goals (v1)

- No history: nothing read or summarized is saved.
- No Apple Intelligence or cloud backend. The design leaves room for both (see "Swapping
  models and services").
- No MCP tool.

## Decisions and the evidence behind them

Measurements: base Apple M5 (10 GPU cores), 24 GB, macOS 26.6. Throwaway benchmarks on branch
`spike/selection-summary` (`bench/selection-summary/`).

| Topic | Choice | Why |
|---|---|---|
| Summary model | **Chosen by the user** from a small catalog, with one entry marked "Recommended" for this Mac. Candidates: Qwen3.5-4B Q4_K_M (2.74 GB) and Gemma 4 E2B Q4_0 (2.8 GB), both Apache 2.0. Which ones ship is decided by the quality eval below. | Qwen3.5-4B met all constraints in 7 of 7 bench cases; Gemma 4 E2B met 6 of 7 (once answered in French when English was asked) and is ~1.7× faster. Gemma 4 E4B was slightly better than both but is 5.2 GB and as slow as Qwen, so it is out. |
| LLM runtime | llama.cpp, official XCFramework, embedded in the app | Builds with SwiftPM and the Command Line Tools (verified: `binaryTarget` → library → executable builds and runs). MLX reads prompts ~30% faster with the same generation speed, but needs Xcode and only runs on Apple hardware. llama.cpp and GGUF also run on Windows, Linux, Android, iOS and the web. |
| Runtime placement | In process, through llama.cpp's C API | Tokens stream straight into the voice; nothing extra to sign or supervise. |
| Voice | Supertonic-3 (FluidAudio 0.17.5, already a dependency), voice F1 by default, M2 as an option | Picked by ear among Supertonic F1/M2, Kokoro and PocketTTS at 1.5×. ~90× real time on the M5, 162 MB for 31 languages, licence OpenRAIL++. |
| Numbers | FluidAudio's `NemoTextNormalizer` before the voice (for the languages it shares with Supertonic-3: French, English, Spanish, German, Japanese, Hindi) | Supertonic misreads digits ("du 14 au 21" → "du 14 au zoo 21"); written out, it reads them correctly. |
| Playback speed | Pitch-preserving time-stretch at playback (`AVAudioUnitTimePitch`), 0.75× to 2×, default 1.5× | Works for any voice engine and can change during playback. Intelligible at 1.5×. |
| Downloads | Nothing is downloaded or deleted without an explicit user action | Plume stays at its current size for everyone else; the user decides what occupies the disk. |
| New dependency | llama.cpp (MIT) | The owner waived the issue that `AGENTS.md` asks for. |

### Projected speed on typical Macs

Projected from this M5's measurements with the per-chip ratios of llama.cpp's public Apple
Silicon benchmark (discussion #4167, Llama 7B Q4_0). The older chips there were measured on an
older llama.cpp, so these numbers are pessimistic. Time to first sound of a summary = reading
the selection + writing the first sentence (~30 tokens) + 0.05 s of voice.

| Chip | Qwen3.5-4B: email / 1,300 w / 3,500 w | Gemma 4 E2B: email / 1,300 w / 3,500 w |
|---|---|---|
| M1 | 4.8 / 15.5 / 39 s | 2.9 / 9.4 / 24 s |
| **M2** | **3.1 / 10.2 / 26 s** | **1.9 / 6.2 / 15 s** |
| M4 | 2.7 / 8.4 / 21 s | 1.6 / 5.1 / 13 s |
| M4 Pro | 1.3 / 4.2 / 11 s | 0.8 / 2.6 / 6 s |
| M5 (measured basis) | 1.3 / 3.1 / 7 s | 0.8 / 1.9 / 4 s |

Qwen3.5-4B sits right at the M2 target's limit; Gemma 4 E2B meets it with margin. The voice is
not the bottleneck (~90× real time on the M5; even 10× slower would keep up), which is also why
reading aloud word for word starts almost at once.

### Quality eval (gate before choosing the catalog)

Before the catalog is fixed (PR 1), both candidates summarize the same 30 to 50 real
selections provided by the owner, through Plume's own in-process path, not the bench's
`llama-server`. The owner judges, blind; Plume records the timings. PR 1 ships the kit and a
step-by-step walkthrough (`bench/read-aloud-eval/README.md`), so the eval can be run without
help:

1. **Collect.** Create an eval folder outside the repository (`<eval folder>`, for example in a
   scratch folder of your own) with a `selections/` folder inside, and drop one `.txt`
   file per selection: mail, Slack threads, articles, documentation; French and English; about
   a third short (under 300 words), a third medium, a third long (over 1,500 words). The file
   name is free. These files never enter the repository.
2. **Download both candidates**: `plume read-aloud --download qwen3.5-4b-q4km` and
   `plume read-aloud --download gemma4-e2b-q4`. Neither turns the feature on in the app.
3. **Run**: `plume read-aloud --eval <eval folder>/selections --engines
   qwen3.5-4b-q4km,gemma4-e2b-q4 --out <eval folder>/results.json`.
   For each file and each engine, it records the summary (length "automatic", language "same
   as the text"), cold and warm timings (load, reading the input, first sentence, total), and
   whether the input was truncated. It prints progress and how long is left.
4. **Judge**: open `bench/read-aloud-eval/judge.html` in a browser and pick `results.json`. For
   each selection, the page shows the source text and the two summaries side by side, labelled
   A and B in a random order per selection (the engine names stay hidden until the end). For
   each summary, tick: main point kept, nothing invented, right language, right length; then
   choose a preference (A, B, or equal) and an optional note. Progress is saved in the browser,
   so the judging can be spread over several sittings; the random A/B order is saved with it,
   so a reload never swaps the labels of a judged selection.
5. **Read the verdict**: once every selection is judged, the page reveals which engine was A
   or B and shows, per engine and per length class, the share of summaries passing each
   criterion, the preferences, and the median timings. **Export** downloads `verdicts.json`
   (a page opened from a file cannot write next to the results; move it there by hand).
6. **Decide**:
   - both acceptable → both ship, and the recommendation depends on the Mac (below);
   - one clearly worse → only the other ships;
   - neither acceptable → the prompt is revised and the eval re-run (step 3 onwards), or
     another model is tried (one catalog entry).

"Acceptable" means, as a starting point to adjust after seeing the results: at least 90% of
summaries keep the main point and invent nothing, and at least 95% respect the language.

## User experience

### Installing

Settings › Local AI gets a new block, "Read the selection aloud". **Nothing is downloaded until
the user asks, and nothing is deleted until the user asks.**

- **Voice** (162 MB, licence OpenRAIL++): **Download** installs it and enables "Read aloud".
  Once installed: the voice choice (F1 or M2) and **Delete**.
- **Summary models** (optional, need the voice): the catalog's models, each with name, size,
  licence, a one-line description ("Faster", "More accurate"), and a **Recommended** badge on
  one of them. Each model has **Download**; once downloaded, **Use** (one is active) and
  **Delete**. Several models can be kept; the block shows the total space used.
- Downloading a summary model when the voice is missing downloads the voice too, and says so.
- Every download asks for confirmation with its size: "Downloads N GB. Nothing leaves your
  Mac." For a summary model on a Mac with less than 16 GB of memory, it adds: "This Mac has
  N GB of memory: other apps may slow down while a summary is being written."
- Download progress shows next to the item in Settings, with **Cancel download**. If the user triggers a read meanwhile, the island shows "Downloading… x%"
  with **stop**, which ends only that waiting read; the download goes on. **Cancel download**
  moves a waiting read back to idle. The item shows as downloading (its buttons disabled) until
  the cancelled task has finished deleting its leftovers and released the lock.
- A summary model whose download failed or was interrupted shows as **Paused, N MB** (and the
  error, if it failed) with **Resume** (which continues from the `.partial`; it is the Retry
  of a failed download) and **Delete**; its `.partial` counts in the total space used. The
  voice cannot resume (its incomplete folder is deleted at the failure): it shows **Failed**
  with **Retry**, which restarts it from zero, and **Delete**, which clears
  `readAloudPendingDownload` and reloads the shortcuts.
- During an engine download that brings the voice, the voice counts as installed as soon as its
  completion marker is written: any waiting read whose items are now all installed starts then
  (a word-for-word read, or a summary on an engine already in use), and the island shows the
  voice's share of the progress meanwhile.
- A failure during the voice part of an engine download belongs to the engine: the engine shows
  `paused(0 bytes, message)` and its Resume brings the voice first; the voice shows `absent`
  (its incomplete folder is deleted), with Download disabled while `readAloudPendingDownload`
  names that engine.
- **What a read needs** (one definition, used by the shortcuts, the waiting rule and the
  failure rule): a word-for-word read needs the voice; a summary needs the voice and an engine.
  The voice is *pending* when `readAloudPendingDownload` is `voice`, or names an engine while
  the voice is not installed (that download brings it). An engine is *pending* when the key
  names it and no engine is in use. A read whose needed item is pending waits **only while
  that download is running**; if it is not running (it failed in this launch, or it was not
  resumed at launch), the read goes to `failed` with the error and Retry, which resumes the
  pending download (an engine's Resume brings the voice first). No read ever waits for a
  download that nothing will start.
- **Delete** asks for confirmation. Deleting the item named by `readAloudPendingDownload` (a
  paused download) clears that key, so nothing resumes it at the next launch. Deleting the active summary model leaves summaries off
  until another downloaded model is chosen with **Use**. Deleting the voice turns both modes
  off; summary models are kept. Deleting the voice or the model in use unloads it if it is
  loaded (at any time, not only during a read: "Keep the models loaded" may hold it), and stops
  a read that uses it. **Use** on another engine unloads the previous one and stops a summary
  in progress; a word-for-word read goes on.
- The shortcuts are reloaded whenever what is installed or pending changes (see "Shortcuts and
  triggers"); `HotkeyManager.reload()` today runs only when shortcuts change.
- While a download runs, the other Download, Delete and Use buttons are disabled (one download
  or deletion at a time, see the lock in `ReadAloudModels`).

**The recommendation adapts to the Mac**, from its chip and memory, read when the list is shown
(no speed test): the more accurate model on a Pro, Max or Ultra chip or an M5 or later, with at
least 16 GB of memory; the faster one otherwise (base M1 to M4, or less than 16 GB). If the
eval keeps one model only, it is the recommendation everywhere.

Rows under the block: the two shortcuts, summary length and language, speed, "Show the text
while reading", "Keep the models loaded". Both shortcuts are unassigned by default, like
"Transform the selection", and are also listed in Settings › Shortcuts.

### Using it

1. Select text, press **Read aloud** or **Summarize aloud**. The selection is read at once,
   while the original app is still in front (same as Transform).
2. For a summary, the island shows:
   - "Loading the model…" when the model is not in memory;
   - "Reading the text… 40%" with the remaining time when the model needs more than about 2 s
     to read the selection (progress comes from the batches llama.cpp processes);
   - "Summarizing…" while the first sentence is written.
   For word-for-word reading, the first sentence plays almost at once.
3. While playing, the island shows "Reading" with a speaker icon and the progress ("2/4", or
   "12/180" for a long text).
4. Hovering the island shows: **stop**, pause/resume, previous and next sentence, replay from
   the start, − and + for speed (saved as the new speed setting), **Show text**, and, for a
   summary, **Read the full text** (also offered while the model reads the text and in the
   "Finished" state).
5. **Read the full text** stops the summary and reads the same selection word for word.
6. **Show text** pins open a text panel under the island: the summary, or the full text for
   word-for-word reading, with the sentence being read highlighted and kept in view, and a Copy
   button. Unlike the hover controls, it stays open when the pointer leaves, until it is closed
   or the read ends. It shows about six lines and scrolls; the island's window and its
   clickable area grow to include it, so Copy and the scroll receive clicks. The setting "Show
   the text while reading" opens it by default.
7. **Pressing a shortcut always starts a new read** of the current selection, replacing the one
   in progress (the other shortcut switches mode the same way). To stop: **Esc**, **stop** on
   the island, or `plume stop` / `plume://stop` / the Remote `stop` (which stop the read when Plume
   is not recording, so Raycast, Shortcuts or a Stream Deck can stop it without the mouse).
   - Esc is a system-wide key: holding it for a whole read would break it in every other app
     (Plume already releases it outside dictations for that reason). So Esc stops a read only
     from "Loading the model…" until the first sound (not during a download, which can last
     minutes), and afterwards while the pointer is on the island or the text panel is open.
     With "Show the text while reading" on, that is the whole read; the setting's help text
     says so. The help text of both shortcuts says that a read is stopped from the island (or
     with Esc while hovering it).
   - During a summary, a stop takes effect within one input batch (≤ ~2 s on an M2, see
     `LlamaSummaryService`).
8. When the read ends, the island stays in a "Finished" state for 8 seconds with Replay and
   Show text, then closes. After that, nothing of the read is kept.

### Edge cases

| Situation | Island | Then |
|---|---|---|
| Empty selection, or the app does not expose it | "Select some text first" | Nothing starts; a read in progress continues. |
| Voice not installed | Neither shortcut is registered. | |
| No summary model in use | "Summarize aloud" is not registered. | |
| An item a read needs is pending (see "What a read needs") | "Downloading… x%" while that download runs; otherwise the error, with Retry | A read waits only for a running download and starts once all its items are installed, unless stopped; a read that needs nothing pending starts at once. |
| The session is busy (`session.isBusy`: recording, or processing a dictation, a transform, a restore or a meeting transcript) | Both shortcuts and the read URLs are ignored. | A read never starts without an island to show it and stop it. |
| A dictation starts while reading | The read stops, the dictation starts. | |
| A restore (shortcut, URL or window) while reading | The read stops, the restore runs. | Same as a dictation: the session's processing takes the island. |
| Summary of a selection over the input budget (context minus the output reserve, ~15,000 tokens) | "Summarizing the beginning (about N words)" | The text is cut at the last sentence that fits. |
| Word-for-word reading of a very long selection | | No limit: sentences are synthesized a few ahead of playback. |

## Architecture

```
Read aloud:
shortcut ─▶ Paster.selectedText() ─▶ SpokenText ─▶ SentenceSplitter ─▶ NemoTextNormalizer
          ─▶ Voice ─▶ ReadAloudPlayer (AVAudioEngine + AVAudioUnitTimePitch)

Summarize aloud:
shortcut ─▶ Paster.selectedText() ─▶ SummaryPrompt (messages) ─▶ SummaryService (token stream)
          ─▶ SummaryCleaner ─▶ SentenceSplitter ─▶ NemoTextNormalizer ─▶ Voice ─▶ ReadAloudPlayer
```

Everything that can be tested without a model or the UI lives in PlumeKit. The LLM, the voice
and the player sit behind small protocols so the controller can be tested with fakes. The two
modes share everything after the sentences are produced.

### Swapping models and services

The owner does not want Plume tied to Qwen, or to any one model or runtime. Three layers keep
each choice replaceable.

**1. The prompt is messages, not text.** `SummaryPrompt` produces a model-neutral request:

```swift
struct SummaryRequest: Sendable {
    let system: String
    let user: String
    let maxSentences: Int
    let language: String        // "fr" or "en"
    let truncated: Bool
}
```

**2. Services.** A `SummaryService` turns a request into a stream of events. v1 ships one,
`LlamaSummaryService`. Apple Intelligence (`LocalAI`), a cloud API or MLX would each be one more
type conforming to the protocol, with no change to the prompt, the cleaner, the splitter, the
voice or the controller.

```swift
protocol SummaryService: Sendable {
    var isLoaded: Bool { get async }
    /// Loads the model (already downloaded); the first load may compile GPU kernels.
    func load() async throws
    /// Tokens the service can take as input, and a counter in its own tokens.
    var inputBudget: Int { get async }
    func countTokens(_ text: String) async throws -> Int
    func stream(_ request: SummaryRequest) -> AsyncThrowingStream<SummaryEvent, Error>
    func unload() async
}

enum SummaryEvent: Sendable {
    case readingInput(fraction: Double)   // prompt processing progress
    case text(String)                     // a decoded piece of the summary
}
```

The prompt needs the token counter, so the controller loads the service before building the
request.

**3. One engine catalog.** What the user picks is an **engine entry**; its `kind` says which
service runs it, and a factory builds the service.

```swift
struct SummaryEngineEntry: Sendable, Identifiable {
    let id: String                // "qwen3.5-4b-q4km", stored in settings
    let name: String              // "Qwen3.5 4B"
    let blurb: String             // "More accurate", shown in Settings (localized)
    let tier: Tier                // .accurate or .fast, drives the recommendation
    let licence: License          // name + URL
    let kind: Kind
    enum Kind: Sendable {
        case llama(LlamaModelSpec)
        // later: .appleIntelligence, .cloud(…), .mlx(…)
    }
}

struct LlamaModelSpec: Sendable {
    let download: ModelDownload   // repo, pinned revision, file name, byte size, SHA-256
    let promptFormat: PromptFormat
    let contextTokens: Int        // 16,384
    let temperature: Float        // 0.3; other sampling values come from the GGUF (see below)
    let reasoningMarkers: [ReasoningMarkers]  // e.g. Qwen <think>…</think>,
                                              // Gemma 4 <|channel>thought … <channel|>
}

struct ReasoningMarkers: Sendable { let open: String; let close: String }

enum PromptFormat: Sendable {
    /// The template embedded in the GGUF, applied by llama.cpp's built-in formatter.
    /// Only the families llama.cpp recognises (ChatML/Qwen, Gemma 1–3, Mistral, Llama 3, Phi…).
    case embedded(assistantPrefix: String)
    /// An explicit format with {system} and {user} placeholders, for models whose template
    /// llama.cpp does not recognise (Gemma 4: verified unrecognised).
    case explicit(template: String)
}
```

- llama.cpp's C formatter does not run Jinja templates; it matches the template against known
  families. Qwen3.5 is recognised as ChatML; Gemma 4 is not. `promptFormat` keeps adding a
  model a data change either way.
- Qwen3.5 uses `.embedded(assistantPrefix: "<think>\n\n</think>\n\n")`: the empty think block
  turns its reasoning off, exactly as its own template does when `enable_thinking` is false.
- Gemma 4 E2B uses `.explicit(…)` with its turn markers (`<|turn>system` … `<turn|>`); the
  exact string is copied from its official template during PR 1 and checked by the catalog
  test. Its reasoning, if any, is wrapped in `<|channel>thought` … `<channel|>`: those go in its
  `reasoningMarkers`.

The engine in use is stored by id (`readAloudEngine`). An id that is no longer in the catalog,
or whose file is not on disk, resolves to "no model in use": summaries are off and Settings
offers the downloaded and available models, so removing a model from the catalog never breaks
a user's settings.

The voice follows the same pattern: `Voice` is a protocol, and `VoiceEntry` (id, engine, voice
name, languages) lists `supertonic3-f1` and `supertonic3-m2` in v1.

### PlumeKit

**`SpokenText`** (pure, word-for-word mode)

- Prepares a selection for speech: URLs become "link" (or "lien" in French), e-mail addresses
  are read as written, markdown and code markers are removed (headings, bullets, emphasis,
  backticks; fenced code blocks become "code block skipped"), list items and line breaks
  without punctuation become sentence ends, whitespace is collapsed.
- Language: `NLLanguageRecognizer` on the whole selection; used as is if Supertonic-3 supports
  it (31 languages), otherwise the interface language. The normalizer runs only for languages
  `NemoTextNormalizer` also supports (French, English, Spanish, German, Japanese, Hindi); other
  languages are spoken without it.

**`SummaryPrompt`** (pure)

- Input: the selection, the length setting, the language setting, the interface language, the
  service's token counter and input budget.
- Language: "same as the text" uses `NLLanguageRecognizer`; if detection fails or returns a
  language other than French or English, it falls back to the interface language.
- Sentence budget from the selection's word count:

  | Words | Short | Automatic | Detailed |
  |---|---|---|---|
  | < 300 | 1 | 2 | 3 |
  | 300–1,500 | 2 | 4 | 6 |
  | > 1,500 | 3 | 6 | 8 |

- System instructions: the ones validated in the bench, in the target language.
- Truncation: if the selection is over the input budget, it is cut at the last sentence end
  that fits, and `truncated` is set.

**`LlamaSummaryService`** (conforms to `SummaryService`)

- Built from a `SummaryEngineEntry` of kind `.llama`. Loads the GGUF with all layers on the GPU
  (Metal), the entry's context size.
- **Threading.** All llama.cpp calls run on one dedicated serial thread (not Swift's
  cooperative pool), because `llama_decode` blocks for seconds. The service's async methods hop
  onto that thread and back.
- **Prompt.** `.embedded`: reads the GGUF's template with `llama_model_chat_template`; if it is
  NULL, `load` fails with "This model has no chat template" (llama.cpp would otherwise silently
  use ChatML). Renders with `llama_chat_apply_template(add_ass: true)` and appends the prefix; a
  return of −1 fails with "Unsupported chat template". `.explicit`: substitutes the
  placeholders.
- **Trimming.** The system text and the selection are trimmed of surrounding whitespace before
  formatting, as both official templates do (`| trim`) and llama.cpp's C formatter does not.
- **Tokenization.** The prompt is rendered with a unique sentinel string in place of the
  selection, then split on it. The template parts are tokenized with `parse_special = true`, the
  selection with `parse_special = false` (so a selection containing `<|im_end|>` stays plain
  text). `add_special = true` only for the first piece, so the model adds its BOS token itself if
  it uses one (Gemma does, Qwen does not); `.explicit` templates must not contain a literal BOS
  token (checked by the catalog test).
- **Reading the input** in batches of 512 tokens (`n_batch = n_ubatch = 512`; 512 is already
  llama.cpp's default `n_ubatch`, so speed is unchanged), emitting `readingInput(fraction)` after
  each batch and checking cancellation between batches. A batch in progress cannot be
  interrupted: llama.cpp's abort callback only works on the CPU, not on Metal. Worst case, a stop
  takes effect after one batch: ~2 s on an M2, ~0.5 s on the M5.
- **Context settings:** `swa_full = false` (llama.cpp's C default is true, which would allocate
  a full-size sliding-window cache for Gemma; `llama-server`, used in the bench, sets false),
  flash attention on automatic. `llama_memory_clear` at the start of every read: Qwen3.5 keeps
  recurrent state, and a stopped read can leave it half-written.
- **Sampling** (reproduces what the bench ran): the chain top-k → top-p → min-p → temperature →
  random draw, repetition penalty off. Values: llama-server's defaults (top-k 40, top-p 0.95,
  min-p 0.05), replaced by the GGUF's `general.sampling.top_k`, `top_p` and `min_p` when present
  (Gemma 4: top-k 64; read with `llama_model_meta_val_str`); temperature is always the entry's
  (0.3), whatever the GGUF says. Other `general.sampling.*` keys (sequence, penalties, mirostat,
  xtc) are ignored; the two candidates set none of them.
- **Generation** stops on end-of-generation, a token cap of 60 tokens per budgeted sentence +
  100, or cancellation.
- **Detokenization** renders special tokens as text (`llama_token_to_piece(…, special: true)`),
  so reasoning markers reach the cleaner instead of vanishing and leaving the thoughts to be
  spoken. Bytes are buffered and only complete UTF-8 characters are emitted in `.text` (a token
  can end in the middle of a multi-byte character, as in "é").
- `llama_backend_init` once per process; llama.cpp's own log goes through `llama_log_set` into
  Plume's log (sizes and timings only).
- `unload()` frees the model and context; it waits for any decode to stop first.

**`SummaryCleaner`** (pure)

- Removes the entry's reasoning blocks (its `reasoningMarkers`, including a block still open at
  the end of the stream). Markers can arrive split across pieces (Gemma 4's `<|channel>thought`
  spans two tokens), so the cleaner holds back any tail that could be the start of a marker; a
  close marker without a matching open is dropped too. It also removes any remaining
  control-token text, markdown markup (headings, bullets, bold, italics, code fences) and
  leading labels like "Summary:".
- Ends the stream once the sentence budget + 2 is reached.
- An empty result raises "Couldn't summarize this text."

**`SentenceSplitter`** (pure, incremental, shared by both modes)

- Fed text pieces, emits complete sentences as soon as they end.
- Does not split on decimals ("4,5", "3.2"), common abbreviations ("M.", "Mme", "Dr", "e.g.",
  "i.e.", "etc."), initials, or ellipses inside a sentence.
- Sentence ends: `.`, `!`, `?`, `…`, and the full-width and other-script ends `。`, `！`, `？`,
  `।`, `؟`.
- A sentence longer than about 300 characters (no punctuation for a long stretch, common in
  copied text) is split at the nearest comma, semicolon or space, or cut at 300 characters if
  there is none (Japanese has no spaces), so synthesis never waits on a huge piece.
- An option caps the **first** sentence at about 70 characters, cut the same way (Supertonic
  synthesizes in 70-character chunks): word-for-word reading uses it so the first sound comes
  fast.
- Flushes the remaining text at the end of the stream.

**`Voice` and `SupertonicVoice`**

```swift
protocol Voice: Sendable {
    var sampleRate: Double { get }
    func load() async throws
    func speak(_ sentence: String, language: String) async throws -> [Float]  // mono
    func unload() async
}
```

- `SupertonicVoice` is built from a `VoiceEntry`. It normalizes the sentence when the language
  allows it (see `SpokenText`), then synthesizes with `Supertonic3Manager` at `speed: 1.0`
  (Supertonic's own default is 1.05), 44.1 kHz.
- The manager is created with `directory: <support directory>/Models` (FluidAudio adds
  `supertonic-3/` itself), so Plume owns the files: Delete removes them, and `PLUME_SUPPORT`
  isolates trials. (FluidAudio's default on macOS is `~/.cache/fluidaudio`, outside Plume's
  control.)
- One constant fixes the voice variant for both the download and the manager:
  `vectorEstimator: .aneBucketed(.int4)` and `veVariant: "ane-int4"` (the variant the bench
  measured; FluidAudio's `downloadVariant` is internal, so the string is repeated, and a test
  checks that it equals `"ane-" + Supertonic3Quantization.int4.rawValue`, the only part of
  FluidAudio's internal naming that is public). `load()` checks that the files and the
  completion marker exist before calling `initialize()`, and reads the voice style with
  `Supertonic3VoiceStyle.load(from:)` (not `loadVoiceStyle`, which downloads a missing file), so
  loading can never start a download.
- The voice files are pinned: Plume sets
  `ModelRegistry.revisionOverrides["FluidInference/supertonic-3-coreml"]` to a fixed commit
  once at process start (app launch and command-line entry), before any FluidAudio call: the
  dictionary is read unsynchronized by every FluidAudio download, including the speech model's,
  so it must never be written while one runs. (FluidAudio otherwise fetches `main`.)
- Speed is applied by the player, never here.

**`ReadAloudModels`** (downloads and deletions)

- Two kinds of items: the voice, and each summary engine's model file. Each is downloaded,
  used and deleted on its own; downloading an engine first downloads the voice if it is
  missing, with one progress weighted by bytes.
- Model file: fetched from `https://huggingface.co/<repo>/resolve/<revision>/<file>` (the
  pinned revision), re-resolved on each attempt because the CDN's redirect URLs are signed and
  expire. Written to `<support directory>/Models/<file>.partial` with HTTP `Range` requests to
  resume; a `200` reply instead of `206` (range ignored) restarts from zero.
- Before starting: free disk space ≥ total size + 10%.
- At the end: size and SHA-256 checked; a mismatch deletes the file and reports a failure (the
  engine shows `paused(0 bytes, message)` with Resume). Otherwise the `.partial` is renamed.
- Voice: `Supertonic3ResourceDownloader.ensureModels(directory:veVariant: "ane-int4",
  progressHandler:)`, then `downloadVoiceStyle` for F1 and M2 (a few kB each). `ensureModels`
  only checks that files exist, and an interrupted bundle can leave `weight.bin.partial` behind
  and still pass. So Plume writes a `.complete` marker in the voice folder once all three calls
  succeed; "installed" requires the marker. An unmarked folder is deleted at the failure or the
  Cancel, and **every voice download, once it holds the lock, starts by deleting an unmarked folder** (Download, Retry,
  an engine's Resume, the launch resume, `--download`), so a bundle left by an interrupted
  command line can never be marked complete.
- One lock (`flock` on `<support directory>/Models/.download.lock`) covers any download or
  deletion, so the app and the command line never write the same files at once. It is taken
  without waiting (`LOCK_NB`): a second taker fails with "A download is already running".
  Delete and the resume at launch take it themselves. **Cancel does not**: it cancels the
  running download task, which deletes what it left (the `.partial`, or the unmarked voice
  folder) while it still holds the lock, then releases it. Quitting the app or interrupting the
  command line kills the process instead, so the `.partial` stays for a resume.
- Settings disables Download and Delete while the app's own download runs. A download started
  by the command line (`--download`, for the eval) holds the lock too; the app cannot see it,
  so Settings then shows "A download is already running" when the user tries.
- **Deletion only on request.** Nothing is deleted except by the user's Delete (one item),
  Cancel (the item being downloaded), and the incomplete files of a failed download (a file
  failing its checksum, an unmarked voice folder at the failure or at the start of any voice
  download, a `.mismatch` marker at Cancel). Downloading an engine never deletes another.
- The command line's `--download` writes neither `readAloudEngine` nor
  `readAloudPendingDownload`: downloading for the quality eval never turns anything on in the
  app.
- **Lifecycle.** The item being downloaded from the app is stored in `readAloudPendingDownload`
  (`voice` or an engine id). Quitting mid-download keeps the `.partial`; at the next launch, if
  a pending download is set, it resumes automatically and the island shows nothing until a read
  is requested. When an engine download completes and no engine is in use, `readAloudEngine`
  takes its id; the pending value is cleared.
- **Cancel** clears `readAloudPendingDownload` (a cancelled download is never resumed) and
  re-registers the shortcuts. **A failure** keeps it, so Resume/Retry and the next launch
  continue; each launch tries once (no retry loop within a launch), except after a checksum
  mismatch, which is never resumed automatically (a wrong pin would otherwise re-download
  3 GB at every launch): only the user's Resume retries it. The mismatch is remembered by a
  marker file next to the model (`<file>.mismatch`), written by `ReadAloudModels` when the
  check fails, holding the error message (so the paused item shows its reason after a
  relaunch). It is removed when a download of that file starts (and by Delete or Cancel), and
  written again only on a new mismatch: a later failure of another kind resumes at launch as
  usual. A read waiting for that download
  moves to `failed` with the error and Retry; a shortcut pressed for a read that needs that
  pending item (see "What a read needs") goes to `failed` with Retry too. Retry, from
  the island or from Settings, restarts the download and, if a read was waiting, waits again
  with the same selection.
- Status per item: `absent`, `downloading(fraction)`, `installed`, `paused(bytes, message?)`
  (summary models), `failed(message)` (the voice).

**Recommendation** (pure): `recommendedEngine(chip:memoryGB:catalog:)` returns the `.accurate`
entry on (Pro, Max, Ultra, or M5 and later) with ≥ 16 GB, the `.fast` entry otherwise, or the
only entry if there is one. The chip name comes from `machdep.cpu.brand_string`, the memory
from `ProcessInfo.physicalMemory`; both are passed in, so the function is tested without
hardware.

### App

**`ReadAloudPlayer`**

- One `AVAudioEngine`: player node → `AVAudioUnitTimePitch` (rate = speed) → main mixer.
- `enqueue(samples, sentenceIndex)` schedules one sentence. It keeps only the sentences queued
  ahead and the one playing; previous sentences, Replay and "previous sentence" are
  re-synthesized from the text (fast enough at ~90× real time), so a long word-for-word read
  never holds minutes of audio in memory.
- `pause()`, `resume()`, `stop()`, `setRate(_:)` (live); skipping and replay are driven by the
  controller.
- Reports which sentence is playing and when the queue empties after the last sentence.
- On an audio configuration change (headphones unplugged, Bluetooth), pauses instead of
  continuing on another output.

**`ReadAloudController`** (`@MainActor`)

- Owns one read at a time, in one cancellable task:
  - read aloud: selection → load voice → `SpokenText` → splitter → voice → player;
  - summarize aloud: selection → load service and voice → prompt → stream → cleaner → splitter
    → voice → player.
- Keeps the read's sentences (text only) for the text panel, skipping, Replay and the 8-second
  "Finished" state; drops them afterwards.
- Synthesizes up to three sentences ahead of playback; skipping cancels what is queued and
  synthesizes from the new position.
- **Read the full text** (summary mode, from loading to "Finished", see the Island table): cancels the summary
  and starts a read-aloud of the same selection, kept in memory for the duration of the read.
- Deleting the voice or the engine in use, or **Use** on another engine, during a read stops
  the read and unloads the affected service or voice.
- A sentence that fails in the voice is skipped; if every sentence fails, the read fails.
- Publishes `ReadAloudState`: `idle`, `downloading(fraction)`, `loading`,
  `readingInput(fraction, remaining)`, `summarizing`, `reading(mode, index, count, paused)`,
  `finished(mode)`, `failed(message)`, plus the sentences.
- A shortcut during any state starts a new read of the current selection; an empty selection
  leaves the current read going and shows "Select some text first".
- One rule: a session phase change into `.recording` or `.processing` (a dictation, a meeting,
  a transform, a restore) stops the read, hooked in `session.onPhaseChanged` (AppDelegate.swift).
- Its own idle timer unloads the service and the voice after the "Keep the models loaded"
  delay (`SessionController.scheduleUnload` belongs to dictation).

**Island**

- Today the island renders only `SessionController.displayPhase`, and `.processing` already
  swaps its label for the speech model's loading state, so it is not reused.
- The island gets a combined state: while the session is recording or processing a dictation
  or meeting, the session takes the island; its other phases (`suggestion`, `done`, `failed`)
  show only when no read is active. Esc is armed for a read only while the read is what the
  island shows.
- New renderings, and the controls each state offers on hover (one table, the reference for
  PR 2):

  | State | Island shows | Hover controls |
  |---|---|---|
  | `downloading` (a read waits) | "Downloading… x%" | stop (ends the waiting read only) |
  | `loading` | "Loading the model…" | stop; Read the full text (summary) |
  | `readingInput` | "Reading the text… 40%", remaining time | stop; Read the full text (summary) |
  | `summarizing` | "Summarizing…" | stop; Read the full text |
  | `reading` | speaker icon, "2/4" | stop, pause/resume, previous/next, replay, −/+, Show text; Read the full text (summary) |
  | `finished` (8 s) | "Finished" | Replay, Show text; Read the full text (summary) |
  | `failed` | the error | Retry when the cause is a download |

  The selection is kept in memory from the shortcut until the "Finished" state ends (so Read
  the full text and Replay work during those 8 s), or, in a `failed` state caused by a
  download, until the read is stopped or the island hides (after 8 s, like "Finished"); a Retry
  keeps it for the new wait. Then it is dropped with the sentences. The pinned
  text panel shows the text with the highlighted sentence.
- Shortcut routing: `onPress`/`onRelease` today send every action except open and restore to
  `session.handlePress` (AppDelegate.swift); `readAloud` and `summarizeAloud` are routed to the
  controller instead.
- The cancel key (Esc by default): `updateCancelShortcut` (AppDelegate.swift) is the single
  place that decides, and it is recomputed on every session phase change. Its condition becomes
  "dictating, or a read is between loading and its first sound, or the pointer is on the island
  or the text panel is open during a read"; it is also recomputed on read-aloud state and hover
  changes. `onCancelShortcut` stops the read when no dictation is running.
- The text panel is a new pinned state of the island, separate from the hover controls
  (`pinnedControls`).
- `UIRender` gets demo states for each new rendering (`plume render … --demo`), as `AGENTS.md`
  requires for interface changes.

**Shortcuts and triggers**

- New `HotkeyAction.readAloud`, registered when the voice is installed or pending, and
  `HotkeyAction.summarizeAloud`, registered when the voice is installed or pending **and** an
  engine is in use or pending (see "What a read needs"). A read pressed while an item it needs
  is pending waits for that download while it runs, or goes to `failed` if it is not running. The shortcuts are
  reloaded whenever `readAloudPendingDownload` or `readAloudEngine` changes (download start,
  completion, Cancel, Use) and on Delete and on a download failure.
- `plume://read-aloud`, `plume://summarize-aloud`, and the Remote actions `read-aloud` and
  `summarize-aloud` start a read of the current selection, through the app, which has the
  permissions. (Not `toggle-*`: they always start, they never stop.) No Plume command sends them: they are for
  Raycast, Shortcuts or a Stream Deck, through the URL or the command channel. The command
  line's `plume read-aloud` is a different thing (it reads standard input); the guide says so.
- `stop` (Remote, `plume://stop`, `plume stop`) stops the read whenever a read is active and
  the session is not recording (a recording keeps its own `stop`); today it only reaches
  `session.stop()` (Remote.swift, AppDelegate.swift), which does nothing outside a recording.

**Command line** (`plume read-aloud`, in-process, no app needed)

- Reads text from stdin and speaks it word for word, or with `--summary`, summarizes it with
  the current settings and speaks the summary.
- `--text`: prints what would be spoken (the prepared text, or the summary) without speaking.
  `--json`: the same plus timings (load, reading the input, first sentence, total).
  `--engine <id>`: uses another downloaded engine.
- `--download voice|<engine id>`: downloads that item (with the lock); without it, the command
  never downloads, and fails with a message naming `--download` and Settings.
- `--eval <folder> --engines <id,id> --out <file>`: the quality eval run (see "Quality eval").
- No reading of the selection from the command line (it would read the terminal's own
  selection); the URL scheme does that.

**Doctor**: "Read aloud: voice installed / downloading x% / not installed", and one line per
downloaded summary model, marking the one in use.

## Settings

Through `PlumeSettings` and `SettingsModel`. New fields are optional when read from a backup.

| Key | Type | Default | In backup |
|---|---|---|---|
| `readAloudEngine` | engine id or empty | empty (no model in use) | **no**: the models are not on a restored Mac; the user downloads and chooses again |
| `readAloudPendingDownload` | `voice`, an engine id, or empty | empty | no (same reason) |
| `readAloudKeepLoaded` | string: `5min` / `30min` / `always`; absent = default | absent, which means 30 min with ≥ 16 GB of memory, 5 min below | yes, only when set: as a string key with no registered default, `SettingsBackup.snapshot` exports it only if the user chose a value, so a 24 GB Mac's backup does not impose 30 min on an 8 GB Mac |
| `readAloudShortcut` | Shortcut | none | yes |
| `summarizeAloudShortcut` | Shortcut | none | yes |
| `readAloudLength` | `short` / `automatic` / `detailed` | `automatic` | yes |
| `readAloudLanguage` | `sameAsText` / `interface` / `fr` / `en` (summaries only) | `sameAsText` | yes |
| `readAloudVoice` | voice id | `supertonic3-f1` | yes |
| `readAloudSpeed` | Double, 0.75…2.0, step 0.25 | 1.5 | yes |
| `readAloudShowText` | Bool | false | yes |

Read aloud is available when the voice is installed; summaries when, in addition,
`readAloudEngine` names a downloaded engine. All interface strings go through `tr("…")` with
their French translation in `L10nTable`.

## Privacy

- The selection, the summary and the audio are never written to disk.
- Plume's log records sizes, languages and timings for a read, never its text; llama.cpp's log
  is routed through the same filter.
- Nothing is sent anywhere; the only network access is the downloads from Hugging Face,
  started by the user.
- The eval's selections, results and verdicts stay in the owner's eval folder, outside the
  repository; the walkthrough uses a placeholder path.

## Testing

Everything runs with `./scripts/test.sh`, in seconds, with no model, no network and no audio
device:

- `SpokenText`: a table of inputs (URLs, e-mail addresses, markdown, fenced code, bullet lists,
  line breaks without punctuation) and the plain sentence closest to each, which must not
  change; language choice (supported, unsupported → interface language; normalizer only for
  its six languages shared with Supertonic).
- `SummaryPrompt`: word counts × length settings → sentence budget; language choice (detected
  French, detected English, undetected, other → interface language); truncation at a sentence
  end with a fake token counter; no model-specific markup in the request.
- `SentenceSplitter`: a table of tricky inputs ("4,5 %", "M. Dupont", "e.g.", "U.S.", "…",
  quotes, a sentence split across pieces, a 1,000-character run without punctuation, Japanese
  `。` and Hindi `।` ends, a 400-character Japanese run without spaces, the 70-character
  first-sentence cap) and the
  plain sentence closest to each, which must not change.
- `SummaryCleaner`: think blocks, markdown, labels, over-long output, empty output.
- Engine catalog (reasoning samples fed token by token, not as one string): unique ids; pinned
  40-character revisions; 64-character SHA-256; positive sizes; each `.explicit` template
  contains `{system}` and `{user}` and no literal BOS token; each `.embedded` entry renders a
  sample request through the same formatting code (with the template string stored in the
  test); an unknown id resolves to "no model in use"; for each entry, a sample output wrapped
  in its `reasoningMarkers` comes out of the cleaner without the reasoning; the voice variant
  string equals `"ane-" + Supertonic3Quantization.int4.rawValue`.
- Recommendation: a table of chips × memory → expected entry, including a one-entry catalog.
- Keep-loaded default: memory size passed in: ≥ 16 GB → 30 min, below → 5 min;
  `readAloudKeepLoaded` absent from a backup when unset, exported once set (in the style of
  `backupExportsEnglishValues`).
- `ReadAloudModels`: resume with `206`, restart on `200`, checksum mismatch, insufficient disk
  space, cancel, the lock held by another descriptor, downloading an engine installs the voice
  first, downloading a second engine keeps the first, Delete removes only its item, nothing is
  deleted otherwise, a failure during the voice part of an engine download leaves the voice
  absent (folder deleted) and the engine resumable, an unmarked voice folder left by an
  interrupted run is deleted before the next voice download, a checksum mismatch writes the
  `.mismatch` marker with its message (removed by success, Delete and Cancel); with a stub
  `URLProtocol` and temporary folders.
- "What a read needs" is a pure function of (voice installed, engine in use, pending key,
  pending download running): a table of cases, including a pending download not running at
  all (→ `failed` with Retry, never an endless wait), including a word-for-word read after an engine's voice
  part failed (→ `failed`, not a read without a voice), and a summary waiting on the voice
  only (engine in use, voice deleted, another engine downloading).
- `ReadAloudController` with a fake `SummaryService`, `Voice` and player: a shortcut during a
  read restarts with the new selection; an empty selection leaves the read going; Esc and stop
  stop; Read the full text switches mode on the same selection; previous/next and replay
  re-synthesize from the right sentence; a failing sentence is skipped, all failing → error;
  a session entering recording or processing (dictation, restore) stops the read; the state sequence for the island; a long read keeps at most
  the queued sentences' audio.
- Settings: the new keys in `SettingsBackup` and in `FixtureSamples.backup` (enforced by
  `SavedFormatTests.samplesCoverEveryValue`); `readAloudEngine` and `readAloudPendingDownload`
  excluded from the backup and listed in `settingsOutsideTheBackupKeepTheirName`; the backup
  fixture of the unreleased version (1.0.2, no tag) regenerated; French translations present;
  the two new shortcuts.
- Command line and Remote: `read-aloud` in `CLI.commands`, `read-aloud` and `summarize-aloud`
  in `RemoteTests`; `stop` reaches the read when the session is not recording (routing function tested
  with fakes). The "not installed" cases are tested on the
  in-process function behind the command, which takes the settings and the models folder as
  parameters (`PlumeSettings.shared` is not allowed in tests), not by launching the binary,
  which `AGENTS.md` allows only for read commands; it fails with the expected message and
  starts no download.
- Eval kit: `--eval` on two fake engines writes the expected `results.json` shape; the judge
  page's summary computation is a plain function covered by a small table (run with the page's
  own script in the test, or kept trivial enough to check by hand; decided in the plan).

Real models are exercised by hand: the quality eval, then a PR checklist (French and English
selections in both modes, a long word-for-word read, Esc during input reading, stop, pause,
skip, speed, Show text, Read the full text, unplugging headphones, quitting mid-download and
resuming, deleting a model in use).

## Packaging and release

- `Package.swift`: a `binaryTarget` for `llama.xcframework` from a pinned llama.cpp release URL
  with its checksum, used by PlumeKit. (The zip nests the framework under `build-apple/`; SwiftPM
  accepts it, verified.)
- `scripts/assemble.sh` (called by both `build.sh` and `release.sh`, unsigned): copy
  `llama.framework` into `Contents/Frameworks` next to Sparkle, thinned to arm64 with
  `lipo -thin`. The app already has the `@executable_path/../Frameworks` rpath.
- Signing, like Sparkle's: `build.sh` signs it with the local identity, `release.sh` with the
  release identity (hardened runtime, timestamp), before signing the app.
- The llama.cpp version is pinned to the one the bench used (b11461) unless the quality eval
  runs on a newer one.
- `Resources/LICENSES.md`: llama.cpp's MIT notice. Model and voice licences (Apache 2.0,
  OpenRAIL++) are linked from Settings.
- App size: about +12 MB.

## Documentation

- README: both modes in "What it does", the optional downloads in "Privacy, concretely".
- `docs/GUIDE.md`: a "Read the selection aloud" section.
- `docs/PLAN.md`: rows for the summary engine (llama.cpp, models chosen by the user; MLX
  rejected: Xcode, Apple-only) and the voice (Supertonic-3 + number normalizer).
- `docs/DEVELOPMENT.md`: the new files.
- `CHANGELOG.md`: one line per PR.

## Delivery

1. **PlumeKit pipeline, command line and eval kit**: `SpokenText`, prompt, cleaner, splitter,
   `SummaryService` + `LlamaSummaryService`, engine catalog, `Voice` + `SupertonicVoice`,
   `ReadAloudModels`, a minimal player (play and stop), **all the settings keys**
   (`PlumeSettings`, the backup lists, `FixtureSamples.backup`, the regenerated 1.0.2 fixture,
   `settingsOutsideTheBackupKeepTheirName`; the command line needs them), the llama.cpp
   dependency and packaging, `plume read-aloud` with all its options, and
   `bench/read-aloud-eval/` (judge page and walkthrough). **The quality eval runs on this PR**,
   and its outcome fixes the catalog before merging.
2. **App**: full `ReadAloudPlayer`, `ReadAloudController`, island states and controls, both
   shortcuts, URLs and Remote actions, render demo states.
3. **Settings UI and docs**: the block in Settings (voice, model list with the recommendation,
   download, use, delete, and the options), doctor, documentation. No new settings keys.

## Risks

- **Projections, not measurements, for older Macs.** The M2 target rests on public ratios; the
  first users on older Macs will tell. The `--json` timings make a real measurement one command
  away.
- **llama.cpp C API**: it changes between releases; the version is pinned and updated on
  purpose.
- **Prompt formats**: the in-process formatter is not the bench's Jinja path; the quality eval
  runs on the in-process path to catch differences.
- **The 70-character first-sentence cap** applies before number normalization, which lengthens
  text ("1786" → "mille sept cent quatre-vingt-six"), and Supertonic's Japanese and Korean chunks
  are 57 characters: the first sentence can still take two chunks. Accepted; measured on the M5.
- **Greek questions** end with `;`, which the splitter does not treat as a sentence end (it is
  a clause mark elsewhere); Greek sentences run longer and are cut at 300 characters.
- **English words in French text** (e.g. "bugs") are sometimes misread by the voice; word for
  word, this matters more than in summaries.
- **Languages beyond French and English** in word-for-word reading were not listened to; those
  outside the normalizer's six are spoken without number normalization.
- **Supertonic-3's OpenRAIL++ licence** carries use restrictions that pass on to users; check the
  wording to show in Settings.
