#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Verify Docker GPU access and collect a real Nsight Compute hardware counter.
Run this script on the target GPU host.

Usage:
  ncu_smoke.sh --image IMAGE [options]

Options:
  --image IMAGE              Container image containing ncu and a CUDA Python stack.
  --output-dir DIR           Host output directory (default: ./ncu-smoke-artifacts).
  --workload-cmd COMMAND     Trusted CUDA command to profile. By default, auto-detect
                             PyTorch or CuPy and run synchronized matrix multiplication.
  --metric NAME              Required metric (default: sm__cycles_elapsed.avg).
  --cap-sys-admin            Add CAP_SYS_ADMIN for restricted performance counters.
  --cap-sys-ptrace           Add CAP_SYS_PTRACE.
  --privileged               Run privileged; use only as an approved last resort.
  --docker-arg ARG           Repeatable extra `docker run` argument.
  --dry-run                  Print the Docker command without executing it.
  -h, --help                 Show this help.
USAGE
}

image=""
output_dir="./ncu-smoke-artifacts"
workload_cmd="python3 /ncu-smoke/workload.py"
metric="sm__cycles_elapsed.avg"
cap_sys_admin=false
cap_sys_ptrace=false
privileged=false
dry_run=false
docker_args=()

while (($#)); do
  case "$1" in
    --image) image=${2:?missing value}; shift 2 ;;
    --output-dir) output_dir=${2:?missing value}; shift 2 ;;
    --workload-cmd) workload_cmd=${2:?missing value}; shift 2 ;;
    --metric) metric=${2:?missing value}; shift 2 ;;
    --cap-sys-admin) cap_sys_admin=true; shift ;;
    --cap-sys-ptrace) cap_sys_ptrace=true; shift ;;
    --privileged) privileged=true; shift ;;
    --docker-arg) docker_args+=("${2:?missing value}"); shift 2 ;;
    --dry-run) dry_run=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -n "$image" ]] || { echo "--image is required" >&2; exit 2; }
command -v docker >/dev/null || { echo "docker is required" >&2; exit 1; }
mkdir -p "$output_dir"
output_dir=$(cd "$output_dir" && pwd)

cat > "$output_dir/workload.py" <<'PY'
import sys

try:
    import torch
    if not torch.cuda.is_available():
        raise RuntimeError("PyTorch reports CUDA unavailable")
    a = torch.randn((1024, 1024), device="cuda")
    b = torch.randn((1024, 1024), device="cuda")
    torch.cuda.synchronize()
    c = a @ b
    torch.cuda.synchronize()
    print(float(c[0, 0]))
except ImportError:
    try:
        import cupy as cp
        a = cp.random.randn(1024, 1024, dtype=cp.float32)
        b = cp.random.randn(1024, 1024, dtype=cp.float32)
        cp.cuda.Stream.null.synchronize()
        c = a @ b
        cp.cuda.Stream.null.synchronize()
        print(float(c[0, 0]))
    except ImportError as exc:
        print("Neither PyTorch nor CuPy is installed; pass --workload-cmd", file=sys.stderr)
        raise SystemExit(3) from exc
PY

cmd=(docker run --rm --gpus all --ipc=host --entrypoint /bin/bash)
$cap_sys_admin && cmd+=(--cap-add SYS_ADMIN)
$cap_sys_ptrace && cmd+=(--cap-add SYS_PTRACE)
$privileged && cmd+=(--privileged)
for value in ${docker_args[@]+"${docker_args[@]}"}; do cmd+=("$value"); done
cmd+=(-v "$output_dir:/ncu-smoke" -e "NCU_SMOKE_COMMAND=$workload_cmd" "$image" -lc)
cmd+=('set -Eeuo pipefail
command -v nvidia-smi >/dev/null
nvidia-smi -L
command -v ncu >/dev/null || { echo "ncu is absent from the image" >&2; exit 4; }
ncu --version | head -n 4
ncu --target-processes all --metrics "$1" --launch-count 1 --force-overwrite -o /ncu-smoke/ncu-smoke --csv --log-file /ncu-smoke/ncu-smoke.csv /bin/bash -lc "$NCU_SMOKE_COMMAND"
ncu --import /ncu-smoke/ncu-smoke.ncu-rep --page details --csv > /ncu-smoke/ncu-smoke-details.csv
grep -F "$1" /ncu-smoke/ncu-smoke-details.csv >/dev/null
chmod a+r /ncu-smoke/ncu-smoke* 2>/dev/null || true' _ "$metric")

printf 'Command:'
printf ' %q' "${cmd[@]}"
printf '\n'
$dry_run && exit 0

set +e
"${cmd[@]}" 2>&1 | tee "$output_dir/ncu-smoke.log"
status=${PIPESTATUS[0]}
set -e
if ((status != 0)); then
  if grep -Eqi 'ERR_NVGPUCTRPERM|permission.*performance counter|profiling.*not supported' "$output_dir/ncu-smoke.log"; then
    cat >&2 <<'ERROR'
NCU could not access GPU performance counters. Inspect:
  grep '^RmProfilingAdminOnly:' /proc/driver/nvidia/params
If it is 1, retry with --cap-sys-admin after approval. Use --privileged only
as a last-resort diagnostic, not as the default benchmark configuration.
ERROR
  fi
  exit "$status"
fi

grep -F "$metric" "$output_dir/ncu-smoke-details.csv" >/dev/null || {
  echo "NCU completed but the required metric was not found: $metric" >&2
  exit 1
}
printf 'NCU hardware-counter smoke test passed. Artifacts: %s\n' "$output_dir"
