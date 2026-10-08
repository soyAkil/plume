# Plume — credits and licenses

Plume transcribes your voice on your Mac and sends nothing anywhere else. It builds on
models, libraries, fonts and icons published by others. Here they are, with their license.

## Models

They are not included in the app: Plume downloads them from Hugging Face on first launch,
into `~/Library/Application Support/FluidAudio/Models`.

### Transcription — Parakeet Ultra

- Parakeet TDT 0.6b v3, © NVIDIA — https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3
- post-trained by moondream (parakeet-ultra) — https://huggingface.co/moondream/parakeet-ultra
- converted to Core ML (modified version) by Fluid Inference —
  https://huggingface.co/FluidInference/parakeet-ultra-coreml

License: Creative Commons Attribution 4.0 — https://creativecommons.org/licenses/by/4.0/

### Diarization

- pyannote speaker-diarization-community-1 —
  https://huggingface.co/pyannote/speaker-diarization-community-1
- WeSpeaker voiceprints — https://github.com/wenet-e2e/wespeaker
- PLDA from BUT Speech@FIT
- converted to Core ML (modified versions) by Fluid Inference —
  https://huggingface.co/FluidInference/speaker-diarization-coreml

License: Creative Commons Attribution 4.0 — https://creativecommons.org/licenses/by/4.0/

References:

- A. Plaquet, H. Bredin, "Powerset multi-class cross entropy loss for neural speaker
  diarization", Interspeech 2023.
- H. Wang et al., "WeSpeaker: A research and production oriented speaker embedding learning
  toolkit", ICASSP 2023.
- F. Landini, J. Profant, M. Diez, L. Burget, "Bayesian HMM clustering of x-vector sequences
  (VBx) in speaker diarization: theory, implementation and analysis on standard tasks",
  Computer Speech & Language, 2022.

### Echo cancellation — LocalVQE

- LocalVQE, © 2024-2026 Richard Sherwood Palethorpe — https://huggingface.co/LocalAI-io/LocalVQE
- converted to Core ML by Fluid Inference — https://huggingface.co/FluidInference/localvqe-coreml
- based on DeepVQE: E. Indenbom et al., Interspeech 2023, arXiv:2306.03177.

License: Apache 2.0 — https://www.apache.org/licenses/LICENSE-2.0

## Libraries

- **FluidAudio**, © Fluid Inference — Apache 2.0 — https://github.com/FluidInference/FluidAudio
- **Sparkle** (updates), © Sparkle Project and Andy Matuschak — MIT license —
  https://github.com/sparkle-project/Sparkle
- **llama.cpp** (local summaries), © The ggml authors — MIT license —
  https://github.com/ggml-org/llama.cpp

## Fonts

- **Geist** and **Geist Mono**, © 2024 The Geist Project Authors — SIL Open Font License 1.1 —
  https://github.com/vercel/geist-font (license text shipped with the fonts, in the app).

## Sounds

- Recording sound packs (Pluck, Beeps, Clicks, Melody, Glide): **Epidemic Sound** —
  https://www.epidemicsound.com — "User Interface, Click, Select, Soft Round Pluck, Short,
  Reverb", "Beep, Button, Happy, Select, Confirm, Deselect, Cancel", "Click, On & Off,
  Small, Short 03", "Alert, Alerts, Notification 15", "Misc, Completions, Melodic,
  Success", "Alert, Notification, Email, Receive, Incoming 03" and "Motion, Swipe Backup".
  Plume's other sounds, including the Wood pack, are synthesized by the app.

## Icons

- **Lucide**, © Lucide Contributors — ISC license; some icons come from Feather,
  © Cole Bemis — MIT license — https://lucide.dev
