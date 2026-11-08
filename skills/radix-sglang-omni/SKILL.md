---
name: radix-sglang-omni
description: Run SGLang-Omni benchmarks or approved profiling on sglang-community GPUs via radix. Combines Radix runtime management with the shared benchmark contract or upstream model-profiling workflow.
---

# SGLang-Omni on Radix

This is the workload/provider adapter. Read [radix-run-time](https://raw.githubusercontent.com/wirybeaver/skills/main/skills/radix-run-time/SKILL.md) for assignment approval, H100/H200 selection, SSH, the four-hour lease, explicit-only renewal, and release. An approved experiment is not approval to run `radix assign` or `radix extend`.

## Select the workflow

- **Benchmark:** read [sglang-omni-benchmark](https://raw.githubusercontent.com/wirybeaver/skills/main/skills/sglang-omni-benchmark/SKILL.md) and its shared execution readiness. They own the A/A and A/B visit schedule, per-visit server lifecycle, warmups, cohorts, scorer coverage, and conditional tail. Use those rules unchanged by the choice of GPU provider.
- **Profiling or diagnosis:** read the current upstream [model-profiling skill](https://raw.githubusercontent.com/sgl-project/sglang-omni/main/.claude/skills/model-profiling/SKILL.md), [methodology](https://raw.githubusercontent.com/sgl-project/sglang-omni/main/.claude/skills/model-profiling/METHODOLOGY.md), and [prompt template](https://raw.githubusercontent.com/sgl-project/sglang-omni/main/.claude/skills/model-profiling/PROMPT_TEMPLATE.md) completely. Use their layer selection and confirmation gates. Read [shared execution readiness](https://raw.githubusercontent.com/wirybeaver/skills/main/skills/sglang-omni-benchmark/references/execution-readiness.md) for source overlays, ownership, and evidence mechanics; this does not select a benchmark schedule for a diagnostic.

For a task containing both, give the benchmark and profiler passes separate entries, timing boundaries, and conclusions in the approved plan. A profiler executable being available does not authorize running it. Persistent-server diagnostic repeats are a separate approved experiment and cannot replace independent single-server benchmark visits.

## Prepare an execution plan

Append a Radix block to the chosen workflow's plan before assignment or inference:

- machine/assignment ownership, H100/H200 SKU and count, and approval state;
- default four-hour duration or explicitly approved duration; actual expiry once known; renewal authorization (default none); cleanup reserve and release policy;
- SSH alias from provider connection output and remote working directory;
- relevant CI workflow/setup, immutable image digest or isolated dependency pins;
- exact A/B revisions, dirty fingerprints, separate source archives/import roots, and the intended semantic difference;
- checkpoint and dataset revisions, ordered sample IDs/seeds, and audio/content hashes where applicable;
- fixed assigned GPU UUIDs, CPU sets, server slots/ports, launch/health/stop commands;
- approved visits/workloads/warmups/scorers and bounded optional profiler entries; artifact paths, copy-back, checksums, and stopping conditions.

Use local read-only checks before requesting an assignment. Runtime gates requiring the assigned hardware remain explicit until allocation is authorized. Confirm both experiment scope and the separate assignment permission; do not infer either from an SSH alias.

## Execute

1. Let `radix-run-time` acquire or validate the explicitly supplied assignment. Immediately record its identifiers, expiry, GPU mapping, SSH alias, and unique remote run path locally.
2. Complete the runtime GPU/container gate and shared execution readiness, including its compile-environment contract. The installed image alone is not CI parity: apply and record any relevant post-image CI setup.
3. Upload each source arm independently. Set an arm-specific `PYTHONPATH` for server and client; verify `sglang_omni.__file__` and the benchmark module's `__file__` inside that arm. Two editable installs in one environment do not provide isolated sources. A flag on Head is not a Base checkout.
4. Complete cheap controller checks before inference: exact manifest order/counts, archive and cohort hashes, output parents, import paths, fresh-server stop/release behavior, and artifact retrieval. Reuse unchanged source-test evidence; test newly changed orchestration at its own seam.
5. Lock the manifest and run only its entries. For a single-server benchmark, restart every visit, **including adjacent B visits**; each restart receives the same substantial warmup and each workload its adjacent shape-warmup/timed-leg pair. With two approved live servers, follow the shared contract's retained-pair schedule instead. GPU lease reuse is distinct from server-process reuse.
6. Record requested and effective runtime settings: actual async execution, precision/deterministic modes, CUDA Graph use, batching limits, dependency versions, and source/patch identities relevant to the hypothesis. Verify real checkpoint outputs and device behavior; CPU mocks establish routing, not numerical parity.
7. Persist each leg's terminal result and raw request/scorer records before advancing. Record the conditional tail as executed or skipped with its deciding evidence. Monitor the lease and keep enough time for artifacts and cleanup. An insufficient lease pauses execution or uses an explicitly authorized extension; it never justifies silently shrinking the cohort or changing the schedule.
8. Stop owned work after the last approved remote task. Metric extraction from saved tensors can be an explicit bounded remote entry; interpret results after GPU work stops. Retrieve and checksum-verify required artifacts, then release and verify the assignment through `radix-run-time` unless explicitly retained.

## Evidence and reporting

Store the report and raw artifacts under the target checkout's gitignored `.profiling-runs/<model>/<run-id>/`. Keep source commits, observer/profiler deltas, actual process lifetimes, placements, quota events, commands, and cleanup proof alongside the metrics.

Inspect per-request latency and generated work before attributing a throughput difference. Keep cold JIT/cache events visible: a warmup does not prove that all later dynamic shapes are compiled. Scope tracing to the approved workload and distinguish observer overhead, actual GPU activity, and host waits. Do not remove slow samples to improve the headline result.

Report H100 and H200 results separately; a GPU or dependency change creates a new environment fingerprint. Apply the upstream reporting/evidence requirements, distinguish measured facts from hypotheses, and keep profiling-derived timings separate from clean benchmark claims. A generic continuation resumes the approved manifest; new arms, profiler passes, placement changes, or extra repeats require a new plan and explicit approval.
