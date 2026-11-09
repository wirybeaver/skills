---
name: github-pr-writing
description: Draft, edit, or review GitHub PR descriptions and benchmark or end-to-end result comments for concise human review.
---

# GitHub PR writing

## PR descriptions

Write for human reviewers. A reader should understand the problem, the core
design decisions, and the headline validation result without reading
implementation details.

Apply explicit user instructions before the defaults below. Reuse approval already given for the requested edit rather than asking again. Publish result comments only when explicitly requested.

- In **Motivation**, state the problem and why the change is needed. For an
  implementation PR within a larger roadmap, explain its role in that roadmap
  and the step it completes.
- In **Modification**:
  - For changes with nontrivial control flow, especially those spanning
    multiple components or stages, summarize the design and show the control
    flow with an ASCII diagram. Keep the prose at the design-decision level.
  - For a narrow change, state the key implementation decisions without
    walking through implementation details.
- For data-infrastructure PRs, use **Test** only for additional end-to-end
  coverage: describe how the test was designed and which path it covers. Keep
  routine unit-test results out of the PR description. Use the shared result format below for expanded experiment evidence.
- For LLM-infrastructure and other GPU-dependent PRs, use a short
  **Benchmark Result** instead of listing CPU validation. Report the
  measured performance and accuracy together, using the table format below.
  Describe observed regressions or limitations explicitly.
- When both the data-infrastructure and GPU-dependent branches apply, use
  **Benchmark Result** in the PR description and include the end-to-end path in its experiment context.

Treat every existing PR-description section and its content as user-owned
source of truth. Preserve it when editing the description; additions may
extend it without replacing the existing text. Any removal or substantive
rewrite requires explicit user approval.

**Related Links** is optional; adding an absent section requires user approval unless already authorized, and that decision must not block the requested work.

## Benchmark results

Apply these rules to PR bodies and comments. In result comments, omit exact commands; publish them in a gist only when explicitly requested:

- Exclude all hashes, including commit SHAs, manifest/source fingerprints, and model or dataset revision hashes. Identify arms by role and behavior; keep hashes in local evidence.
- Keep performance and accuracy together in one **Benchmark Result** section. Put the summary table first and the per-visit results table in a `<details>` block below it. The per-visit block contains the table only; put necessary experiment context and limitations outside it. For end-to-end tests without performance or accuracy measurements, report the tested path, coverage, and observed outcome instead of inventing metrics.
- Briefly state the environment, arm definitions, workloads, and actual visit order. Specify whether every visit restarts the server, the substantial warmup count, and the shape-warmup count immediately followed by the timed request count for each workload.
- Use parameter columns for modes, concurrency, languages, or workloads, and a separate column for each metric, with units in the header. Each summary metric cell contains all arms' median-based absolute values on its first line, explicitly labeled in arm order. Put each candidate's change relative to the base arm on its own following line, using `<br>` and directional labels such as `A → B` and `A → C`. Compare candidates with the base arm by default; add candidate-to-candidate comparisons only when requested.
- Compute each arm's summary absolute value as the median of its visit-level metric values. For latency, retain the actual within-visit statistic: the median across visit-level mean latencies is distinct from the median across visit-level median latencies or pooled request latencies. Label the metric accurately. Derived counters with a different aggregation must retain that aggregation label rather than being called medians.
- For numerical metrics such as throughput, mean latency, or TTFA, show signed relative percentage change: `(candidate median / base median - 1) * 100%`. For metrics already expressed as percentages, such as WER or CER, show the signed difference in **percentage points (pp)** only: `7.0% → 7.4%` is `+0.4 pp`.
- Preserve per-visit absolute measurements in executed order in the collapsed table, with one row per visit/workload and parameter/metric columns. Keep cross-arm gain intervals in controller evidence. Use blank lines before and after tables so adjacent prose stays outside them.

Example layout (illustrative values):

```markdown
## Benchmark Result

Environment, workloads, and arm definitions. Each mode follows A1 → B1 → C1 → C2 → B2 → A2, restarting the server for every visit with 256 substantial warmup requests, then 32 shape-warmup requests immediately followed by 256 timed requests for each workload.

| Mode | Concurrency | Throughput (req/s) | Mean latency (ms) | Corpus WER (%) |
|---|---|---|---|---|
| Normal | c1 | A/B/C: 10.00 / 12.00 / 15.00<br>A → B: +20.00%<br>A → C: +50.00% | A/B/C: 100.00 / 80.00 / 60.00<br>A → B: -20.00%<br>A → C: -40.00% | A/B/C: 7.00% / 7.40% / 6.80%<br>A → B: +0.40 pp<br>A → C: -0.20 pp |

Relevant observed regression or limitation.

<details>
<summary>Per-visit results</summary>

| Mode | Visit | Throughput (req/s) | Mean latency (ms) | Corpus WER (%) |
|---|---|---:|---:|---:|
| Normal | A1 | ... | ... | ... |
| Normal | B1 | ... | ... | ... |
| Normal | C1 | ... | ... | ... |
| Normal | C2 | ... | ... | ... |
| Normal | B2 | ... | ... | ... |
| Normal | A2 | ... | ... | ... |

</details>
```

## Historical benchmark results

Keep the current result visible. Preserve superseded results unless the user requests removal. Each historical run uses one `<details>` block labeled by workload, configuration, or date, containing its context, summary table, per-visit table, and limitations without nested collapsibles. Apply the same metric rules and mark unavailable statistics as unavailable.
