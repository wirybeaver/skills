---
name: vastai-sglang-omni
description: Run SGLang-Omni benchmarks and layered model profiling on Vast.ai with repeatable CI-image/source overlays, service lifecycle, workload A/B controls, application-native traces, artifacts, and verified instance cleanup. Use when SGLang-Omni execution targets Vast.ai; use vastai-gpu-runtime for GPU runtime and NCU readiness.
---

# Vast.ai SGLang-Omni benchmarking glue

This is the workload/provider adapter for SGLang-Omni on Vast.ai. Use the
official `$vastai` skill for provider control, `$vastai-gpu-runtime` for the GPU
execution environment, and `$model-profiling` for the current layered
methodology. This skill does not duplicate those interfaces.

## Source-of-truth contract

Use `$model-profiling` to fetch and apply the latest GitHub main-branch
`SKILL.md`, `METHODOLOGY.md`, and `PROMPT_TEMPLATE.md`. It owns experiment
scope, confirmation gates, layer routing, evidence grading, report shape, and
durable tracking.

Include those remote instruction URLs in the executor prompt. An uploaded
checkout-local methodology file is part of the source under test, including
authorized dirty changes; it does not replace the fetched instruction source
unless the remote workflow explicitly says so.

Read `$vastai` for current CLI/auth/control-plane behavior. Read
`$vastai-gpu-runtime` for target modes, image/runtime preflight, Docker/driver
repair, optional NCU readiness, exact-command execution, and provider cleanup.

If instructions conflict, the model-profiling source workflow owns methodology
and approval; the official Vast.ai skill owns provider API behavior; the
runtime skill owns host/container readiness. This glue owns only their
SGLang-Omni composition.

Translate pre-plan target checks without spending credits. Run local read-only
checks plus account/offer discovery before presenting the plan. Checks such as
`nvidia-smi` that require a rented instance remain explicit unresolved gates in
the plan and execute only after confirmation.

## Provider bridge

While preparing the model-profiling plan, append a Vast.ai execution block
containing:

- account/profile context and current credit/billing check;
- offer policy, GPU model/count, reliability/direct-port requirements, maximum
  hourly price, disk, and timeout;
- target mode and template/image digest;
- checkout commit and dirty-file fingerprints;
- checkpoint/dataset revisions and cache paths;
- SSH bootstrap or prebuilt-image command;
- server, health, warmup, benchmark, and copy-back commands;
- unique instance/run/artifact IDs;
- stop/destroy commands and retry cap.

Never invent or print secret values. A profiling request prepares this block;
instance creation and paid GPU work wait for the model-profiling confirmation.

After confirmation:

1. Let `$vastai` select/create the approved target.
2. Write the local controller record with instance ID and remote artifact path
   before upload or SSH execution.
3. Let `$vastai-gpu-runtime` complete the selected target-mode preflight.
4. Run the confirmed SGLang-Omni workload and conditional profiler passes.
5. Collect artifacts before stopping/destroying the instance.
6. Independently verify provider terminal/non-billable state.

The glue orchestrates the controller, attempts, and artifact manifest. The
runtime skill verifies and operates only inside the selected target. The
official `$vastai` skill alone mutates provider state.

## Image and source parity

Resolve the active checkout's relevant CI workflow and preserve the base-image
digest. The base image alone is not CI parity: inspect setup actions and apply
the steps required by the experiment. Record installed core dependency
versions.

Upload the intended checkout, including authorized dirty changes. Prefer an
editable `--no-deps` overlay when the image already has the pinned dependency
set. Before model work, import `sglang_omni` and the benchmark module, record
their `__file__` paths, and require both to come from the uploaded checkout.

Inspect the image entrypoint and CI cleanup steps. Disable any automatic
clone/pull that could replace the uploaded revision. Reuse dependency/cache
setup as needed, but replace blanket GPU-process deletion with cleanup scoped
to the owned server/process group.

For Base-vs-Head comparisons, use two immutable application images or two
clean source overlays with the same parent image and dependency procedure.
Switching a runtime flag in one Head image does not create a Base revision.

## Benchmark and service branch

Use the repository benchmark entrypoint selected by model-profiling. Verify its
flags through source or `--help`; in particular, confirm whether it owns the
server or attaches to an existing one.

For a persistent service/client workload, read
[service benchmarks](references/service-benchmarks.md). It defines server
readiness, warmup/repetition ownership, A/B order, process cleanup, raw request
records, and SeedTTS-specific handling.

Declare one server owner across benchmark and trace branches. A separate
profiler pass may reuse the validated server when its API supports start/stop;
otherwise stop it and launch a separately owned trace server. Never let two
runners independently launch on the same port.

For parameter sweeps, multiple Vast target modes, or unattended collection,
read [benchmark recipes](references/benchmark-recipes.md). For prebuilt
Base-vs-Head images on one direct-container instance, also read
[direct-container Base/Head](references/direct-container-base-head.md).

Normal performance claims come from application metrics collected without
profiler injection. Preserve every repetition, request distribution, maximum
latency, correctness output, environment identity, and aggregation method.

## Profiler routing

For SGLang/PyTorch/Perfetto request traces, read
[application-native profilers](references/application-native-profilers.md).
Keep capture outside timed repeats and require nonempty, stable, parseable,
request-attributed artifacts.

When hardware counters are explicitly approved, let `$vastai-gpu-runtime` own
NCU installation, real-counter permission, bounded capture, export, and runtime
repair. This glue supplies the SGLang component driver or service command,
representative shape/dtype, target kernel/range, minimal metric question, and
correctness checksum. NCU replay timing is never service performance.

## Artifacts and retries

Keep caches separate from per-attempt evidence. Every attempt gets a new local
controller record, remote directory, and manifest; a retry never overwrites the
only pointer to a failure.

Copy back exact commands, configs, logs, request rows, traces/reports,
correctness outputs, environment/source/image fingerprints, and cleanup state.
Verify sizes and SHA-256 before accepting completion. Route the final report
and durable record exactly as model-profiling requires.

## Cleanup completion criterion

Stop only owned server/client/profiler processes. Collect artifacts before
provider teardown. Destroy a disposable instance created by the run and require
its absence from a fresh provider listing; `stopped` still incurs storage cost
and is not the completion state for this ownership class. For a pre-existing
target, follow the approved ownership policy and verify only owned runtimes
stopped.

The provider run is complete only when artifacts are verified, the local
controller has exited, and every created billable target has independently
verified cleanup. Never leave an instance running while waiting for
interpretation or a second profiling decision.

## References

- [service benchmarks](references/service-benchmarks.md): persistent
  SGLang service/client lifecycle and matched A/B execution.
- [application-native profilers](references/application-native-profilers.md):
  SGLang/PyTorch/Perfetto capture and attribution.
- [benchmark recipes](references/benchmark-recipes.md): target-mode
  reproductions, sweeps, and unattended orchestration.
- [direct-container Base/Head](references/direct-container-base-head.md):
  two immutable images on one Vast direct-container instance.
