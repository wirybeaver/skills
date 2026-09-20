# NVIDIA driver, container runtime, and NCU operations

Use this reference when preflight fails, remote changes are needed, or profiling results need interpretation.

## Safety boundaries

1. Inspect before repair. Preserve command output in the run record.
2. Classify the target before mutation. On an exclusive, disposable provider
   instance created for the current benchmark, narrowly scoped package,
   Docker/toolkit repair, service restart, and required host reboot may proceed
   without another pause only when those repair classes and a reboot cap were
   explicit in the approved execution plan. Otherwise preserve the failure and
   obtain approval before mutation.
3. On a shared, persistent, production, or ownership-unknown host, obtain
   explicit permission before package installation, Docker configuration
   changes, service restarts, or reboot.
4. Check for other users and running containers before restarting Docker. If
   unexpected users or unrelated workloads exist, reclassify the host as
   shared and stop before disruption.
5. Do not change NVIDIA kernel-module profiling policy automatically. Module
   reloads can terminate all GPU work and may require display-manager shutdown
   or a reboot. Capability escalation and privileged containers still require
   explicit approval.
6. Do not expose registry tokens in shell history, process arguments, logs,
   image layers, build arguments, or artifacts. Use `--password-stdin` and
   temporary Docker configuration directories.
7. Treat benchmark and profile commands as trusted shell input. Do not execute
   commands copied from untrusted issues or artifacts without review.

## Layered diagnosis

For a Docker host, test each layer independently and stop at the first failure:

1. **SSH and host:** login works; host identity and OS match expectations.
2. **Driver:** `nvidia-smi -L` works on the host.
3. **Docker daemon:** the user can access `docker version` and the server responds.
4. **Container toolkit:** `nvidia-ctk` and `nvidia-container-cli` exist; Docker exposes the NVIDIA runtime or CDI integration.
5. **GPU injection:** `docker run --rm --gpus all CUDA_IMAGE nvidia-smi -L` works.
6. **Application:** an application-level CUDA smoke and the exact unprofiled benchmark succeed.
7. **NCU binary compatibility, profiling branch only:** `ncu --version` works in the profiling environment and supports the target GPU/driver.
8. **Counter permission, profiling branch only:** a real metric such as `sm__cycles_elapsed.avg` is collected from a CUDA kernel.

A Docker runtime entry in daemon configuration does not prove that NVIDIA Container Toolkit binaries are installed. Verify actual binaries and a containerized `nvidia-smi` call.

For a direct container, skip Docker and toolkit checks. Require `nvidia-smi` and
an application-level CUDA smoke in the container. The provider owns the host
kernel driver; move to another host or contact the provider when that layer is
broken.

## Repair scope

`repair_remote_gpu_tools.sh` supports apt, dnf, yum, and zypper only when the required packages already exist in configured repositories. It intentionally does not add NVIDIA repositories because repository URLs, signing-key procedures, distributions, architectures, and package versions change. Use current official NVIDIA documentation for repository setup, then return to the script.

The repair script does not install the NVIDIA kernel driver, reload modules, or
repair a provider-managed driver. Use `driver_diagnostics.sh` to collect
evidence before following the host's approved driver-installation process.

Typical toolkit repair sequence:

1. Install `nvidia-container-toolkit`.
2. Back up `/etc/docker/daemon.json` if present.
3. Run `nvidia-ctk runtime configure --runtime=docker`.
4. Review the resulting daemon configuration.
5. Check workload impact, then restart Docker only when the approved plan
   includes that repair class and the host remains exclusive/disposable;
   otherwise obtain approval.
6. Re-run Docker GPU injection.

Prefer NCU inside the application image to reduce host coupling. If host NCU is required, install an exact package offered by the configured NVIDIA repository; package names often include a release version.

## Reboot and post-reboot validation

Use this sequence only when a driver, kernel-module, toolkit, or operating
system change requires a reboot. On an exclusive, disposable benchmark host,
proceed without another pause only when the approved plan names a reboot cap:
check for unexpected users and workloads and record the repair expected to take
effect. Otherwise obtain approval first. A reboot can interrupt unrelated work.

1. Confirm the current host identity and save its boot ID:

   ```bash
   host=gpu-host
   ssh_opts=(-o BatchMode=yes -o ConnectTimeout=5)
   before_boot_id=$(ssh "${ssh_opts[@]}" "$host" \
     'cat /proc/sys/kernel/random/boot_id')
   printf 'Before reboot: %s\n' "$before_boot_id"
   ssh "${ssh_opts[@]}" "$host" \
     'who; docker ps --format "table {{.ID}}\t{{.Names}}\t{{.Status}}" 2>/dev/null || true; nvidia-smi'
   ```

2. Reboot according to the ownership and approved-plan policy above. An SSH disconnect or exit status
   `255` is expected and does not prove that the reboot happened:

   ```bash
   ssh "${ssh_opts[@]}" "$host" \
     'if [ "$(id -u)" -eq 0 ]; then
        systemctl reboot || reboot
      else
        sudo -n systemctl reboot || sudo -n reboot
      fi' || true
   ```

3. Poll with a bounded deadline until SSH returns with a different boot ID:

   ```bash
   deadline=$((SECONDS + 600))
   after_boot_id=
   while (( SECONDS < deadline )); do
     candidate=$(ssh "${ssh_opts[@]}" "$host" \
       'cat /proc/sys/kernel/random/boot_id' 2>/dev/null) || {
         sleep 5
         continue
       }
     if [[ "$candidate" != "$before_boot_id" ]]; then
       after_boot_id=$candidate
       break
     fi
     sleep 5
   done

   if [[ -z "$after_boot_id" ]]; then
     echo "Host did not complete a verified reboot before the deadline" >&2
     exit 1
   fi
   printf 'After reboot: %s\n' "$after_boot_id"
   ```

   Adjust the deadline for the provider, but keep it bounded. The changed boot ID is the definitive reboot check; a temporary SSH outage alone is insufficient. If SSH reports a host-key mismatch, stop and verify the machine identity through the provider. Never automatically delete the old key.

4. Validate the host before running any container:

   ```bash
   ssh "${ssh_opts[@]}" "$host" '
     set -eu
     printf "boot_id="; cat /proc/sys/kernel/random/boot_id
     uname -a
     nvidia-smi -L
     nvidia-smi
     docker version
     command -v nvidia-ctk >/dev/null && nvidia-ctk --version || true
     command -v ncu >/dev/null && ncu --version | head -n 4 || true
     grep "^RmProfilingAdminOnly:" /proc/driver/nvidia/params || true
   '
   ```

5. Re-run `scripts/remote_gpu_preflight.sh` to validate Docker GPU injection and
   the application CUDA smoke. If profiling was requested, then run
   `scripts/ncu_smoke.sh` and require a real metric such as
   `sm__cycles_elapsed.avg`. Apply `--cap-add SYS_ADMIN` only when the
   permission policy requires it and the escalation is approved.

Do not benchmark when the boot ID is unchanged, `nvidia-smi` fails, Docker
cannot inject the GPU, or the application CUDA smoke fails. A failed NCU gate
blocks profiling claims only. If the driver fails after reboot, collect
`uname -r`, `lsmod`, `dkms status`, and `journalctl -k -b` before attempting
another repair; do not blindly reload modules.

## NCU permissions

On Linux, inspect:

```bash
grep '^RmProfilingAdminOnly:' /proc/driver/nvidia/params
```

When the value is `1`, unprivileged processes cannot access performance counters. For an approved profiling container, first try `--cap-add SYS_ADMIN`. `SYS_PTRACE` may be required for process inspection but does not by itself grant performance-counter access. `--privileged` grants broad host access and should be only a temporary diagnostic.

Changing the host policy to permit non-admin profiling is a security decision and usually involves NVIDIA module options plus a driver reload or reboot. Do not automate it on shared or production hosts.

Common failures:

- `ERR_NVGPUCTRPERM`: insufficient counter permission; inspect `RmProfilingAdminOnly` and container capabilities.
- No kernels profiled: wrong target process, workload did not execute CUDA, filter excluded kernels, or launch bounds skipped all work.
- Unsupported GPU/driver: use an NCU release that supports the GPU and is compatible with the installed driver.
- Report exists but metric is absent: the requested metric is unsupported, the profile did not capture a kernel, or CSV logging failed. Treat the gate as failed.
- Container GPU works but NCU fails: toolkit setup is likely healthy; focus on NCU version, target command, counter permission, and kernel selection.

## Benchmarking rules

- Warm caches and model state explicitly; record warmup count.
- Keep normal benchmark runs free of NCU.
- The helper's outer timing records include container startup and teardown. Use application-emitted timings when claiming steady-state in-process latency.
- Keep clocks, power limits, GPU occupancy, model/data versions, concurrency, batch shape, and request mix stable or record differences.
- Run enough normal repetitions for the metric being claimed and report the aggregation method.

## Profiling rules

- Enter this branch only when NCU or hardware-counter analysis is requested.
- Bound NCU with `--launch-count` and, only when known, a kernel regex.
- `run_remote_profile.sh` already uses `--target-processes all`; do not add a
  duplicate option.
- Start with `--set basic`; collect heavier section sets only for a specific question.
- NCU can replay kernels many times. Its wall time is profiling overhead, not normal latency or throughput.

## Artifact contract

A complete benchmark run should contain:

- `build.env` and build checksum data.
- Source commit, dirty state, repository remotes, Dockerfile, declared
  non-secret build arguments, sanitized command, source/context fingerprints,
  image tag, and digest. Secret-bearing build arguments are prohibited.
- `environment.txt` with host OS, GPU, driver, execution target, CUDA, and,
  for Docker hosts, Docker/toolkit and image inspection.
- Exact benchmark and optional server/health commands, mounts, non-secret
  environment values, warmups, and repetitions.
- Before/after boot IDs and post-reboot validation output when a reboot was required.
- Docker or direct-container GPU/application smoke output.
- Normal benchmark logs and timing records.
- Repairs performed, target-ownership classification, authorization basis,
  failures, and limitations.
- SHA-256 checksums after collection.

A profiling run should additionally contain the profile command, capabilities,
NCU options, hardware-counter smoke report/CSV, `.ncu-rep`, CSV/text export,
NCU log, and separately labeled replay-inflated profile timing.

Before posting results publicly, remove tokens, private registry configuration, private hostnames if necessary, signed URLs, dataset credentials, and sensitive command-line values. Do not remove information needed to reproduce the performance claim.
