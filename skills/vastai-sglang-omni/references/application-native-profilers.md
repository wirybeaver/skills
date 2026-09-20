# Application-native profiler traces

Use this reference when the user wants profiler evidence from the application
runtime itself, such as SGLang internal profiler, PyTorch profiler, Chrome
trace, TensorBoard trace viewer, or Perfetto `.trace.json.gz` output.

This is **not** the NCU branch. Keep the normal benchmark workflow and collect
the application's profiler artifacts. NCU is only for requested hardware-counter
analysis.

## Pattern

1. **Run the same target as the benchmark.** Use the already validated Docker
   host or direct-container environment. Do not add nested Docker to a direct
   container.
2. **Keep normal timings separate.** First run the unprofiled benchmark branch
   for performance claims. Run profiler passes separately because profiler
   hooks, trace writes, and extra synchronization can perturb latency.
3. **Use the application contract.** Start/stop the profiler through the
   application's supported API or CLI, then run a small representative pass.
   Record the exact start/stop payloads and pass command.
4. **Collect trace and event artifacts.** Preserve raw traces, request-event
   JSONL, generated reports, screenshots, launch commands, server logs, and a
   SHA-256 manifest.
5. **Report profiler evidence as evidence.** Make performance claims from the
   unprofiled benchmark metrics. Use profiler traces to explain launch
   behavior, stage breakdowns, or scheduling behavior.

Before capture, predeclare the expected trace files, target request/range or
owned process, and the event classes needed for the claim. A profiler stop API
may return before asynchronous export finishes; wait for every expected file to
be nonempty, size-stable, and parseable before stopping the service or
collecting artifacts.

Completion criterion: the unprofiled benchmark succeeds; the profiled pass
exits successfully; every expected raw trace is nonempty, stable, parseable,
and contains evidence attributable to the predeclared request/range/process;
and the report clearly separates normal metrics from profiler observations.

## SGLang / SGLang-Omni internal profiler

For SGLang-Omni services exposing profiler routes:

- `POST /start_profile` starts torch profiling and request-event recording.
- `POST /stop_profile` stops torch profiling.
- `trace_path_template` controls where `*.trace.json.gz` files are written.
- `event_dir` controls where request-event JSONL files are written.
- `enable_torch=true` is required for torch/Perfetto trace output; use
  request-event-only routes only when no torch trace is needed.

Minimal start payload:

```json
{
  "run_id": "example-run",
  "trace_path_template": "/workspace/example/trace/trace",
  "event_dir": "/workspace/example/events",
  "enable_torch": true
}
```

Recommended SGLang-Omni flow:

1. Launch the server and verify `/v1/models`.
2. Run one warmup pass before profiler start.
3. `POST /start_profile` with a unique `run_id`.
4. Run one bounded representative client pass.
5. `POST /stop_profile`.
6. Build an event report with `sglang_omni.profiler.views.build_report`.
7. Open `*.trace.json.gz` in Perfetto and capture a flame-chart/timeline
   screenshot; if upload is blocked, download the trace locally.

Preserve:

- `launch.txt`, `server.log`, profiler start/stop JSON responses;
- client result JSON/log for warmup and profiled pass;
- `events/*.jsonl`, `event_report.json`;
- `trace/*.trace.json.gz`, Perfetto screenshot if available;
- `trace_summary.json` with launch-count checks when relevant;
- `SHA256SUMS`.

## Worked example: ARK-ASR SeedTTS H100 direct container

The ARK-ASR encoder CUDA Graph prototype used a direct-container, prebuilt
application image on H100. Normal benchmark runs measured eager vs encoder CUDA
Graph on SeedTTS-50 and full SeedTTS EN with the pre-LM cache disabled. A
separate SeedTTS-50 concurrency-32 run used SGLang-Omni internal profiler
instead of NCU and produced Perfetto `.trace.json.gz` files plus request-event
reports.

Public script gist:

```text
https://gist.github.com/wirybeaver/7fbd5b49f9c9ab8cdaa72243ca5f8fd4
```

Reusable details from that run:

- Target type: direct container, prebuilt application image; no nested Docker.
- Image provenance was recorded with both base image and application image
  digests.
- The profiler pass used SGLang-Omni `/start_profile` and `/stop_profile`.
- Perfetto screenshots were taken from the trace timeline/flame-chart view, not
  from the SQL summary page.
- The PR reported trace-event and CUDA launch-count deltas as profiler
  evidence, while throughput/latency came from unprofiled benchmark runs.
