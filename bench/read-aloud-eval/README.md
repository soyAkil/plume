# Read-aloud summary quality eval

Compares the two candidate summary models on your own texts, judged blind. Run it before choosing which models the catalog ships.

**The selections and the results contain your texts: keep the eval folder outside the repository and never commit it.**

`<eval folder>` below is a folder of your choice outside the repository.

1. **Collect.** Create `<eval folder>/selections/` and drop one `.txt` file per selection: mail, Slack threads, articles, documentation; French and English; about a third short (under 300 words), a third medium, a third long (over 1,500 words). 30 to 50 files. The file names are free.
2. **Download both candidates** (neither turns the feature on in the app):
   ```
   plume read-aloud --download qwen3.5-4b-q4km
   plume read-aloud --download gemma4-e2b-q4
   ```
3. **Run.** For each file and each model, this records the summary (length "automatic", language "same as the text"), the cold and warm timings, and whether the input was truncated. It prints progress and the time left on the standard error. It needs exactly two different models, at least one `.txt` file, and `--out` (no default). It refuses an `--out` inside a Git repository.
   ```
   plume read-aloud --eval <eval folder>/selections --engines qwen3.5-4b-q4km,gemma4-e2b-q4 --out <eval folder>/results.json
   ```
4. **Judge.** Open the page and pick `results.json`:
   ```
   open bench/read-aloud-eval/judge.html
   ```
   Each selection shows the source and two summaries, A and B, in a random order. The model names stay hidden. For each summary tick: main point kept, nothing invented, right language, right length. Then pick a preference (A, B or equal) and add a note if you want. Progress is saved in the browser, with the A/B order, so you can judge over several sittings.
5. **Read the verdict.** Once every selection is judged, the page reveals which model was A or B and shows, per model, the share of summaries passing each criterion, the preferences and the median timings. **Export** downloads `verdicts.json` to your Downloads folder; move it next to `results.json`.
6. **Decide.**
   - Acceptable means: at least 90% of summaries keep the main point and invent nothing, and at least 95% have the right language.
   - Both acceptable: both stay in the catalog; the recommended one depends on the Mac.
   - One clearly worse: only the other stays in the catalog.
   - Neither acceptable: revise the prompt and re-run from step 3, or try another model (one catalog entry).
