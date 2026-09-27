# Modal execution readiness

Read this reference before every Modal SGLang-Omni Sandbox run. It owns source
overlay, controller, persistence, retry, and cleanup mechanics. Profiler-only
installation and permission gates live in
[profiler readiness](profiler-readiness.md).

## Exact image and source

Inspect the relevant CI workflow as well as the digest-pinned base image; CI
may install dependencies after its container starts. Record the workflow path,
image digest, installed core versions, and every setup step reproduced by the
run.

Upload the intended checkout, including authorized dirty files, and record its
commit plus patch/content fingerprints. Work from the checkout root or set an
explicit `PYTHONPATH`, then import both `sglang_omni` and the selected benchmark
module and require their `__file__` paths to resolve inside that checkout.

Prefer a process-local source overlay:

```bash
cd "$EXACT_CHECKOUT"
PYTHONPATH="$EXACT_CHECKOUT${PYTHONPATH:+:$PYTHONPATH}" \
  python -m sglang_omni.cli --help
```

Give each A/B server and client its own explicit `PYTHONPATH`, and verify imports
inside each process environment. Installing two checkouts with `pip install -e`
or `uv pip install --system -e` targets the same distribution slot and makes the
second checkout replace the first. Use an isolated virtual environment or
target directory for an editable no-dependency install only when packaging or
entry-point behavior itself is under test. A `ModuleNotFoundError` for a
repository benchmark often means the command ran from the wrong root, not that
a package is absent.

## Pre-GPU harness checks

Keep this gate cheap and local-first:

- syntax-check controller and shell files;
- materialize the approved manifest and verify its exact ordered entries;
- verify source archives, hashes, imports, arm deltas, and output parents;
- exercise launch/readiness/request/stop, the fresh-server contract below, and
  artifact packaging with harmless local processes;
- run the manifest cursor fixtures described below.

Run relevant source tests once per source-content hash. Reuse that evidence for
orchestration-only edits; rerun only syntax, fixtures, lifecycle, and packaging.

Use a short CPU Modal Sandbox only for checks that require Modal itself, such
as Sandbox exec/lifecycle, mount behavior, or a prepared profiler image. A CPU
Sandbox is not a substitute for GPU checks and need not run the full model test
suite.

When using Modal, prove a compact Volume put/get hash round trip and discover
usable CPU IDs with `os.sched_getaffinity(0)` before `taskset`. Persist each
terminal result independently.

## Fresh-server contract

For repeated server visits in one Sandbox, give every launch a unique inherited
environment marker. Stop all processes carrying that marker, including
reparented descendants, then require an empty marker inventory and released GPU
memory before advancing. Do not rely on the launcher's original process group
alone.

Keep each arm's approved port stable. Check release with the launcher's exact
bind semantics and wait within a declared bound for TCP `TIME_WAIT`; reject an
automatic fallback port. CPU fixtures must cover an occupied port, real
`TIME_WAIT`, and a reparented marker process. Persist launch identity, bound
port, owned processes, GPU memory, and release results in the manifest ledger.

Output checks create and verify the parent directory only. The task owns its
fresh final directory; fixture-test the pre-existing-target failure instead of
creating that target during preflight.

## Schedule lock

Hash an immutable manifest containing the approved phase order, source arms,
placement, server lifecycle, workload order, substantial and shape warmups,
timed samples, the dual-server gain criterion and conditional tail, scorer
entries, cohort IDs/seeds, retained WAVs, and budget.
The cursor must reject extra or reordered entries and over-budget requests.
An explicitly approved early quality-gate failure or screening failure stops
later phases; record their skipped status and reason before teardown, rather
than silently proceeding or treating the run as complete.

For **both** screening and optional full qualification, assert the approved
timed visit order before GPU allocation:

```text
two live servers fit: A/A = [A1, A2, A2, A1]
                      A/B = [A, B, B, A] + [A, B] if gain criterion is unmet
one server only:      A/B = [A, B, B, A, A, B]; no A/A
```

For any model, an approved early quality check is **before** screening:
untimed `A -> B`, with matching 32-sample cohorts at `c1` and `c8` in each
arm. Score the approved model-appropriate metric (WER when meaningful) and
apply the preapproved gross-regression threshold before continuing. If
either workload or scorer is unavailable, resolve that in the plan. These
requests do not substitute for substantial or shape warmups.

Store workloads in order with `concurrency`, `shape_warmup_samples`, and
`timed_samples`. Screening uses **256 timed samples per workload per visit**.
Optional full qualification keeps the same visit order, shape-warmup policy,
and 256 samples per timed leg; it may use a broader workload map only when
that map and incremental cost are explicitly approved. Within each timed
visit, every workload has one adjacent, indivisible
`[shape warmup, timed leg]` pair. Never transpose visit and workload loops.

For `W` workloads, a dual-server stage has `4W` A/A and `4W` or `6W` A/B timed
legs, with the same number of shape warmups; a single-server stage has only
`6W` A/B timed legs and shape warmups. Screening timed requests total
`256 * 8W` or `256 * 10W` for dual-server runs, or `256 * 6W` for single-server
runs. After the fourth dual-server A/B visit, evaluate the predeclared
significant-gain criterion against the A/A noise floor. Record the last two
A/B visits as skipped with the deciding evidence when the criterion passes;
otherwise run them. Warm each new live server once at startup; for
the single-server schedule restart and substantially warm the server on **all
six visits**, including consecutive same-arm visits. Log starts, stops,
placements, and ports so a reused or silently substituted server fails the
manifest check. The single-server schedule has no independent A/A noise
calibration; do not claim that a small A/B delta clears one.

For TTS, retain and score only the timed-leg `c1`/`c8` WAVs from A/B visits
**3 B -> 4 A** after the stage's performance legs. Both arms must use the
same sample IDs and seeds. The optional early 32-sample quality check is
separate and scored before performance. Never add scorer coverage or a full
stage after approval by interpreting a generic "continue" as a new phase.

Fixture-test added phases, placement swaps, duplicate legs, extra requests,
and both conditional-tail outcomes; also check the selected server lifecycle
and scorer visit IDs.
Persist the manifest hash beside the actual ledger. A scope change gets a
new manifest after terminating the current paid Sandbox.

## Real GPU allocation gate

Before model download or server startup:

1. Verify the requested accelerator using `nvidia-smi -L`, including model,
   UUID, memory, and MIG state; stop on substitution.
2. Record utilization, memory, and compute applications, then run a CUDA
   operation in the workload's Python environment.
3. Repeat source-import and mount checks.
4. Run only the profiler gates named in the approved plan.
5. Persist and hash-verify each compact terminal result before advancing.

Keep NVML preflight commands portable: query GPU utilization/memory and MIG
state separately when a combined `nvidia-smi -q -d ...` form is unsupported,
and trim CSV fields before numeric or string comparison.

Container and host NVML PID namespaces may differ. Attribute GPU work with
before/boot/teardown bracketing and owned process ancestry, not an unresolved
PID alone.

## Volume evidence

Record whether each mounted Volume is v1 or v2.

- V1 Sandbox writes persist through background commits and a final commit on
  Sandbox termination.
- V2 mounts additionally support `sync <mountpoint>` inside the Sandbox.
- `Volume.commit()` requires a mounted Python Volume object. Calling it from
  the local controller fails, and installing the Modal SDK plus credentials in
  a Sandbox exec process does not turn that client object into the mount owner.

Use client-side `modal volume put` followed by `modal volume get` and a byte/hash
comparison for compact boundaries that must survive before teardown. Prove a
mount with `stat` plus a write/read/hash round trip rather than relying on the
host-specific text emitted by `mount`. Do not inject Modal credentials into the
workload image merely to call `Volume.commit()`. Close all output files before
a V2 `sync` or final Sandbox termination.

Create an artifact manifest before execution with three retention classes:

- `required-local`: reports, scorer outputs, per-sample scoring records,
  manifests, metrics, traces, and logs cited by conclusions;
- `remote-only`: generated media consumed by an approved early or main
  quality scorer until scoring completes, including TTS WAVs from the middle
  A/B B/A `c1`/`c8` pair;
- `disposable`: warmup and unscored media, and uncited intermediates.

Run the approved early model-specific quality scorer before screening. Score
the retained timed-leg TTS WAVs only after the corresponding performance visits.
Require complete, paired sample-ID coverage and persist per-sample scores
before teardown.
Other models use their approved quality workload/scorer. After termination,
selectively download and checksum every `required-local` artifact. Do not
download `remote-only` media unless necessary for diagnosis or a cited
conclusion. Treat an intentional exclusion as success; report failure only
when a required artifact is missing or fails verification. Check the installed
CLI/API before assuming glob or recursive-download behavior; enumerate exact
remote paths when needed.

## Retries and cleanup

Write the local controller record with Sandbox ID and remote run path
immediately after allocation. Every retry gets a new record and remote
directory. Correct one diagnosed layer and rerun only the checks invalidated by
that change; never overwrite the only pointer to a failed allocation.

Put owned-process stop, Sandbox termination, terminal polling, artifact
download, and inventory checks in independent `finally` steps. Terminate with
waiting, detach when required by the current SDK, reacquire terminal state, and
require zero app tasks and containers. A blocked local Modal wrapper after
confirmed remote cleanup may be terminated by its exact owned PID; record that
local lifecycle result separately.

Provider execution is complete only when the allocation is terminal, the app
has zero tasks/containers, and every cited artifact has been copied back and
checksum-verified. Never leave a paid Sandbox running while waiting for
interpretation or human input.
