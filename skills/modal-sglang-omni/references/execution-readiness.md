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

Prefer the environment's equivalent of:

```bash
cd "$EXACT_CHECKOUT"
uv pip install --no-deps -e .
```

Use an editable no-dependency overlay only when the image already has the
pinned dependency set. A `ModuleNotFoundError` for a repository benchmark often
means the command ran from the wrong root, not that a package is absent.

## CPU command-envelope gate

Run the exact controller and shell envelope against harmless commands in a
short CPU Sandbox before the first GPU allocation. Prove that:

- every upload and import resolves to the intended source;
- every output and shell-redirection parent exists before command launch;
- launch, readiness polling, request, owned-process stop, and cleanup commands
  return their expected codes;
- a compact boundary survives a client-side `modal volume put`, immediate
  `modal volume get`, and byte/hash comparison;
- each command result is persisted independently before the next terminal
  gate.

Keep growing controller history local. A prior run exceeded Modal's 65,536-byte
exec argument limit by embedding already-persisted NCU help text into cumulative
JSON. Transfer files or compact history-free records instead.

A CPU Sandbox normally lacks GPU injection, so absence of `nvidia-smi` there is
expected. Record cgroup files as observations; their encoded quota/ceiling need
not equal the requested Modal CPU or memory value. Use separate commands for
identity, mounts, source hashes, runtime, and tools: one long `set -e` command
hides the failed predicate and may exit before diagnostics become durable.

Check every shell dependency. At least one CI image lacked `rg`; use
`grep`/`find` or add a pinned package to the prepared image.

Completion criterion: the exact controller envelope, source imports, output
parents, compact persistence, and cleanup all pass without a GPU.

## Real GPU allocation gate

Before model download or server startup:

1. Verify the requested accelerator using `nvidia-smi -L`, including model,
   UUID, memory, and MIG state; stop on substitution.
2. Record utilization, memory, and compute applications, then run a CUDA
   operation in the workload's Python environment.
3. Repeat source-import and mount checks.
4. Run only the profiler gates named in the approved plan.
5. Persist and hash-verify each compact terminal result before advancing.

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
comparison for compact boundaries that must survive before teardown. Do not
inject Modal credentials into the workload image merely to call
`Volume.commit()`. Close all output files before a V2 `sync` or final Sandbox
termination. After termination, download the exact run directory and verify
file sizes and hashes. Check the installed CLI/API before assuming recursive
directory download; when it lacks that behavior, enumerate the remote run and
download each expected file through a checked exact-path operation.

## Retries and cleanup

Write the local controller record with Sandbox ID and remote run path
immediately after allocation. Every retry gets a new record and remote
directory. Correct one diagnosed layer and re-run all earlier gates; never
overwrite the only pointer to a failed allocation.

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
