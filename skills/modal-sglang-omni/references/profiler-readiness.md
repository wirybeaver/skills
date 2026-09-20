# Modal profiler readiness

Read this reference only when the approved Modal plan uses application-native
tracing, py-spy, nsys, NCU, or DCGM. Complete
[execution readiness](execution-readiness.md) as the shared prerequisite.

## Four independent gates

A profiler is ready only when all applicable gates pass:

1. **Image** — the exact image contains a compatible executable and runtime.
2. **Permission** — the real GPU Sandbox permits the profiler operation.
3. **Attribution** — capture covers the intended request/range/process rather
   than startup or another worker.
4. **Lifecycle** — the report closes, exports, persists, downloads, and verifies.

| Capability | Exact-image CPU gate | Real GPU gate |
|---|---|---|
| Application-native trace | Syntax/import and output-parent checks | One tiny request; wait for the expected trace to stabilize |
| py-spy | Version and synthetic launch | Attach or launch against the actual process tree |
| nsys | Version, `--help`, driver-script syntax | Tiny CUDA+NVTX capture followed by one export |
| NCU | Version and chip-qualified metric query | One real requested counter from a warmed CUDA kernel |
| DCGM | Binary and field inventory | Correct GPU/UUID plus nonzero fields under a known CUDA load |

Binary presence is not permission, attribution, or a successful lifecycle.
Persist stdout, stderr, return code, and output metadata for the first failed
gate before changing the image or controller.

## Install in the image, not the paid run

Inventory the digest-pinned CI image before installing anything:

```bash
command -v nsys && nsys --version
command -v ncu && ncu --version
command -v py-spy && py-spy --version
command -v dcgmi && dcgmi --version
```

One SGLang-Omni CI image used by prior H100 runs already contained nsys
2026.4.1, NCU 2025.3.1, and py-spy 0.4.2, while DCGM was absent. Treat that as
evidence for that digest only and inspect any CI setup steps that run after the
base image starts.

nsys and NCU are native CUDA-toolkit components, not Python packages. When one
is absent, keep independently authorized benchmark work profiler-free or build
a derivative image first. Pin the package source, tool version, parent digest,
and install commands, then validate the derivative in a CPU Sandbox. Ad hoc
native-profiler installation in a paid GPU Sandbox makes startup, parity, and
retry cost unbounded.

py-spy may be pinned as a Python tool, but reinstalling it cannot grant ptrace
permission. DCGM is usable only when its binary and a working host engine are
already exposed; never install or start host-level DCGM services in a Sandbox.

Completion criterion: one immutable image identity has every planned profiler
binary, script import, CLI option, and output parent verified before GPU work.

## Application-native tracing

Prefer SGLang/PyTorch tracing for ordinary request-range kernel attribution and
keep it outside timed benchmark repeats. `/stop_profile` may return before
asynchronous trace compression/export is durable. Wait for every expected
nonempty trace to appear, stop changing size, and parse successfully before
stopping the server.

Graph-replayed kernels may be absent from native kernel categories. When CUDA
graphs are in scope, use runtime launch evidence and capture logs instead of
counting missing kernel rows as eliminated work.

## py-spy

Try launch mode in the image gate and repeat on the actual allocation. PID
attach can vary by host and may fail with permission errors even when the
binary is installed. Record ptrace denial as a permission result; another
install is not a repair. Use an in-process alternative only when the profiling
methodology accepts it for the same question.

## Nsight Systems

Before loading the model, require a tiny CUDA+NVTX command to produce a
nonempty `.nsys-rep`, then export it once. `nsys --version` alone does not test
CUPTI injection, report finalization, or export support.

SGLang-Omni may fork its model worker. Wrap the full server launch and include
child processes; attaching only to the initial PID can miss the worker. When
the question needs only CUDA and NVTX, disable unavailable CPU sampling rather
than treating a `perf_event_open` restriction as total nsys failure.

Bound capture by request, NVTX range, or time. CUDA+NVTX+OSRT traces can contain
millions of events, and SQLite export can exceed the report size. Set size caps
before capture. On shutdown:

1. stop the owned process group;
2. let nsys finish report processing;
3. require a stable nonempty report and an export with expected CUDA/NVTX data;
4. record wrapper exit status separately.

Exit 143 with a complete export and a successful workload with no report are
different lifecycle outcomes.

## Nsight Compute

On the CPU image, verify that the installed release knows the target chip and
metric:

```bash
ncu --chips gh100 --query-metrics | grep -F 'sm__cycles_elapsed.avg'
```

Inside the real GPU allocation, record host policy when exposed and require one
real counter from a tiny warmed kernel:

```bash
grep '^RmProfilingAdminOnly:' /proc/driver/nvidia/params || true
ncu --target-processes all \
  --nvtx --nvtx-include 'modal.ncu.permission/' \
  --metrics sm__cycles_elapsed.avg \
  --launch-count 1 \
  --force-overwrite -o artifacts/permission \
  python permission_gate.py
```

The gate script must warm CUDA outside the range, execute and synchronize a
kernel inside the exact range, and emit a deterministic checksum. A missing
range, metric row, or checksum fails the gate. On `ERR_NVGPUCTRPERM`, preserve
the evidence and stop NCU work; Sandbox code cannot repair provider-host driver
policy.

Prefer a direct component driver with representative shapes, dtypes,
deterministic inputs, and an exact NVTX range. Launch-and-attach around a
persistent server can capture compile/startup kernels before readiness; those
counters remain startup evidence even if a later request succeeds. If the
service itself must be profiled, wrap the complete process tree with
`--target-processes all` and prove request attribution from timestamps/ranges.

Keep metric sets and launch counts small. Verify metric names with the installed
release, export machine-readable CSV plus reviewable details, and keep NCU
replay wall time separate from application latency. NCU wrappers may remain
alive after SIGINT; persist any closed report, bound the shutdown wait, and let
the execution-readiness `finally` path terminate the Sandbox.

## DCGM

Use DCGM only when `dcgmi`, a working host engine, and the intended GPU/UUID are
already visible. Validate fields under a known CUDA load. An all-zero trace may
mean the wrong GPU or sampling window. If the host engine is unavailable, use
NVML busy indication or the profiler selected by the methodology.

## Profiler completion criterion

For every cited profiler result, preserve tool path/version, exact command,
permission output, report/export, file size, checksum, target process/range,
and limitation. Then satisfy the artifact, terminal-state, and zero-task checks
in [execution readiness](execution-readiness.md). A profiler failure may limit
evidence, but it does not invalidate an independently completed unprofiled
benchmark.
