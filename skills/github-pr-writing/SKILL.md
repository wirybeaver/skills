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
  **Benchmarking Result** instead of listing CPU validation. Report the
  measured throughput change and name the measured accuracy metrics that
  showed no regression. Put expanded experiment evidence in a GitHub comment
  using the format below.
- When both the data-infrastructure and GPU-dependent branches apply, use
  **Benchmarking Result** in the PR description and describe the end-to-end
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

## Benchmark and end-to-end test comments

A GitHub comment whose primary purpose is to report a benchmark or end-to-end
test has three concise, visible sections in this order:

1. **Experiment** — briefly introduce the comparison, workload, and experiment
   process.
2. **Key Results** — present the headline measurements in a compact table or
   short list.
3. **Conclusion** — state what the evidence establishes and any material
   limitation.

For repeated A/B benchmarks:

- Report mean improvement as `mean(B visits) / mean(A visits) - 1` and median
  improvement as `median(B visits) / median(A visits) - 1` in both PR
  descriptions and GitHub comments.
- In the comment, state the visit order actually executed, such as
  `A -> B -> B -> A` or `A -> B -> B -> A -> A -> B`.
- Cross-arm gain intervals are controller-internal evidence and stay out of PR
  descriptions and GitHub comments.

Put environment setup, reproducibility information, and optional detailed
analysis after the visible sections in a collapsible block. Exclude manifest
SHAs and exact commands. Publish exact commands in a gist only when the user
explicitly requests it.

For historical or superseded benchmark results, wrap the entire comment,
including **Experiment**, **Key Results**, **Conclusion**, and supplementary
details, in one collapsible block. Use
`Historical benchmark — click to expand` as its summary and avoid nested
collapsible blocks.

Use this collapsible form:

```html
<details>
<summary>Click to expand</summary>

Markdown content goes here.

</details>
```
