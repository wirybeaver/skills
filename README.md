# Skills

Reusable agent skills for development and automation.

## Included skills

| Skill | Purpose |
|---|---|
| [`sglang-omni-benchmark`](skills/sglang-omni-benchmark/) | Shared A/A and A/B benchmark schedule, server lifecycle, warmups, evidence, and stop gates across GPU providers. |
| [`radix-run-time`](skills/radix-run-time/) | Manage sglang-community H100/H200 assignments, SSH access, four-hour leases, explicit renewals, runtime readiness, and release. |
| [`radix-sglang-omni`](skills/radix-sglang-omni/) | Run SGLang-Omni benchmarks or upstream profiling on Radix assignments. |
| [`modal-sglang-omni`](skills/modal-sglang-omni/) | Run repeatable SGLang-Omni benchmarks and profiling workflows on Modal Sandboxes. |
| [`vastai-gpu-runtime`](skills/vastai-gpu-runtime/) | Prepare and validate Vast.ai GPU runtimes, including Docker, CUDA, NCU, repairs, artifacts, and cleanup. |
| [`vastai-sglang-omni`](skills/vastai-sglang-omni/) | Compose Vast.ai provider control, GPU runtime readiness, and SGLang-Omni benchmarking or model profiling. |

Each skill lives under `skills/<name>/` and may include UI metadata, conditional references, and executable helpers. Cross-skill references use canonical GitHub raw URLs, so dependencies do not rely on sibling installation paths or symlink layouts. Resources within a skill use paths relative to that skill. Benchmark methodology is shared; profiling remains in the upstream `model-profiling` workflow, reached through the provider adapter.

## Install

Use a compatible skills client to add this repository and select the skills you
need. For example:

```bash
npx skills add wirybeaver/skills
```

## External skill dependencies

This repository does not vendor official or upstream-maintained skills. The
provider glue skills refer to these separately installed dependencies:

- `modal`
- `vastai`
- `model-profiling`

Their source of truth remains with their respective maintainers.

## Repository layout

```text
skills/
├── sglang-omni-benchmark/
├── radix-run-time/
├── radix-sglang-omni/
├── modal-sglang-omni/
├── vastai-gpu-runtime/
└── vastai-sglang-omni/
```

The predecessor [`docker-ncu-benchmark`](https://github.com/wirybeaver/docker-ncu-benchmark)
has been split into `vastai-gpu-runtime` and `vastai-sglang-omni`.
