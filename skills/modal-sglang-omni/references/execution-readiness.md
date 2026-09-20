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
- exercise launch/readiness/request/stop and artifact packaging with harmless
  local processes;
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

## Schedule lock

Hash an immutable manifest containing every phase, arm fingerprint, placement,
warmup, timed leg, scorer entry, cohort, shape, request count, and total budget.

The harness reads this list in order. Before each launch, the next full tuple
must match the cursor and remain within budget. Record terminal status, then
advance. Reject additions, duplicates, reordering, placement swaps, extra
requests, and work after the final entry.

Assert these flattened visit lists before GPU allocation:

```text
gate A/A substantial = [A1, A2]
gate A/A timed       = [A1, A2, A2, A1]
gate A/B substantial = [A, B]
gate A/B timed       = [A, B, B, A]

full A/A substantial = [A1, A2]
full A/A timed       = [A1, A2, A2, A1, A1, A2]
full A/B substantial = [A, B]
full A/B timed       = [A, B, B, A, A, B]
```

Store workloads as ordered records with independent `concurrency`,
`shape_warmup_samples`, and `timed_samples` fields. Do not derive one workload's
sample count from another.

For `G` gate workloads, each gate phase contains `2` substantial warmups,
`4*G` shape warmups, and `4*G` timed legs. For `F` full workloads, each full
phase contains `2`, `6*F`, and `6*F` respectively. Within every timed visit,
each workload is one adjacent, indivisible `[shape warmup, timed leg]` pair.
The cursor cannot advance to another workload between the two entries.

The timed request budget for one phase is the sum of its workload-specific
`timed_samples`, multiplied by `4` for gate or `6` for full qualification.

Fixture-test four failures before GPU allocation: added phase, swapped
placement, duplicate leg, and extra request. Persist the manifest hash beside
the actual ledger.

A scope change gets a new manifest. Terminate the current paid Sandbox before
requesting approval for it.

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
- `remote-only`: bulky generated media needed by a remote accuracy scorer;
- `disposable`: warmup outputs and uncited intermediates.

Run the accuracy scorer on Modal, require complete expected sample-ID coverage,
and persist its outputs before teardown. After termination, selectively download
and checksum every `required-local` artifact. Do not download `remote-only`
media unless it becomes necessary for diagnosis or a cited conclusion. Treat an
intentional exclusion as success; report failure only when a required artifact
is missing or fails verification. Check the installed CLI/API before assuming
glob or recursive-download behavior; enumerate exact remote paths when needed.

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
