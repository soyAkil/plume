# Plume — technical choices and roadmap

## The idea

A free alternative to Superwhisper, designed from scratch: dictation by shortcut, a
state-of-the-art local model, speaker separation, live transcription, two sources (microphone +
system audio), a central library an AI can read, text pasted into the active field, a minimal
interface.

## Technical choices

| Topic | Choice | Why |
|---|---|---|
| Form | Native macOS app (Swift, menu bar) | Light, integrated, no runtime to install. |
| Tooling | SwiftPM only | Everything builds with the Command Line Tools, without Xcode. |
| Engine | FluidAudio 0.17.5 (CoreML, Neural Engine) | The only Swift stack that combines transcription, live text and diarization, and builds without Xcode (MLX requires Xcode). |
| Model | Parakeet Ultra (September 2026) | Best accuracy / speed trade-off for French that runs locally: FLEURS fr ≈ 4.3% error, ~150× real time. Cohere Transcribe is slightly more accurate but 70× slower on CoreML; Whisper large-v3-turbo trails behind. |
| Live text | Sliding window re-transcribed ~2 times a second | Same model as the final result, for 6 to 7% of real time. Validated text freezes at sentence ends. |
| Speakers | Offline diarization (pyannote community-1) at the end of the recording, per channel | More reliable than streaming diarization. The microphone and the system audio are processed separately, then merged by timestamp. |
| "Me" | Voiceprint learned from dictations | A dictation only contains the user's voice: free training data. |
| System audio | Core Audio process tap | Only asks for the "system audio" permission, not screen recording. |
| Shortcuts | `⌃⇧` modifier chord (the same as Superwhisper), read by polling the keyboard state | No special permission; doesn't fire on `⌃⇧`+key. Quit Superwhisper to avoid a double trigger. |
| Interface | An island that comes out of the notch + a single window (home, history, vocabulary, settings) | Discreet while dictating, everything in one place afterwards. |
| Echo in meetings | Neural echo cancellation (LocalVQE) on the microphone, with the system audio as reference, only when echo is detected | Without headphones, remote voices came out doubled and drowned out the local voice. |
| Speaker turns | Voice changes snapped to the nearest pause or sentence end; no merging of "similar" voices | Over-eager merging mixes up two people with close voices, and boundaries landed a word or two off. |
| Meeting mode | Switch on the island, mid-recording | You don't always know in advance that you're in a meeting; the system audio channel starts at the switch. |
| Library | `~/Plume` folder: Markdown + JSON + audio | Readable by a human, by `grep`, by any AI; no database. |
| AI access | Folder, `plume` command, MCP server | From the most universal to the most integrated. |
| Signing | Self-signed certificate in a dedicated keychain (until a Developer ID certificate) | macOS permissions survive rebuilds. |
| Distribution | Disk image on GitHub releases, Sparkle updates | A single link, and updates arrive on their own (see `docs/RELEASING.md`). |
| Formatting | Deterministic chain (clean-up → voice commands → vocabulary → style → insertion), AI after and optional | Competitors' number 1 complaint: an AI that changes words or numbers. The raw text always stays in the history. |
| Local AI | Apple Intelligence language model (FoundationModels), on device | No dependency, no account, nothing is sent. 4,096-token window: long meetings are summarized in chunks, then merged. |
| Profiles | One rule per application (style, Return, AI, typing), recognized in the foreground | Having to configure "modes" is the number 2 complaint about Superwhisper; here it is a list, and nothing to pick before talking. |
| Detected meeting | List of Core Audio processes reading an input (`kAudioHardwarePropertyProcessObjectList`) | Without listening: only "who holds the microphone" is read. A known video call triggers an offer on the island. |
| Pause | The microphone really closes (orange light off), the missing silence is filled in on resume | Requested for two years at Superwhisper (196 votes) without being delivered. |
| Sound muted while dictating | Mute setting of the default output (Core Audio), not MediaRemote | MediaRemote is private and broken since macOS 15.4; the mute is restored without remembering anything. |
| Insertion | Reading the active field through accessibility (`AXSelectedTextRange`, `AXStringForRange`) | Native apps expose it; web or Electron apps often don't, so Plume pastes as is. |
| Read aloud: summary | llama.cpp (official XCFramework, in process), GGUF models chosen and downloaded by the user (Qwen3.5-4B, Gemma 4 E2B) | Builds without Xcode and runs on every platform a port could target; MLX reads prompts ~30% faster but needs Xcode and only runs on Apple hardware. |
| Read aloud: voice | Supertonic-3 (FluidAudio), F1 or M2, numbers spelled out by NeMo's normalizer first, speed applied by a pitch-preserving time-stretch | Picked by ear among four engines at 1.5×; ~90× real time; one 162 MB model for 31 languages. |

## Roadmap

1. **Native iOS app** with the same engine embedded (PlumeKit is already separate from the
   interface, and FluidAudio runs on iOS 17+). Needs Xcode and an Apple developer account.
   Content: recording, on-phone transcription, history, a "Dictate" action for the Action
   button.
2. **Acoustic vocabulary** (proper nouns, jargon) through FluidAudio's "CTC boosting", on top
   of word replacements. The CTC model is trained on English: evaluate it on French names
   before exposing it.
3. **Vocabulary learned from corrections**: re-read the field a few seconds after pasting and
   offer a replacement when a word was corrected by hand.
4. **End of call**: when the video-call app releases the microphone, offer to end the meeting.
5. **Pre-roll** on the microphone so the first syllable isn't lost in "hold to talk".
6. **Library sync** (putting it in iCloud Drive already works, through Settings › Library).
7. **Apple notarization**, to remove the block on first open.
8. **More interface translations**: English (default) is written in the
   code, French is in `PlumeKit/L10nTable.swift`; one more language is one more table.
