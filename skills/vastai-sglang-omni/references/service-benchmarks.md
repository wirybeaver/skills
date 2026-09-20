# Service/client GPU benchmarks

Use this reference when the benchmark client talks to a persistent GPU server,
as with `benchmark_asr_seedtts`.

Resolve the installed `$vastai-gpu-runtime` skill directory from the available
skills catalog and assign it to `VASTAI_GPU_RUNTIME_DIR` before using the script
examples below.

Before provisioning a host, verify the server and benchmark entrypoints with
the selected source revision or image. Read `--help` and inspect the benchmark's
dataset-loading path. Use only confirmed flags, model IDs, dataset IDs, and
preparation commands. A runner `--dry-run` does not validate the nested server
or benchmark command. If a preparation helper is not present in the source,
warm the real model/dataset path with an unmeasured application run instead.

## Choose the execution target

- **Docker host**: use `run_remote_benchmark.sh`. This fits a VM, bare-metal
  host, or SSH target with its own Docker daemon and NVIDIA Container Toolkit.
- **Direct container**: use `run_direct_benchmark.sh`. This fits any cloud GPU
  service where SSH lands inside the provider-created application container.
  Either create an instance for a source-pinned application image, or launch a
  compatible provider CUDA/PyTorch image and install the pinned source revision
  after SSH login. Do not attempt Docker-in-Docker.

These execution models are provider-neutral. Provider integrations should
handle only offer selection, instance creation, connection discovery, storage,
and destruction.

## Direct-container provisioning

There is one outer container, not a provider image plus a nested application
image. Choose one setup:

1. **Provider image plus SSH bootstrap** — select a compatible CUDA/PyTorch
   provider image, SSH into it, clone the exact remote revision, install the
   environment, and then run `direct_gpu_preflight.sh` and
   `run_direct_benchmark.sh`.
2. **Prebuilt application images** — build the required source revisions ahead
   of time and create an instance or custom template specifically configured
   for the active image. This is fastest and most reproducible for repeated
   Base-vs-Head runs. Follow the parent skill's image-parity contract; a source
   comparison requires distinct Base and Head images.

Do not reuse an unrelated provider template while silently replacing its
image. Templates may couple a provider base image to an on-start script,
environment variables, ports, Jupyter setup, or a web portal. When retaining
such a template, retain its image and use SSH bootstrap. To use the prebuilt
application image, create a separate custom template or direct instance with
compatible startup settings.

For SGLang-Omni, prefer a base that already contains its expensive native/CUDA
stack. The repository's recommended environment can be bootstrapped as:

```bash
cd /workspace
git clone --branch <REMOTE_BRANCH> --single-branch <REPOSITORY_URL> sglang-omni
cd sglang-omni
git rev-parse HEAD
git status --short

# When starting from the matching SGLang-Omni development image:
uv pip install --system --no-deps --no-build-isolation -e .

# When starting from a generic compatible image instead:
uv venv .venv -p 3.12
source .venv/bin/activate
uv pip install -v -e .
```

The no-dependency overlay is valid only after verifying that the outer image
already supplies the revision's pinned Python and native dependencies. A
generic image may require UCX, FlashAttention, compilers, and matching
CUDA/PyTorch packages before `uv pip install -e .` can succeed. Preserve the
outer image reference, source commit, Python/uv versions, lockfile, install
command, and post-install package inventory as artifacts.

## Repetition ownership

Use one repetition layer:

- If the application benchmark implements warmup and repeats, pass
  `--warmup 0 --repeat 1` to the runner.
- Otherwise, let the runner perform warmups and repetitions.

Application-emitted latency, throughput, and correctness metrics are the source
of truth for steady-state claims. Runner timings include process or container
startup and teardown.

## Docker-host SeedTTS pattern

Build source-pinned base and head images from the same digest-pinned parent:

```dockerfile
ARG BASE_IMAGE=hongccc/sglang-omni@sha256:DIGEST
FROM ${BASE_IMAGE}
ARG SOURCE_COMMIT
LABEL org.opencontainers.image.revision="${SOURCE_COMMIT}"
WORKDIR /opt/sglang-omni-benchmark
COPY . .
RUN python -m pip install --no-deps --no-build-isolation -e . \
    && python -m pip install --no-deps openai-whisper==20250625
ENV PYTHONPATH=/opt/sglang-omni-benchmark
```

Run one image:

```bash
"$VASTAI_GPU_RUNTIME_DIR/scripts/run_remote_benchmark.sh" \
  --host gpu-vm \
  --image user/sglang-omni@sha256:DIGEST \
  --mount /opt/asr/cache:/root/.cache/huggingface \
  --mount /opt/asr/results:/results \
  --env HF_HOME=/root/.cache/huggingface \
  --env HF_HUB_OFFLINE=1 \
  --env TRANSFORMERS_OFFLINE=1 \
  --server-docker-arg -p \
  --server-docker-arg 8000:8000 \
  --server-cmd \
    'python -m sglang_omni.cli serve \
       --model-path FunAudioLLM/Fun-ASR-Nano-2512-hf \
       --host 0.0.0.0 --port 8000' \
  --health-cmd 'curl -fsS http://127.0.0.1:8000/health' \
  --docker-arg=--network=host \
  --benchmark-cmd \
    'python -m benchmarks.eval.benchmark_asr_seedtts \
       --host 127.0.0.1 --port 8000 \
       --model-path FunAudioLLM/Fun-ASR-Nano-2512-hf \
       --meta zhaochenyang20/seed-tts-eval-50-arrow \
       --lang en --max-samples 20 --concurrencies 1,8 \
       --repeats 3 --warmup --output /results/result.json' \
  --warmup 0 --repeat 1
```

The script starts the server container, waits for health, runs the client
container, captures both logs, and stops the server even when the benchmark
fails. The server command must remain in the foreground so the runner can
observe and terminate its lifecycle.

## Direct-container SeedTTS pattern

Launch the customized image as the provider instance image, or bootstrap the
pinned source into a compatible provider image, then run:

```bash
"$VASTAI_GPU_RUNTIME_DIR/scripts/run_direct_benchmark.sh" \
  --host gpu-container \
  --workdir /opt/sglang-omni-benchmark \
  --env HF_HOME=/root/.cache/huggingface \
  --env HF_HUB_OFFLINE=1 \
  --env TRANSFORMERS_OFFLINE=1 \
  --cuda-smoke-cmd \
    'python -c "import torch; assert torch.cuda.is_available(); print(torch.cuda.get_device_name())"' \
  --server-cmd \
    'python -m sglang_omni.cli serve \
       --model-path FunAudioLLM/Fun-ASR-Nano-2512-hf \
       --host 127.0.0.1 --port 8000' \
  --health-cmd 'curl -fsS http://127.0.0.1:8000/health' \
  --benchmark-cmd \
    'python -m benchmarks.eval.benchmark_asr_seedtts \
       --host 127.0.0.1 --port 8000 \
       --model-path FunAudioLLM/Fun-ASR-Nano-2512-hf \
       --meta zhaochenyang20/seed-tts-eval-50-arrow \
       --lang en --max-samples 20 --concurrencies 1,8 \
       --repeats 3 --warmup --output /workspace/result.json' \
  --warmup 0 --repeat 1
```

## Base-vs-head controls

For comparative claims:

1. Satisfy the parent skill's image-parity contract.
2. Use the same host, model, dataset, cache, commands, and power settings.
3. Warm each revision explicitly.
4. Run both base-then-head and head-then-base orders.
5. Ensure the prior server and GPU processes are gone before switching images.
6. Compare application metrics and correctness outputs, not only wrapper wall
   time.
7. Report individual repetitions, aggregation, ordering, and limitations.

For the prebuilt direct-container lifecycle, including cache-state sessions and
provider image switching, read
[direct-container-base-head.md](direct-container-base-head.md).
