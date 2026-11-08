---
name: radix-run-time
description: Manage sglang-community GPU assignments through radix, SSH access, quota deadlines, and validated GPU runtimes. Use for RadixArk machine access and execution readiness; workload-specific experiments belong in a separate skill.
---

# Radix GPU runtime

Use the current [Radix documentation](https://nodes.sglang.io/) and installed `radix --help` / subcommand help as the CLI contract. This skill owns machine allocation, SSH, environment readiness, quota management, artifact retrieval, and release. It does not choose benchmark workloads or profiling experiments.

## Allocation and authorization

- Select only **H100 or H200** GPUs. Honor an explicitly requested SKU; update the plan and get approval before substituting one for the other.
- **Require user approval covering each `radix assign`**, including replacement machines and retries. An explicit approval already covering the exact current target/count/duration is sufficient; record it instead of asking again. Login permission, available credits, a profiling request, and a generic continuation do not authorize assignment.
- Default to **4 hours**, expressed as `--duration 4h` so an environment default cannot silently increase it. A different duration or GPU count needs explicit approval.
- **Extend only with explicit authorization for the current task.** Permission to assign or continue work does not authorize renewal. If the user has explicitly authorized conditional renewal, use `--by 1h` within that authorization; otherwise ask before extending.
- When finished, retrieve evidence, stop owned work, and **release the task's assignment**, unless the user explicitly asks to keep it. Use the exact target, never a blanket release of all assignments.

## Discover and connect

1. Inspect `radix machines mine --json` and `radix machines available --json`; use their help if the installed interface differs. Reuse an explicitly provided assignment rather than acquiring another. Record assignment ID, machine ID, allocated GPU indices/count, endpoint, and expiry in UTC. Keep authentication material out of run artifacts; interactive unlock failures require the user to unlock locally.
2. For a new target, check that explicit approval covers its machine, H100/H200 model, GPU count, duration, and task. If it does not, present those details and wait for approval. Run only the approved command:

   ```bash
   radix assign <machine-id> --gpus <approved-count> --duration 4h
   ```

   The CLI defaults to all available GPUs (`--gpus 0` has the same meaning), so supply the approved positive count. Choose a target whose available hardware can satisfy the SKU constraint; verify the actual assignment after allocation.
3. Use the returned `Connecting: ssh -i <key-path> <user>@<ip>` information from assignment or `radix shell <machine-id>` as the connection source of truth. Do not infer endpoints from an unrelated prior run.
4. Inspect `~/.ssh/config` and its `Include` files for that IP. If it already has a `HostName` entry, reuse its alias and **skip adding another Host for the same IP**. Verify that the effective user/key match this assignment; resolve a conflict instead of overwriting existing settings.
5. For a new IP, append only its target-specific block, preserving existing configuration. Use `sglang-<host-or-node-name>`; resolve an alias collision before writing:

   ```sshconfig
   Host sglang-<host-or-node-name>
       IdentityFile <key-path>
       IdentitiesOnly yes
       HostName <ip>
       User <username>
   ```

   Validate with `ssh -G <alias>`, then connect with `ssh <alias>`. Verify new host keys against provider metadata; retain host-key checking.

## Runtime gate

Before model or kernel work, record these results in a unique task directory:

- **Ownership and GPU:** actual model, UUID, memory, MIG state, utilization, and compute applications from `nvidia-smi`. Map provider GPU indices to UUIDs; index numbering can change inside containers. Require the approved H100/H200 and allocated count. An idle-memory reading alone is insufficient; unresolved activity is a blocking ownership question.
- **Host or direct container:** identify the environment, writable paths, disk space, Python/uv, container engine, driver, and network readiness. Inspect command help instead of assuming that a `docker` executable is Docker rather than a Podman compatibility wrapper.
- **Environment identity:** use the workload's pinned image/dependencies where specified. In a host-container setup, disable automatic entrypoints that could clone a different checkout. Use an isolated source overlay and verify actual import paths.
- **GPU injection:** expose only assigned UUIDs. For an NVIDIA CDI runtime, use the exact assigned device selector rather than `nvidia.com/gpu=all` on a shared node. Verify the in-container device count and UUID, then perform one small CUDA operation.
- **CPU placement:** discover allowed CPUs and GPU NUMA affinity before binding; separate server, client, and telemetry placements and record the chosen sets. Do not change other tenants' processes or host settings.

Missing profiler permissions do not authorize privileged containers, host sysctl changes, driver repair, or killing another process. Preview any required repair and obtain separate approval for changes outside the owned runtime.

For a requested profiler, verify binary/version, actual attach or CUDA capture permission, intended worker attribution, and stable exported artifacts before a long run. CUDA Graph replay must appear as graph activity or node activity in the collected data. A successful `--version` or CUDA API trace alone does not establish GPU coverage.

## Four-hour deadline and renewal

Use the assignment's returned expiry, not allocation-request time plus four hours. Reserve enough time to stop work and copy required artifacts. Poll quota during long tasks and recheck before starting another long phase; once less than 30 minutes remains, report it and persist intermediate evidence.

If the remaining lease cannot cover the phase and cleanup, stop at a durable boundary. With explicit renewal authorization, target the recorded assignment and verify the new expiry:

```bash
radix extend <assignment-id-or-machine-id> --by 1h
```

Without that authorization, wait for approval while owned GPU work is stopped. A failed renewal leaves the old expiry in force. Extending a lease changes resource time, not the experiment's approved workloads, repeats, or profilers.

## Finish and release

1. Stop only task-owned servers, clients, profilers, containers, and orphaned descendants. Check process ownership, GPU memory/utilization, and port release.
2. Retrieve required reports, logs, manifests, and cited raw evidence; checksum-verify local copies before relinquishing access. Preserve pointers to bulky remote-only artifacts and explain their retention limits.
3. Recheck `radix machines mine --json`, then release the exact task machine with `radix release <machine-id>`. Release of a task-dedicated assignment is part of cleanup; do not release an assignment covering other ongoing user work. Clarify shared lifecycle ownership before using such a target.
4. Verify that the assignment is absent from the active-assignment list. Process cleanup and assignment release are separate completion checks. If release fails, report the still-active assignment and expiry rather than claiming cleanup is complete.

An explicitly retained assignment stays allocated; stop owned GPU work and report its remaining lease. On a user stop request, stop owned work promptly, preserve evidence, and release unless the user asks to retain the target.
