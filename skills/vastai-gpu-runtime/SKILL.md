---
name: vastai-gpu-runtime
description: Prepare and validate NVIDIA GPU execution targets rented through Vast.ai, including source-pinned images, SSH direct containers, Docker GPU injection, CUDA/NCU readiness, bounded command execution, repairs, artifacts, and verified shutdown. Use for Vast.ai GPU runtime work; use vastai-sglang-omni to design SGLang-Omni benchmarks or profiling experiments.
---

# Vast.ai GPU runtime

This skill is the execution-environment module beneath workload-specific
benchmark skills. Use the official `$vastai` skill for offers, instances,
templates, volumes, billing, SSH endpoints, and provider state. This skill owns
what happens inside the selected target: image/source identity, GPU runtime
readiness, exact command execution, optional NCU access, artifact transfer, and
terminal cleanup.

It does not choose model workloads, concurrency, warmup, repetitions, A/B
variables, correctness policy, or evidence conclusions.

## Required interface

Resolve before changing remote state:

- exact source revision and dirty state;
- target mode: Docker host or SSH-accessed direct container;
- bootstrap image or immutable application-image digest;
- one exact trusted workload command and artifact directory;
- target ownership: new disposable instance or existing/shared target;
- whether NCU hardware counters are required.

Ask only when a missing value changes correctness, cost, or host safety. Never
infer an SSH target merely because it exists in local configuration or prior
artifacts.

## Provider bridge

Read [target modes](references/target-modes.md) to select the runtime shape.
Let `$vastai` own every control-plane command and decision. Consume its resolved
provider block—offer, instance/template, image, disk, SSH endpoint/mode, hourly
price, timeout, and destroy/stop command—rather than searching, selecting, or
creating provider resources here.

For a new exclusive instance, an approved execution plan may include narrowly
scoped package repair, Docker configuration backup/update, Docker restart, and
a required reboot. Preview and record repairs first. Shared, persistent,
production, or ownership-unknown targets require separate approval before
mutation, restart, or reboot. Capability escalation and privileged containers
always require explicit approval.

## Target modes

Choose exactly one:

1. **Direct container, SSH bootstrap** — rent a compatible provider
   CUDA/PyTorch image, upload the exact source, install only its pinned runtime,
   and execute directly in the provider container.
2. **Direct container, prebuilt image** — rent a template/instance whose outer
   image is the immutable application image and execute directly.
3. **Docker host** — rent a GPU VM/bare-metal host, verify Docker and NVIDIA
   Container Toolkit, then run the immutable application image with GPU
   injection.

An existing provider template is not an interchangeable image slot. Reuse its
declared image/startup/ports unchanged, or create a separate template.

## Attempt lifecycle

Give every attempt a stable run ID and unique local/remote artifact directory.
Before upload or execution, record the instance ID, source/image identity,
target mode, ownership, exact artifact path, and cleanup action. A retry gets a
new record and directory.

Put artifact collection and cleanup in independent finalization steps. For an
instance created for the run, verify provider terminal/non-billable state and
absence from the active-instance list. On an existing target, stop and verify
only owned processes/containers.

Completion criterion: every attempt remains identifiable, every cited artifact
is checksum-verified, and every created billable instance or owned runtime is
independently verified stopped.

## Pin image and source

Use a digest-qualified parent/application image where practical. A mutable tag
or unpinned checkout is insufficient for a comparison. For source comparisons,
build Base and Head with the same parent, Dockerfile, build arguments, and
dependency procedure except for source revision.

Verify the exact workload command against the selected source through its
`--help`, a dry smoke, or source inspection. A runner dry-run validates runner
arguments only; it does not validate the nested command.

Build when needed with `scripts/build_publish_image.sh`. Record Dockerfile,
context, source state, registry reference, immutable digest, and install
commands for every image. The helper accepts only declared non-secret build
arguments, stores their values in the private run metadata, redacts them from
console/command output, and fingerprints both the Git source and a conservative
superset of the non-`.git` Docker context.

## Runtime preflight

For a Docker host, run `scripts/remote_gpu_preflight.sh`. It must prove host
driver health, Docker daemon access, NVIDIA Container Toolkit binaries, GPU
injection, and an application-level CUDA operation in the selected image.

For a direct container, run `scripts/direct_gpu_preflight.sh`. It must prove
`nvidia-smi` and an application-level CUDA operation in the exact environment
that will execute the workload. Nested Docker is not required.

NCU is not part of ordinary runtime readiness. A missing profiler cannot block
an independently requested unprofiled workload.

## Execute the caller's command

Use `scripts/run_remote_benchmark.sh` for Docker hosts and
`scripts/run_direct_benchmark.sh` for direct containers. The caller owns the
workload semantics, warmup/repetition count, request order, correctness gates,
and aggregation; pass them through without reinterpretation.

Preserve exact commands, environment, stdout/stderr, exit status, process/GPU
state, and raw artifacts. Application-emitted steady-state metrics—not outer
SSH/container wall time—support performance claims.

Completion criterion: every requested command exits successfully, processes
the expected work, passes the caller's correctness gate, and produces the
declared raw artifacts.

## Optional NCU branch

Enter only when the caller requests hardware counters. Read
[operations and permissions](references/operations.md) before installing NCU,
changing profiler permissions, or considering a reboot.

Prefer compatible NCU inside the application image. Run an unprofiled baseline,
a one-kernel real-counter smoke, then a bounded profile with
`--target-processes all`. NCU replay wall time is profiler overhead, not
application latency.

Completion criterion: the smoke report contains a real requested metric; the
bounded `.ncu-rep` and checked export contain the predeclared target
kernel/range and requested metric rows; and normal metrics remain separate from
replay-inflated findings.

## Repair the failed layer only

Use `scripts/driver_diagnostics.sh` for read-only driver evidence. Use
`scripts/repair_remote_gpu_tools.sh` in preview mode before any toolkit or
Docker repair. The skill does not automate NVIDIA kernel-driver installation or
module reloads; on a provider-managed direct container, select another host or
contact the provider when the driver is broken.

After repair, rerun the focused failed check and the complete target preflight.

## Collect and hand off

Use `scripts/collect_artifacts.sh` or a checked Vast copy command. Produce a
SHA-256 manifest and return source/image provenance, target mode, GPU/driver,
exact commands, repairs, raw artifact location, and cleanup evidence to the
caller. Interpretation and final reporting stay with the workload-specific
skill.

## Resources

- [references/target-modes.md](references/target-modes.md): direct-container,
  prebuilt-image, and Docker-host runtime invariants.
- [references/operations.md](references/operations.md): driver/runtime repair,
  reboot safety, NCU installation, permissions, and failure modes.
- `scripts/build_publish_image.sh`: reproducible image build/publication.
- `scripts/remote_gpu_preflight.sh`: Docker-host GPU validation.
- `scripts/direct_gpu_preflight.sh`: direct-container GPU validation.
- `scripts/run_remote_benchmark.sh`: exact-command Docker-host runner.
- `scripts/run_direct_benchmark.sh`: exact-command direct-container runner.
- `scripts/ncu_smoke.sh`: real-counter gate.
- `scripts/run_remote_profile.sh`: bounded Docker-host NCU runner.
- `scripts/driver_diagnostics.sh`: read-only driver evidence.
- `scripts/repair_remote_gpu_tools.sh`: previewed runtime repair.
- `scripts/collect_artifacts.sh`: artifact copy and checksums.
