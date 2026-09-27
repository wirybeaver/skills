---
name: modal-sglang-omni
description: Run SGLang-Omni profiling and benchmarks on Modal Sandboxes with exact source overlays, locked A/A and A/B schedules, durable evidence, and verified cleanup.
---

# Modal SGLang-Omni profiling

This skill is Modal provider glue for `$model-profiling`. It controls how an
approved experiment runs on Modal; it does not change what the experiment is.

## Authority

Read the current `$model-profiling` source workflow and the official `$modal`
skill. `$model-profiling` owns scope, confirmation, methodology, evidence, and
reporting. This skill owns Modal setup, execution, persistence, and teardown.
When they conflict, `$model-profiling` wins.

Read [execution readiness](references/execution-readiness.md) for every run.
Read [profiler readiness](references/profiler-readiness.md) only when the
approved plan names a profiler.

## Benchmark schedule

Lock the approved sources, placement, ordered workloads, visits, warmups,
scorers, cohorts, and budget in an immutable manifest before GPU allocation.
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

Two do not fit:        A/B  A  -> B  -> B  -> A -> A -> B
                       (no separate A/A)
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
to this path. Without an A/A noise floor, treat small A/B deltas as
uncalibrated rather than claiming a robust performance gain.

For each visit, iterate the approved workload list. Run one shape warmup
immediately followed by one timed leg per workload before advancing to the
next; do not transpose the workload and visit loops. A/A and A/B use matching
workloads and sample counts within each stage. Optional full qualification
retains the visit order, shape-warmup policy, and 256 samples per timed leg;
any broader workload map must be explicitly approved.

For TTS quality, retain the **timed-leg WAVs** for only `c1` and `c8` from the
middle A/B `B -> A` pair (visits 3 and 4) on the Volume. Use matching sample
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
Persist evidence and terminate the paid Sandbox before asking. A generic
"continue" resumes the existing manifest; it never expands it.

## Workflow

1. Add a short Modal block to the `$model-profiling` plan: profile/app, image
   digest, GPU, timeout, source commits/configs, Volume paths, exact visit
   sequence and conditional tail, warmups, shapes, minimum/maximum legs and
   requests, scorer coverage, and maximum GPU time. Wait for the confirmation
   required by `$model-profiling`.
2. Run the pre-GPU checks in execution readiness. Keep them cheap and
   local-first. Use a CPU Modal Sandbox only for behavior that actually
   requires Modal, such as Sandbox lifecycle or Volume mounts.
3. Allocate one bounded GPU Sandbox. Immediately record its ID and remote run
   path. Verify the requested GPU, idle state, CUDA, mounts, and exact imports
   before downloading weights or starting servers.
4. Execute the manifest with a fail-closed cursor. Persist each leg's terminal
   status before advancing. A missing, duplicate, reordered, wrong-arm, or
   over-budget entry stops the run.
5. Keep media required by approved quality scorers on the Volume until scoring
   completes. If selected, score the early model-specific gate before screening
   and the main quality set after performance. Copy back compact reports,
   per-sample scores, logs, manifests, and checksums, not bulky media by default.
6. After the last approved remote task, terminate the Sandbox before analysis
   or follow-up planning. Verify terminal state and zero owned tasks/containers.

## Modal invariants

- Resolve the CI image to a registry digest and record installed core versions.
- Upload each intended source arm independently. Use an explicit arm-specific
  `PYTHONPATH`; never replace one shared editable install with another.
- Record each arm's logical role, commit, dirty fingerprint, archive hash,
  launch arguments, and source/configuration difference.
- For a fixed H100 request use `gpu="H100!"` and verify the allocated device.
- Give every attempt a new run ID and remote directory. Never overwrite the
  only pointer to an earlier attempt.
- Persist intermediate evidence after long operations. Classify artifacts as
  required-local, remote-only, or disposable before the run.
- Touch only owned processes and allocations. A user stop request means stop
  owned work and terminate the exact Sandbox immediately, not after the phase.

## Pre-GPU check scope

Source tests are keyed by source content. Run the smallest relevant tests when
the source changes, and reuse that evidence while the source hashes stay fixed.
An orchestration-only edit reruns syntax, manifest fixtures, lifecycle, and
persistence checks—not the full model test suite.

The pre-GPU checks do not prove GPU performance, CUDA correctness, model
quality, or profiler permissions. Those remain GPU-run evidence.
