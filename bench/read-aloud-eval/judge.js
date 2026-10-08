// bench/read-aloud-eval/judge.js
// Verdict math for the blind judge page. Plain functions, tested from Swift with JavaScriptCore.
(function (root) {
  const CRITERIA = ["mainPoint", "nothingInvented", "rightLanguage", "rightLength"];

  function lengthClass(words) {
    return words < 300 ? "short" : words <= 1500 ? "medium" : "long";
  }

  function median(values) {
    if (values.length === 0) return null;
    const sorted = [...values].sort((a, b) => a - b);
    const middle = Math.floor(sorted.length / 2);
    return sorted.length % 2 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
  }

  // Shares the spec asks for: below these, a model is not acceptable. No threshold on length.
  const THRESHOLDS = { mainPoint: 0.9, nothingInvented: 0.9, rightLanguage: 0.95 };

  function below(criterion, share) {
    return criterion in THRESHOLDS && share < THRESHOLDS[criterion];
  }

  // results: results.json; verdicts: { [file]: { order: [idA, idB], A: {criteria}, B: {criteria}, preference: "A"|"B"|"equal", note } }
  function summarize(results, verdicts) {
    const engines = {};
    for (const engine of results.engines) {
      engines[engine.id] = { counts: {}, preferred: 0, totals: [], firsts: [], coldTotals: [], coldFirsts: [] };
    }
    let ties = 0;
    for (const item of results.items) {
      // Timings belong to the run, not to the verdict. An errored outcome has 0 s timings and
      // a summary-less one has no first sentence: both would make a failing model look fast.
      for (const [id, engine] of Object.entries(engines)) {
        const outcome = item.results[id];
        if (!outcome || outcome.error) continue;
        const warm = outcome.cold !== true;
        if (typeof outcome.totalSeconds === "number") (warm ? engine.totals : engine.coldTotals).push(outcome.totalSeconds);
        if (typeof outcome.firstSentenceSeconds === "number" && outcome.sentences !== 0) {
          (warm ? engine.firsts : engine.coldFirsts).push(outcome.firstSentenceSeconds);
        }
      }
      const verdict = verdicts[item.file];
      if (!verdict) continue;
      const lengthKey = lengthClass(item.words);
      verdict.order.forEach((id, index) => {
        const label = index === 0 ? "A" : "B";
        const engine = engines[id];
        if (!engine) return;
        for (const key of ["all", lengthKey]) {
          engine.counts[key] = engine.counts[key] || { n: 0 };
          engine.counts[key].n += 1;
          for (const criterion of CRITERIA) {
            engine.counts[key][criterion] = (engine.counts[key][criterion] || 0) + (verdict[label][criterion] ? 1 : 0);
          }
        }
        if (verdict.preference === label) engine.preferred += 1;
      });
      if (verdict.preference === "equal") ties += 1;
    }
    const out = { engines: {}, ties };
    for (const [id, engine] of Object.entries(engines)) {
      const shares = {};
      for (const [key, count] of Object.entries(engine.counts)) {
        shares[key] = { n: count.n };
        for (const criterion of CRITERIA) shares[key][criterion] = count.n ? count[criterion] / count.n : 0;
      }
      if (!shares.all) shares.all = Object.assign({ n: 0 }, Object.fromEntries(CRITERIA.map((c) => [c, 0])));
      out.engines[id] = Object.assign(shares, {
        preferred: engine.preferred,
        // Warm runs only; the engine's first file after its cold load is reported apart.
        medianTotalSeconds: median(engine.totals),
        medianFirstSentenceSeconds: median(engine.firsts),
        cold: { totalSeconds: median(engine.coldTotals), firstSentenceSeconds: median(engine.coldFirsts) },
      });
    }
    return out;
  }

  // A random A/B order per file, drawn once and kept with the progress, so a reload never
  // swaps the labels of a judged selection.
  function orderFor(file, engineIds, saved) {
    if (saved[file] && saved[file].order) return saved[file].order;
    const order = Math.random() < 0.5 ? [engineIds[0], engineIds[1]] : [engineIds[1], engineIds[0]];
    return order;
  }

  root.PlumeJudge = { summarize, orderFor, lengthClass, below, CRITERIA };
})(globalThis);
