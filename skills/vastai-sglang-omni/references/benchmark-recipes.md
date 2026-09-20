# Reusable benchmark recipes

Use this reference for multi-execution-target comparisons, parameter-grid
sweeps, or long runs that must collect artifacts and stop billing without
interactive supervision. Keep model-, dataset-, server-, and metric-specific
commands in the benchmark workspace rather than copying them into the skill.

## Reproduce multiple execution targets

Apply the same benchmark contract to each supported target:

1. Pin the source revision and application image digest.
2. Select an offer from machine-readable provider output.
3. Create the target and poll it with a deadline and terminal-state handling.
4. Resolve the current SSH endpoint and use a per-run known-hosts file.
5. Run the target-specific GPU preflight.
6. Run identical application commands and benchmark inputs.
7. Collect artifacts and checksums before destroying the target.
8. Verify that every created instance is absent from the final provider list.

Let `$vastai-gpu-runtime` map the target to one of its three workflows:

- Bootstrap pinned source inside a compatible provider direct container.
- Launch the digest-pinned application image as the direct container.
- Launch a VM, validate Docker GPU injection, and run the image through Docker.

Use the official `$vastai` skill for provisioning and
`service-benchmarks.md` for persistent server/client lifecycle. Runtime repair
and target-mode details stay in `$vastai-gpu-runtime`; do not duplicate them in
benchmark-specific orchestration.

For a source comparison that switches prebuilt images on one direct-container
GPU instance, read
[direct-container-base-head.md](direct-container-base-head.md).

Worked example:
[three Vast.ai workflow reproduction, revision
e08341b6](https://gist.github.com/wirybeaver/c45d7c62c78fd38d8c24f71b3ad943c3/e08341b6d704fd0652108c3699dd7c96e6101c69).

## Run a parameter-grid sweep

Keep the orchestration explicit and auditable:

1. **Smoke:** run the baseline and one candidate on a minimal sample before the
   full matrix.
2. **Define:** record the baseline, candidate image digests, parameter grid,
   dataset/model revisions, concurrency levels, warmup, repeats, and run order.
3. **Execute:** isolate each configuration's server lifecycle and artifact
   directory. Let either the application or the outer runner own repetition,
   never both.
4. **Signal:** write a status file containing the active configuration,
   timestamps, exit code, and terminal success or failure.
5. **Watch:** use a bounded watcher for unattended runs. The watcher must detect
   terminal state, collect results, produce checksums, redact transient access
   data, and then destroy or stop the instance.
6. **Aggregate:** preserve per-repeat values and calculate the declared summary
   statistics and deltas against baseline.
7. **Select:** state the eligibility gates and ranking policy before choosing a
   parameter set. Correctness gates must precede performance ranking.

For service benchmarks, normally retain:

- Throughput and mean, P95, and P99 latency.
- Mean real-time factor when the application emits it.
- Correctness metrics, evaluated and skipped request counts, and raw outputs
  needed to reproduce them.
- Mechanism-specific evidence, such as operation counts or batch-size
  distributions, when the optimization claims to change that mechanism.
- Per-repeat values, aggregation method, run order, environment, logs, and
  immutable provenance.

Worked example:
[ARK-ASR-3B parameter sweep, revision
a4a4500d](https://gist.github.com/wirybeaver/a398c4eddc021be9f14986d18a54c6e2/a4a4500d69be010b333b504b7571925f145524d0).

Worked Base-vs-Head direct-container example:
[ARK-ASR encoder CUDA Graph full SeedTTS-EN benchmark](https://gist.github.com/wirybeaver/079e2faf1e95e314ec91994511f4ae95).

## Abstraction boundary

Adapt small project-specific orchestration scripts from these recipes. Do not
add a generic matrix runner to this skill until another independent benchmark
demonstrates the same interface and lifecycle needs.
