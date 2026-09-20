# Skills

Reusable agent skills for development and automation.

## Included skills

| Skill | Purpose |
|---|---|
| [`modal-sglang-omni`](skills/modal-sglang-omni/) | Run repeatable SGLang-Omni benchmarks and profiling workflows on Modal Sandboxes. |
| [`vastai-gpu-runtime`](skills/vastai-gpu-runtime/) | Prepare and validate Vast.ai GPU runtimes, including Docker, CUDA, NCU, repairs, artifacts, and cleanup. |
| [`vastai-sglang-omni`](skills/vastai-sglang-omni/) | Compose Vast.ai provider control, GPU runtime readiness, and SGLang-Omni benchmarking or model profiling. |

Each skill is self-contained under `skills/<name>/` and may include an
`agents/openai.yaml`, conditional references, and executable helpers.

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
├── modal-sglang-omni/
├── vastai-gpu-runtime/
└── vastai-sglang-omni/
```

The predecessor [`docker-ncu-benchmark`](https://github.com/wirybeaver/docker-ncu-benchmark)
has been split into `vastai-gpu-runtime` and `vastai-sglang-omni`.
