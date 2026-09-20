---
name: modal-sglang-omni
description: Run SGLang-Omni profiling and benchmarks on Modal Sandboxes with repeatable source overlays, profiler image/readiness gates, durable Volume evidence, and verified cleanup. Use for Modal execution including torch.profiler, py-spy, nsys, NCU, or DCGM checks.
---

# Modal SGLang-Omni profiling

This is a provider glue skill. Use it together with the official `$modal`
skill and the repository-defined `$model-profiling` skill; it does not replace
either one and does not duplicate the five-layer methodology.

## Source-of-truth contract

Use `$model-profiling` to resolve the source of truth for profiling behavior.
It fetches the latest GitHub main-branch `SKILL.md`, `METHODOLOGY.md`, and
`PROMPT_TEMPLATE.md`. At every invocation, read those files completely and
apply their current wording. Keep the authoritative URLs in model-profiling
only so a source change requires one edit.

Read the official `$modal` skill for current Modal APIs, authentication,
Sandbox lifecycle, GPU selection, and CLI/SDK behavior. Read any existing
`.profiling-runs/<model>/profile.md` and cited artifacts as required by the
source workflow.

If the source files cannot be retrieved, report the retrieval failure.
If this glue conflicts with the source workflow, the source workflow wins.
Do not copy its layer ordering, evidence rubric, report schema, confirmation
rules, or result-tracking policy into this file.

Translate pre-plan target checks to Modal without weakening them. Run local
read-only checks before presenting the plan. When a source-workflow check such
as `nvidia-smi` or exact-image py-spy requires creating a Modal Sandbox, list it
as an unresolved provider check in the plan and execute it in the approved CPU
or GPU preflight. Creating provider resources still waits for confirmation;
the deferred check remains a gate rather than being skipped.

## Provider bridge

Let `$model-profiling` own the plan, scope, gates, executor prompt, evidence,
report, and durable-record decisions. This skill adds only the Modal execution
block and lifecycle:

1. While preparing the plan, resolve current Modal facts through `$modal`, read
   [execution readiness](references/execution-readiness.md), and append the
   provider block to the model-profiling executor prompt: app/workspace and
   profile, image, checkout/commit, GPU request, timeout, secret names, Volume
   mounts, artifact paths, copy-back command, cleanup command, an explicit arm
   manifest, and the fully materialized execution schedule. When the plan
   names a profiler, also read
   [profiler readiness](references/profiler-readiness.md). Never invent or print
   secret values.
2. Do not create a GPU Sandbox, download weights, or launch a server before
   the first confirmation required by `$model-profiling`.
3. After that confirmation, run the execution reference's CPU command-envelope
   gate before allocating a GPU. Reading the references prepares the plan;
   creating a Sandbox or changing provider state waits for confirmation.
4. Persist intermediate evidence and copy the final report and cited raw files
   into the model-profiling output directory.
5. Apply the source skill's executor continuation, second confirmation, A/B,
   Layer 5, cleanup, and reporting rules without restating or changing them.

## Provider repeatability

### Image and source

Use the active checkout's relevant CI workflow to resolve the base image.
Preserve its registry digest; if it uses a mutable tag, resolve and record the
digest before running. Record the workflow path and installed core dependency
versions. CI may install dependencies after starting its container, so the
base image alone does not establish environment parity: inspect the setup
steps and apply those needed by the experiment. Keep any diagnostic package
changes explicit in the run record.

Upload the intended checkout, including authorized uncommitted changes, and
verify that the server imports that source. Record the commit and a patch or
content fingerprint for dirty files. Do not substitute the image's bundled
checkout. Resolve the image digest and account/run identifiers per invocation
rather than hardcoding them into this skill.

Run project commands from the checkout root with an explicit `PYTHONPATH` for
that checkout. Before model work, import both `sglang_omni` and the selected
benchmark module in every source arm, record their resolved file paths, and
require them to come from the intended checkout. Keep A/B arms process-local:
do not sequentially replace one system editable install with another. Use an
isolated editable `--no-deps` install only when packaging or entry-point
behavior itself must be tested; resolving dependencies again can invalidate
comparison parity.

For every comparison, classify the experiment as source-controlled,
configuration-controlled, or hybrid. Record each arm's logical role, exact
repository commit, dirty-content fingerprint, source archive hash, launch
arguments, and intended difference from the other arm. Equal commits are
valid only when an explicitly configuration-controlled experiment has a
non-empty arm-specific configuration difference. A source-controlled
experiment must identify every arm by its exact commit rather than describing
both as the current `HEAD`.

Validate this arm manifest in the CPU command-envelope gate. Materialize each
arm independently, assert its commit and content hash, import from its expected
source path, and verify the declared source or configuration delta. Stop before
GPU allocation if a source-controlled comparison resolves to equal source
trees, or if a configuration-controlled comparison has no effective
configuration difference. Do not silently repair either condition by changing
the approved experiment.

### Paired multi-shape execution

When an approved experiment contains multiple arms, repeats, and workload
shapes, materialize the complete schedule before creating a GPU Sandbox. Name
the outer, middle, and inner loops and list the actual arm-visit order; prose
such as "three pairs at each concurrency" is not a complete schedule.

For a resident-server comparison whose approved protocol treats an arm visit
as the outer unit, use `repeat -> arm visit -> shape/concurrency -> shape
warmup -> timed leg`. For example:

```text
round 1: A1[c1,c8,c16,c32] -> A2[c1,c8,c16,c32]
round 2: A2[c1,c8,c16,c32] -> A1[c1,c8,c16,c32]
round 3: A1[c1,c8,c16,c32] -> A2[c1,c8,c16,c32]
```

This is an orchestration default, not a replacement for `$model-profiling`'s
experiment design. Preserve a different loop order when the confirmed plan
specifies one, and never transpose confirmed loops while implementing the
harness.

Distinguish server-lifecycle warmup from per-shape warmup. Run substantial
warmup after readiness and a real smoke request but before that server's first
timed arm visit; repeat it after every server restart or source-arm
replacement. Record any convergence pass separately, and exclude both passes
from timed results. Run shape-specific warmup immediately before its timed leg
inside each arm visit. The approved schedule must state warmup sizes, cohort
hashes, and whether cohorts are reused or disjoint.

### Conditional profiler readiness

Keep ordinary benchmarking independent of profiler availability. When the
approved plan includes profiler work, read
[profiler readiness](references/profiler-readiness.md) and classify
each failure as image/tool absence, source-path error, runtime permission,
profiler lifecycle, or workload failure before attempting a repair.

This skill owns every Modal profiler branch, including NCU hardware counters.
The readiness references define image preparation, permission gates, bounded
capture, profiler lifecycle, Volume evidence, and terminal cleanup. Use the
repository methodology only to decide when each profiler is warranted and what
question its evidence must answer.

### GPU and Sandbox

Preserve the user's requested hardware. When the experiment requires a fixed
H100, use `gpu="H100!"` to prevent an automatic H200 upgrade, and verify the
allocated device during preflight. See the official
[GPU guide](https://modal.com/docs/guide/gpu).

Use a GPU-capable `modal.Sandbox` with the current SDK. Check current official
Sandbox documentation and SDK behavior before selecting backend options.
Avoid hardcoding a classic/V2 switch: backend routing can change, and Modal's
[V2 reference](https://modal.com/docs/guide/sandbox-v2) describes automatic
fallback to the previous backend for unsupported features such as GPUs.

Reuse the Sandbox for the verified source overlay, server launches, HTTP checks,
and profiler commands within the approved experiment. When the plan names a
native profiler, prepare it in a digest-pinned derivative image and validate
its command envelope in a CPU Sandbox before allocating the paid GPU. Give the
session a bounded lifetime and retain its ID so interrupted orchestration can
recover logs and terminate the allocation.

### Persistence and run record

Mount a Modal Volume for model caches and experiment artifacts. Keep reusable
caches separate from per-run directories so later runs cannot overwrite cited
evidence. Record both remote and local artifact paths, persist intermediate
results, and copy the report and its cited artifacts back to the output
directory required by model-profiling before teardown.

Classify run artifacts as required-local, remote-only, or disposable before
execution. For evaluations that generate bulky media, run the accuracy scorer
against the media on Modal, verify complete sample coverage, and copy back the
scorer outputs, manifests, metrics, and cited logs rather than the media itself.
An intentionally excluded remote-only artifact is not a copy-back failure.

Every Modal run should have a stable run identifier and record:

- repository commit SHA and dirty state;
- an experiment manifest containing arm identities, source/configuration
  deltas, loop nesting, warmup policy, cohort hashes, and intended leg order;
- an append-only actual-leg ledger containing sequence number, server/arm,
  source and configuration fingerprints, phase, concurrency, cohort hash,
  timestamps, status, and artifact directory;
- model checkpoint revision or resolved snapshot;
- Modal image, GPU type, app/profile, Volume, and timeout;
- exact launch and benchmark commands;
- raw artifact paths and the report path.

Write the local controller record, including the Sandbox ID and exact remote
run path, immediately after allocation and before file upload or remote exec.
Use one record per attempt; never overwrite the only pointer to an earlier
allocation during a retry.

Before accepting results, compare the actual-leg ledger with the approved
experiment manifest. A missing, duplicated, reordered, or wrong-arm timed leg
is a protocol failure rather than benchmark evidence.

Reuse the Volume for caches, but never treat cached weights or an existing
Sandbox as proof that the environment is unchanged. Re-run the provider
preflight and let the source skill decide whether the environment fingerprint
invalidates prior evidence.

## Lifecycle and handoff

Use the current official Modal lifecycle API. Always put Sandbox termination
and detach in a `finally` path, then independently verify the terminal state
and artifact copy-back. Persist intermediate evidence before long or
preemptible operations.

Before reporting completion, independently check provider cleanup and
copy-back. Let the source skill define report validation, methodology routing,
commit behavior, durable tracking, and final status text.
