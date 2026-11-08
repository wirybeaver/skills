---
name: github-pr-writing
description: Draft, edit, or review GitHub PR descriptions and benchmark or end-to-end result comments for concise human review.
---

# GitHub PR writing

## PR descriptions

Write for human reviewers. A reader should understand the problem, the core
design decisions, and the headline validation result without reading
implementation details.

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
  routine unit-test results out of the PR description. Put expanded experiment
  evidence in a GitHub comment using the format below.
- For LLM-infrastructure and other GPU-dependent PRs, use a short
  **Benchmark Result** instead of listing CPU validation. Report the
  measured performance and accuracy together, using the table format below.
  Describe observed regressions or limitations explicitly.
- When both the data-infrastructure and GPU-dependent branches apply, use
  **Benchmark Result** in the PR description and describe the end-to-end
  path under **Experiment** in the GitHub comment.

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
  units in the header. Preserve execution order and absolute values for every
  visit. Use parameter columns for different modes or workloads; avoid separate
  arm-specific column groups or separate performance and accuracy tables.
- Put relative changes in prose after the table, naming the compared arms and
  improvement direction. Keep percentage changes and summary rows out of the
  per-visit table. Cross-arm gain intervals stay in controller evidence.
- Default to median performance statistics rather than mean statistics, including
  per-request latency and aggregation across repeated visits. Compute latency
  medians from per-request observations; an average of visit means is not a
  median. Report means only when explicitly requested. Keep throughput as each
  visit's measured requests per second and accuracy in its established form,
  such as corpus WER; do not replace these with medians over individual requests.
- For repeated A/B benchmarks, state the actual visit order. Summarize throughput
  change as `median(B visit throughputs) / median(A visit throughputs) - 1` by
  default. Distinguish this aggregation across visits from each visit's median
  request latency.

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

Median throughput improvement (B/A): ... . Accuracy observation and limitations.
```

## Historical benchmark results

Keep the current **Benchmark Result** visible in the PR body. When a new run
supersedes an earlier result, preserve that earlier result in a collapsed block
in the PR body, rather than posting historical results as GitHub comments.
Identify each historical run by its workload, date, or meaningful configuration.
Retain its environment, arm definitions, executed order, absolute per-visit
performance and accuracy table, and relevant limitations. Apply the same
hash-free and median-default rules; retain unavailable statistics as unavailable
rather than relabeling means as medians. Use one block per historical run and
avoid nested collapsible blocks.

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

For an explicitly requested benchmark or end-to-end result comment, use three
concise sections: **Experiment**, **Benchmark Result**, and **Conclusion**.
Experiment describes the comparison, workload, and process; Benchmark Result
uses the combined table above; Conclusion states what the evidence establishes
and its limitations. Wrap the comment in one collapsible block. Expanded setup
or analysis may follow the conclusion inside that block. Historical benchmark
results belong in the PR body as specified above.

Exclude exact commands. Publish them in a gist only when explicitly requested.
