#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Inspect an SSH-accessible GPU container without requiring Docker.

Usage:
  direct_gpu_preflight.sh --host SSH_TARGET [options]

Options:
  --host TARGET             SSH target or configured alias.
  --cuda-smoke-cmd COMMAND  Required trusted application-level CUDA check.
  --require-ncu             Fail if ncu is absent; use only for profiling.
  --ssh-option OPTION       Repeatable ssh -o option.
  -h, --help                Show this help.
USAGE
}

host=""
cuda_smoke_cmd=""
require_ncu=false
ssh_cmd=(ssh)

while (($#)); do
  case "$1" in
    --host) host=${2:?missing value}; shift 2 ;;
    --cuda-smoke-cmd) cuda_smoke_cmd=${2:?missing value}; shift 2 ;;
    --require-ncu) require_ncu=true; shift ;;
    --ssh-option) ssh_cmd+=(-o "${2:?missing value}"); shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -n "$host" ]] || { echo "--host is required" >&2; exit 2; }
[[ -n "$cuda_smoke_cmd" ]] || {
  echo "--cuda-smoke-cmd is required for a passing preflight" >&2
  exit 2
}
command -v ssh >/dev/null || { echo "ssh is required" >&2; exit 1; }

remote_argv=(bash -s -- "${cuda_smoke_cmd:--}" "$require_ncu")
printf -v remote_command '%q ' "${remote_argv[@]}"
"${ssh_cmd[@]}" "$host" "$remote_command" <<'REMOTE'
set -uo pipefail
cuda_smoke_cmd=$1
require_ncu=$2
[[ "$cuda_smoke_cmd" == "-" ]] && cuda_smoke_cmd=""
failures=0
warnings=0

section() { printf '\n== %s ==\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; failures=$((failures + 1)); }
warn() { printf 'WARN: %s\n' "$1" >&2; warnings=$((warnings + 1)); }

section "Container"
uname -a
if [[ -r /etc/os-release ]]; then
  grep -E '^(NAME|VERSION|ID|ID_LIKE)=' /etc/os-release || true
fi
printf 'User: %s uid=%s\n' "$(id -un)" "$(id -u)"

section "NVIDIA driver exposure and GPU"
if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi --query-gpu=name,uuid,driver_version,memory.total --format=csv,noheader \
    || fail "nvidia-smi query failed"
else
  fail "nvidia-smi is absent or the host driver is not exposed"
fi
printf 'CUDA_VERSION=%s\n' "${CUDA_VERSION-}"
command -v nvcc >/dev/null 2>&1 && nvcc --version | tail -n 4 || warn "nvcc is absent"

section "Nsight Compute"
if command -v ncu >/dev/null 2>&1; then
  ncu --version | head -n 4
elif $require_ncu; then
  fail "ncu is required for profiling but was not found"
else
  warn "ncu is absent; this does not block normal benchmarking"
fi

section "Application CUDA smoke"
if ! bash -lc "$cuda_smoke_cmd"; then
  fail "application CUDA smoke command failed"
fi

printf '\nPreflight summary: failures=%d warnings=%d\n' "$failures" "$warnings"
((failures == 0))
REMOTE
