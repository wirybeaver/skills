---
name: sglang-omni-benchmark
description: Plan and execute provider-independent SGLang-Omni A/A and A/B benchmarks with fixed cohorts, server visits, warmups, evidence, and stop gates. Use with a GPU provider adapter for actual execution.
---

# SGLang-Omni benchmark contract

This skill owns the benchmark schedule and evidence contract shared by Modal and RadixArk. Provider skills own allocation, connection, persistence, and release. Apply explicit user constraints first; record any requested departure in the approved manifest.

## Authority and scope

At each invocation, read the current upstream [model-profiling skill](https://raw.githubusercontent.com/sgl-project/sglang-omni/main/.claude/skills/model-profiling/SKILL.md), [methodology](https://raw.githubusercontent.com/sgl-project/sglang-omni/main/.claude/skills/model-profiling/METHODOLOGY.md), and [prompt template](https://raw.githubusercontent.com/sgl-project/sglang-omni/main/.claude/skills/model-profiling/PROMPT_TEMPLATE.md) completely. They own confirmation, profiling layer selection, reporting, and durable tracking. Report an unavailable source instead of silently using a stale copy.

For every service benchmark, read [execution readiness](references/execution-readiness.md). Read the chosen provider's runtime instructions before using a GPU. Approval of an experiment does not authorize allocating or extending a Radix assignment.

A diagnostic request is not permission to invent a benchmark campaign. Scope a diagnostic separately, including its interventions and limits; its timings do not replace a benchmark with different instrumentation or lifecycle. Benchmark repeats on one persistent server require explicit approval as a different experiment; they do not substitute for the single-server restart schedule below.

## Benchmark schedule

Lock the approved sources, placement, ordered workloads, visits, warmups,
scorers, cohorts, and budget in an immutable manifest before GPU allocation or use of an existing assignment.
Screening runs **256 samples per timed workload leg**. Full qualification is
optional: it uses the same visit order and 256 samples per timed leg, and may
use a broader separately approved workload map. Run it only if screening
passes its preapproved criterion and the full stage was explicitly approved;
a screening pass alone does not authorize it.

### Optional early quality check

This check applies to **all models**, not only TTS. Before screening, if
approved, run **A -> B** with matching 32-sample cohorts at `c1` and `c8`
for each arm. Score the model's approved quality metric remotely (WER where
appropriate) before performance; stop if the predeclared gross-regression
criterion fails. Resolve an unsupported workload or missing scorer in the
plan rather than silently omitting a requested check. This small check does
not prove quality parity or replace a measured server's substantial warmup.

### Visits and warmups

Use the same timed visit order for screening and optional full qualification:

```text
Two live servers fit:  A/A  A1 -> A2 -> A2 -> A1
                       A/B  A  -> B  -> B  -> A
                       Tail A  -> B  only if the gain criterion is unmet

Two do not fit:        A/B  A  -> B  -> B  -> A
                       Tail A -> B unless the four-visit stop gate passes
                       No separate A/A
```

With two live servers, keep each phase's pair running between visits: A1 and
A2 have identical baseline source/configuration, while A and B retain their
respective source/configuration. Give each newly started server one substantial
warmup before timed work. After the fourth dual-server A/B visit, compare the
result with the predeclared significant-gain criterion and the A/A noise floor.
If it passes, record the final `A -> B` visits as skipped and proceed to quality
scoring; otherwise run them. When two servers cannot fit, restart **every** A/B
visit, including adjacent visits of the same arm, on the same approved
placement; give each restart one substantial warmup. Do not add an A/A phase
to this path. Lock one primary performance metric and its improvement
direction for each workload in the manifest before allocation. After
`A1 -> B1 -> B2 -> A2`, use each workload's four **absolute metric values**
to bound the observed gain: compute `improvement(Ai, Bj)` for all four
combinations of `i, j in {1, 2}`, then take their minimum and maximum.
`improvement(A, B)` is `(B - A) / A` for higher-is-better metrics and
`(A - B) / A` for lower-is-better metrics.

Skip the final `A -> B` only if, for **every** approved workload, the entire
gain interval is strictly below 4% or strictly above 6%. A workload may be
in either band; report its conclusion separately. Run the tail if any metric
is missing, nonpositive or nonfinite, or if any workload's interval touches
the closed 4–6% band. This cross-arm bound accounts for variation between
visits without a fixed same-arm drift tolerance: one unusually low A value
cannot by itself establish a gain above 6%. Record the four values, gain
interval, thresholds, and terminal status of both tail visits. Without an
A/A noise floor, treat small A/B deltas as uncalibrated rather than claiming
a robust performance gain.

For each visit, iterate the approved workload list. Run one shape warmup
immediately followed by one timed leg per workload before advancing to the
next; do not transpose the workload and visit loops. A/A and A/B use matching
workloads and sample counts within each stage. Optional full qualification
retains the visit order, shape-warmup policy, and 256 samples per timed leg;
any broader workload map must be explicitly approved.

For TTS quality, retain the **timed-leg WAVs** for only `c1` and `c8` from the
middle A/B `B -> A` pair (visits 3 and 4) in durable storage. Use matching sample
IDs and seeds; score the approved quality metrics *after that stage's
performance visits*, not during timed legs. The earlier 32-sample quality check
is separate.
Do not score A/A or other A/B visits without approval.

`B -> A` means visit B, then visit A; it does not exchange sources, server
slots, ports, CPU sets, or placements. A BA placement crossover is a separate
experiment. Record the lifecycle and use the
[execution readiness](references/execution-readiness.md) contract.

The manifest is a closed list: advance only through its entries and stop at
its end or a predeclared failed gate. Lock the dual-server gain criterion and
conditional tail before allocation; record terminal skipped entries when it
passes. Any extra arm, phase, placement, workload, repeat, profiler, or scorer
needs a new plan and explicit approval.
Persist evidence and complete provider cleanup before asking; reacquiring a released target needs new authorization. A generic
"continue" resumes the existing manifest; it never expands it.
