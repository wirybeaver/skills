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

**Related Links** is optional and may contain issues, PRs, roadmaps,
documentation, or other relevant links. When a PR has neither the section nor
prior approval for it, propose the section for approval before adding it.
Handle all optional PR-description approvals after completing the required
work; they never block task completion.

## Benchmark results

Apply these rules to PR bodies and comments:

- Exclude all hashes, including commit SHAs, manifest/source fingerprints, and
  model or dataset revision hashes. Identify arms by role and behavior, such as
  base, compatibility patches, and head with async decode. Keep hashes in local
  evidence rather than public prose, tables, or links.
- Combine performance and accuracy in one **Benchmark Result** section and one
  per-visit table. Follow [PR #3564](https://github.com/sgl-project/sglang-omni/pull/3564):
  each row is one executed visit; each column is one parameter or metric, with
  units in the header. Use parameter columns for different modes or workloads; avoid separate
  arm-specific column groups or separate performance and accuracy tables. For end-to-end tests without performance or accuracy measurements, report the tested path, coverage, and observed outcome instead of inventing benchmark metrics.
- State the actual visit order and preserve it alongside per-visit absolute measurements in the table. After the table, report median-based relative changes in prose, naming the compared arms and improvement direction. Immediately follow each relative change with parentheses containing both arms' median absolute values, explicit arm labels, and units, for example `+14.22% (B/C: 38.29/43.73 req/s)`. Compute throughput change as `median(candidate visit throughputs) / median(baseline visit throughputs) - 1`; for accuracy, compare medians of visit-level metrics such as corpus WER. Compute each visit's median latency from its per-request observations, keeping it distinct from aggregation across visits. Use means only when explicitly requested. Keep relative changes and summary rows in the prose and cross-arm gain intervals in controller evidence.

Use this table shape, adding only relevant parameter and metric columns:

```markdown
## Benchmark Result

Brief environment, workload, arm definitions, and executed visit order.

| Mode | Visit | Throughput (req/s) | Median latency (s) | Corpus WER |
|---|---|---:|---:|---:|
| Normal | A1 | ... | ... | ... |
| Normal | B1 | ... | ... | ... |
| Normal | B2 | ... | ... | ... |
| Normal | A2 | ... | ... | ... |

Median throughput improvement (B/A): ...% (A/B: .../... req/s). Median corpus WER reduction (B vs A): ...% relative (A/B: ...%/...%). Relevant limitations.
```

## Historical benchmark results

Keep the current **Benchmark Result** visible in the PR body. When an approved update supersedes an earlier run, preserve the earlier result in the PR body using the collapsible format below, unless the user requests its removal. Apply the benchmark rules above to historical results too; mark unavailable statistics as unavailable rather than relabeling means as medians.

Use this same format for historical results and explicitly requested result comments: one block per run, with a summary identifying its workload, configuration, or date. Keep environment and experiment context, the applicable results table, and relative changes with median absolute values and relevant limitations inside the block. Avoid nested collapsible blocks.

```html
<details>
<summary>Historical benchmark result — workload / configuration / date</summary>

## Benchmark Result

Environment, workload, arm definitions, and visit order.

Per-visit performance and accuracy table.

Relative changes and limitations.

</details>
```

## Benchmark and end-to-end test comments

Use the shared collapsible format in **Historical benchmark results**, with a summary such as `Benchmark result — workload / configuration / date`.

Exclude exact commands. Publish them in a gist only when explicitly requested.
