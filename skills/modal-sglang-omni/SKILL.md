---
name: modal-sglang-omni
description: Run SGLang-Omni profiling and benchmarks on Modal Sandboxes with exact source overlays, locked A/A and A/B schedules, durable evidence, and verified cleanup.
---

# Modal SGLang-Omni profiling

This skill is Modal provider glue for the upstream SGLang-Omni model-profiling
workflow. It controls how an approved experiment runs on Modal; it does not
change what the experiment is.

## Authority

For benchmarks, read [the shared benchmark contract](https://raw.githubusercontent.com/wirybeaver/skills/main/skills/sglang-omni-benchmark/SKILL.md), including its upstream sources. It owns visits, warmups, conditional tails, and benchmark evidence.

For profiling or diagnosis, read the current upstream [model-profiling skill](https://raw.githubusercontent.com/sgl-project/sglang-omni/main/.claude/skills/model-profiling/SKILL.md), [methodology](https://raw.githubusercontent.com/sgl-project/sglang-omni/main/.claude/skills/model-profiling/METHODOLOGY.md), and [prompt template](https://raw.githubusercontent.com/sgl-project/sglang-omni/main/.claude/skills/model-profiling/PROMPT_TEMPLATE.md) completely at each invocation. They own profiling scope, layer selection, confirmation, and reporting. This adapter owns Modal mechanics; the upstream workflow wins conflicts about methodology. An uploaded checkout-local copy does not replace the current instruction source.

After model-profiling triage identifies a slow stage, read the current upstream [omni-gpu-deep-dive skill](https://raw.githubusercontent.com/sgl-project/sglang-omni/main/.claude/skills/omni-gpu-deep-dive/SKILL.md) completely for a stage-level GPU deep dive. Follow its backend capability check, mapping/formal trace pair, steady-state gates, and output contract; resolve its resources against that upstream URL. Keep model-profiling responsible for the approved scope and findings record.

Read the official `$modal` skill and [Modal execution readiness](references/execution-readiness.md) for every run. Read [profiler readiness](references/profiler-readiness.md) only when the approved plan names a profiler. Fetch the shared contract from its canonical URL; if it is unavailable, report the blocker rather than inventing a replacement schedule.

## Workflow

1. Add a short Modal block to the upstream model-profiling plan: profile/app,
   image digest, GPU, timeout, source commits/configs, Volume paths, exact visit
   sequence and conditional tail, warmups, shapes, minimum/maximum legs and
   requests, scorer coverage, and maximum GPU time. Wait for the confirmation
   required by the upstream model-profiling workflow.
2. Run the pre-GPU checks in execution readiness. Keep them cheap and
   local-first. Use a CPU Modal Sandbox only for behavior that actually
   requires Modal, such as Sandbox lifecycle or Volume mounts.
3. Allocate one bounded GPU Sandbox. Immediately record its ID and remote run
   path. Verify the requested GPU, idle state, CUDA, mounts, and exact imports
   before downloading weights or starting servers.
4. Execute the manifest with a fail-closed cursor, following only declared transitions including the shared benchmark contract's conditional compilation-recovery branches. Persist each leg's terminal status before advancing. An unexpected missing, duplicate, reordered, or wrong-arm entry, or any budget overrun, stops the run.
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
