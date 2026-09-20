#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Read-only inspection of an SSH-accessible NVIDIA Docker host.

Usage:
  remote_gpu_preflight.sh --host SSH_TARGET [options]

Options:
  --host TARGET             SSH target or configured alias.
  --gpu-test-image IMAGE    Required exact workload image for Docker GPU test.
  --gpu-test-cmd COMMAND    Required trusted application CUDA smoke in that image.
  --ssh-option OPTION       Repeatable ssh -o option.
  --require-host-ncu        Fail if ncu is not installed on the host.
  -h, --help                Show this help.
USAGE
}

host=""
gpu_test_image=""
gpu_test_cmd=""
require_host_ncu=false
ssh_cmd=(ssh)

while (($#)); do
  case "$1" in
    --host) host=${2:?missing value}; shift 2 ;;
    --gpu-test-image) gpu_test_image=${2:?missing value}; shift 2 ;;
    --gpu-test-cmd) gpu_test_cmd=${2:?missing value}; shift 2 ;;
    --ssh-option) ssh_cmd+=(-o "${2:?missing value}"); shift 2 ;;
    --require-host-ncu) require_host_ncu=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -n "$host" ]] || { echo "--host is required" >&2; exit 2; }
[[ -n "$gpu_test_image" ]] || {
  echo "--gpu-test-image is required for a passing preflight" >&2
  exit 2
}
[[ -n "$gpu_test_cmd" ]] || {
  echo "--gpu-test-cmd is required for a passing preflight" >&2
  exit 2
}
command -v ssh >/dev/null || { echo "ssh is required" >&2; exit 1; }

remote_argv=(
  bash -s --
  "$gpu_test_image"
  "${gpu_test_cmd:--}"
  "$require_host_ncu"
)
printf -v remote_command '%q ' "${remote_argv[@]}"
"${ssh_cmd[@]}" "$host" "$remote_command" <<'REMOTE'
set -uo pipefail
image=$1
gpu_test_cmd=$2
require_host_ncu=$3
[[ "$gpu_test_cmd" == "-" ]] && gpu_test_cmd=""
failures=0
warnings=0

section() { printf '\n== %s ==\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; failures=$((failures + 1)); }
warn() { printf 'WARN: %s\n' "$1" >&2; warnings=$((warnings + 1)); }

section "Host"
uname -a
if [[ -r /etc/os-release ]]; then
  grep -E '^(NAME|VERSION|ID|ID_LIKE)=' /etc/os-release || true
fi
printf 'User: %s uid=%s\n' "$(id -un)" "$(id -u)"

section "NVIDIA driver and GPU"
if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi --query-gpu=name,uuid,driver_version,memory.total --format=csv,noheader || fail "nvidia-smi query failed"
else
  fail "nvidia-smi is not installed or the driver is unavailable"
fi

if [[ -r /proc/driver/nvidia/params ]]; then
  grep -E '^RmProfilingAdminOnly:' /proc/driver/nvidia/params || warn "RmProfilingAdminOnly was not exposed"
else
  warn "/proc/driver/nvidia/params is unavailable"
fi

section "Docker and NVIDIA Container Toolkit"
if command -v docker >/dev/null 2>&1; then
  docker version --format 'Client={{.Client.Version}} Server={{.Server.Version}}' || fail "Docker daemon is unavailable to this user"
  docker info --format 'Runtimes={{json .Runtimes}} DefaultRuntime={{.DefaultRuntime}}' || true
else
  fail "docker is not installed"
fi
toolkit_found=false
if command -v nvidia-ctk >/dev/null 2>&1; then
  toolkit_found=true
  nvidia-ctk --version || true
else
  warn "nvidia-ctk is absent; the NVIDIA Container Toolkit may be missing or old"
fi
if command -v nvidia-container-cli >/dev/null 2>&1; then
  toolkit_found=true
  nvidia-container-cli --version || true
else
  warn "nvidia-container-cli is absent"
fi
if ! $toolkit_found; then
  fail "neither nvidia-ctk nor nvidia-container-cli is available"
fi

section "Host Nsight Compute"
if command -v ncu >/dev/null 2>&1; then
  ncu --version | head -n 4
elif $require_host_ncu; then
  fail "ncu is required on the host but was not found"
else
  warn "host ncu is absent; this does not block normal benchmarking"
fi

section "Docker GPU injection"
if command -v docker >/dev/null 2>&1; then
  if ! docker run --rm --gpus all --entrypoint /bin/bash \
    -e "GPU_TEST_COMMAND=$gpu_test_cmd" "$image" -lc \
    'nvidia-smi -L
     eval "$GPU_TEST_COMMAND"'; then
    fail "docker run --gpus all failed with image $image"
  fi
else
  fail "Docker GPU injection could not be tested"
fi

printf '\nPreflight summary: failures=%d warnings=%d\n' "$failures" "$warnings"
((failures == 0))
REMOTE
