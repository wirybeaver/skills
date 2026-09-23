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

## Two-stage paired schedule

Write the approved schedule to an immutable manifest before allocating a GPU.
Define an ordered workload list for each stage. Every workload independently
specifies its concurrency, shape-warmup sample count, and timed sample count;
do not assume the workload set or sample counts are uniform.
Within one stage, A/A and A/B use the same workload list and sample counts.

### Screening gate

Use small, workload-specific sample counts to reject weak candidates cheaply:

```text
A/A substantial: A1 -> A2
A/A timed:       A1 -> A2 -> A2 -> A1

A/B substantial: A -> B
A/B timed:       A -> B -> B -> A
```

### Full qualification

Only a candidate that passes the confirmed screening criterion may enter full
qualification. Use a separately confirmed full workload map; for example,
`c1`, `c8`, and `c16` may each use 256 samples, but neither those workloads nor
that count are defaults.

Full qualification has matching full-size A/A and A/B phases:

```text
A/A substantial: A1 -> A2
A/A timed:       A1 -> A2 -> A2 -> A1 -> A1 -> A2

A/B substantial: A -> B
A/B timed:       A -> B -> B -> A -> A -> B
```

Within each timed arm visit, iterate only that stage's confirmed workload list.
For every workload, run exactly one shape warmup immediately followed by
exactly one timed leg using that workload's own sample counts. Finish this pair
before advancing to the next workload. Do not batch all shape warmups before
the timed legs, and do not transpose the loops.

The full stage may start automatically only when its exact workload map,
schedule, screening criterion, and incremental cost were already confirmed.
Otherwise persist the gate result, terminate the Sandbox, and request approval.

`B -> A` means visit B, then visit A. It does not swap commits, server slots,
CPU sets, ports, or logical arm identities. A BA placement crossover is a new
experiment and is not part of the schedule above.

When one GPU cannot hold both servers, run each visit as a fresh, sequential
server on the same placement. A1/A2 remain identical baseline restarts, and the
A/A band measures restart noise. Record the lifecycle in the manifest and use
the fresh-server contract in execution readiness; live dual servers are an
option when they fit, not a requirement.

The manifest is a closed list. Execute exactly its entries and stop at its end.
An extra phase, arm, placement, repeat, shape, profiler, or scorer requires a
new plan and explicit confirmation. First persist evidence and terminate the
current paid Sandbox. A generic “continue” resumes the existing manifest; it
never expands it.

## Workflow

1. Add a short Modal block to the `$model-profiling` plan: profile/app, image
   digest, GPU, timeout, source commits/configs, Volume paths, exact visit
   sequence, warmups, shapes, total legs/requests, scorer coverage, and maximum
   GPU time. Wait for the confirmation required by `$model-profiling`.
2. Run the pre-GPU checks in execution readiness. Keep them cheap and
   local-first. Use a CPU Modal Sandbox only for behavior that actually
   requires Modal, such as Sandbox lifecycle or Volume mounts.
3. Allocate one bounded GPU Sandbox. Immediately record its ID and remote run
   path. Verify the requested GPU, idle state, CUDA, mounts, and exact imports
   before downloading weights or starting servers.
4. Execute the manifest with a fail-closed cursor. Persist each leg's terminal
   status before advancing. A missing, duplicate, reordered, wrong-arm, or
   over-budget entry stops the run.
5. Keep bulky generated media on the Volume. Run approved scorers there, then
   copy back reports, metrics, per-sample results, logs, manifests, and checksums.
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
