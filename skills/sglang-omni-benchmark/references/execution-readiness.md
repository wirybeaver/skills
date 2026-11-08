# Shared execution readiness

Read before every SGLang-Omni benchmark. Provider-specific allocation, mount persistence, and release remain in the provider adapter.

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

Export `SGLANG_OMNI_TORCH_COMPILE_DEFAULT=0` to every model-server process. Keep the environment value fixed across arms, lock it in the manifest, and verify process inheritance. Change engine compilation only through explicit stage configuration; component-specific compile switches remain explicit as well.

## Pre-GPU harness checks

Keep this gate cheap and local-first:

- syntax-check controller and shell files;
- materialize the approved manifest and verify its exact ordered entries;
- verify source archives, hashes, imports, arm deltas, and output parents;
- exercise launch/readiness/request/stop, the fresh-server contract below, and
  artifact packaging with harmless local processes;
- run the manifest cursor fixtures described below.

Keep provider-specific transport checks separate from source tests. Runtime preflight does not prove numerical correctness or performance.

## Fresh-server contract

For repeated server visits on one target, give every launch a unique inherited
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

## Manifest and cursor

Hash the approved manifest before allocation or execution on an existing target. Apply the visit order, counts, warmups, stop conditions, and scorer coverage from [the benchmark contract](../SKILL.md), not a controller's inherited defaults. Persist the manifest hash beside the actual ledger.

Fixture-test added or reordered phases, duplicate or extra legs, request-budget violations, both conditional-tail outcomes, and terminal skipped entries. Test gain bounds below 4%, above 6%, touching either boundary, an unusually low A visit, overlapping arm values, mixed-workload outcomes, and invalid metrics.

A scope change needs a new plan and explicit approval. Stop owned GPU work and complete the provider's cleanup before waiting; a generic continuation resumes only the approved entries.

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

## Evidence and source-test reuse

Classify artifacts before execution: required-local reports, manifests, raw request/scorer records, logs, commands and cited traces; remote-only bulky media until approved scoring finishes; disposable warmups and uncited intermediates. Verify paired sample-ID coverage and checksums of every cited local artifact. Keep interpretation separate from metric extraction, and do not present instrumented diagnostic timings as clean serving performance.

Source tests are keyed by source content. Run the smallest relevant tests when source changes. For orchestration-only edits, rerun syntax, manifest, lifecycle, and persistence fixtures; reuse source-test evidence while hashes remain fixed. CPU preflight cannot establish GPU parity, model quality, or performance.
