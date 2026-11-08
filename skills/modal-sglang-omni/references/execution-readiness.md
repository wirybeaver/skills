# Modal execution readiness

Read [shared execution readiness](https://raw.githubusercontent.com/wirybeaver/skills/main/skills/sglang-omni-benchmark/references/execution-readiness.md) first on every run. This reference adds Modal transport, Volume persistence, and Sandbox teardown. Read [profiler readiness](profiler-readiness.md) only for an approved profiler pass.

## Modal transport gate

When using Modal, prove a compact Volume put/get hash round trip and discover
usable CPU IDs with `os.sched_getaffinity(0)` before `taskset`. Persist each
terminal result independently.

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
