#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Run an unprofiled benchmark directly in an SSH-accessible GPU container.

Use this when SSH already lands inside the provider-created GPU container and
Docker-in-Docker is unavailable.

Usage:
  run_direct_benchmark.sh --host SSH_TARGET --benchmark-cmd COMMAND [options]

Required:
  --host TARGET                 SSH target or configured alias.
  --benchmark-cmd COMMAND       Trusted command executed directly on the target.

Options:
  --remote-artifacts DIR        Absolute path or path under remote $HOME
                                (default: direct-gpu-runs/<UTC run id>).
  --workdir DIR                 Remote working directory (default: remote $HOME).
  --warmup N                    Unmeasured runs (default: 1).
  --repeat N                    Measured runs (default: 3).
  --env KEY=VALUE               Repeatable non-secret environment value.
  --cuda-smoke-cmd COMMAND      Optional application-level CUDA smoke command.
  --server-cmd COMMAND          Optional background server command.
  --health-cmd COMMAND          Trusted command that succeeds when ready;
                                required with --server-cmd.
  --health-timeout N            Readiness deadline in seconds (default: 600).
  --health-interval N           Readiness polling interval in seconds (default: 5).
  --ssh-option OPTION           Repeatable ssh -o option.
  --dry-run                     Print configuration without connecting.
  -h, --help                    Show this help.

This runner intentionally does not invoke Docker or Nsight Compute.
USAGE
}

host=""
benchmark_cmd=""
server_cmd=""
health_cmd=""
cuda_smoke_cmd=""
run_id=$(date -u +%Y%m%dT%H%M%SZ)
remote_artifacts="direct-gpu-runs/$run_id"
workdir=""
warmup=1
repeat=3
health_timeout=600
health_interval=5
dry_run=false
ssh_cmd=(ssh)
env_values=()

is_uint() { [[ $1 =~ ^[0-9]+$ ]]; }

while (($#)); do
  case "$1" in
    --host) host=${2:?missing value}; shift 2 ;;
    --benchmark-cmd) benchmark_cmd=${2:?missing value}; shift 2 ;;
    --server-cmd) server_cmd=${2:?missing value}; shift 2 ;;
    --health-cmd) health_cmd=${2:?missing value}; shift 2 ;;
    --cuda-smoke-cmd) cuda_smoke_cmd=${2:?missing value}; shift 2 ;;
    --remote-artifacts) remote_artifacts=${2:?missing value}; shift 2 ;;
    --workdir) workdir=${2:?missing value}; shift 2 ;;
    --warmup) warmup=${2:?missing value}; shift 2 ;;
    --repeat) repeat=${2:?missing value}; shift 2 ;;
    --health-timeout) health_timeout=${2:?missing value}; shift 2 ;;
    --health-interval) health_interval=${2:?missing value}; shift 2 ;;
    --env) env_values+=("${2:?missing value}"); shift 2 ;;
    --ssh-option) ssh_cmd+=(-o "${2:?missing value}"); shift 2 ;;
    --dry-run) dry_run=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -n "$host" ]] || { echo "--host is required" >&2; exit 2; }
[[ -n "$benchmark_cmd" ]] || { echo "--benchmark-cmd is required" >&2; exit 2; }
if [[ -n "$server_cmd" && -z "$health_cmd" ]]; then
  echo "--health-cmd is required with --server-cmd" >&2
  exit 2
fi
if [[ -z "$server_cmd" && -n "$health_cmd" ]]; then
  echo "--health-cmd requires --server-cmd" >&2
  exit 2
fi
is_uint "$warmup" && is_uint "$repeat" && is_uint "$health_timeout" \
  && is_uint "$health_interval" || {
  echo "--warmup, --repeat, --health-timeout, and --health-interval must be non-negative integers" >&2
  exit 2
}
((repeat > 0 && health_interval > 0)) || {
  echo "--repeat and --health-interval must be greater than zero" >&2
  exit 2
}

printf 'Execution target: direct GPU container\nHost: %s\n' "$host"
printf 'Remote artifacts: %s\nWarmup/repeat: %s/%s\n' \
  "$remote_artifacts" "$warmup" "$repeat"
printf 'Benchmark command: %s\n' "$benchmark_cmd"
[[ -z "$server_cmd" ]] || printf 'Server command: %s\nHealth command: %s\n' \
  "$server_cmd" "$health_cmd"
if $dry_run; then
  printf 'Environment:'; printf ' %q' ${env_values[@]+"${env_values[@]}"}; printf '\n'
  exit 0
fi
command -v ssh >/dev/null || { echo "ssh is required" >&2; exit 1; }

records=()
for value in ${env_values[@]+"${env_values[@]}"}; do records+=("E:$value"); done

remote_argv=(bash -s -- \
  "$benchmark_cmd" "${server_cmd:--}" "${health_cmd:--}" "${cuda_smoke_cmd:--}" \
  "$remote_artifacts" "${workdir:--}" "$warmup" "$repeat" \
  "$health_timeout" "$health_interval" ${records[@]+"${records[@]}"})
printf -v remote_command '%q ' "${remote_argv[@]}"
"${ssh_cmd[@]}" "$host" "$remote_command" <<'REMOTE'
set -Eeuo pipefail
benchmark_cmd=$1; shift
server_cmd=$1; shift
health_cmd=$1; shift
cuda_smoke_cmd=$1; shift
artifact_input=$1; shift
workdir=$1; shift
[[ "$server_cmd" == "-" ]] && server_cmd=""
[[ "$health_cmd" == "-" ]] && health_cmd=""
[[ "$cuda_smoke_cmd" == "-" ]] && cuda_smoke_cmd=""
[[ "$workdir" == "-" ]] && workdir="$HOME"
warmup=$1; shift
repeat=$1; shift
health_timeout=$1; shift
health_interval=$1; shift

env_values=()
for record in "$@"; do
  case "$record" in
    E:*)
      value=${record#E:}
      env_values+=("$value")
      export "$value"
      ;;
    *) echo "Malformed option record" >&2; exit 2 ;;
  esac
done

[[ -d "$workdir" ]] || { echo "Remote workdir does not exist: $workdir" >&2; exit 2; }
workdir=$(cd "$workdir" && pwd)
case "$artifact_input" in
  /*) artifact_dir=$artifact_input ;;
  *) artifact_dir="$HOME/$artifact_input" ;;
esac
if [[ -d "$artifact_dir" && -n $(find "$artifact_dir" -mindepth 1 -maxdepth 1 -print -quit) ]]; then
  echo "Remote artifact directory is not empty: $artifact_dir" >&2
  exit 2
fi
mkdir -p "$artifact_dir"
artifact_dir=$(cd "$artifact_dir" && pwd)

command -v nvidia-smi >/dev/null || { echo "nvidia-smi is absent" >&2; exit 1; }
nvidia-smi -L | tee "$artifact_dir/gpu-smoke.log"

{
  echo "RUN_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "EXECUTION_TARGET=direct-container"
  echo "HOST=$(hostname -f 2>/dev/null || hostname)"
  echo "WORKDIR=$workdir"
  echo "ARTIFACT_DIR=$artifact_dir"
  echo "WARMUP=$warmup"
  echo "REPEAT=$repeat"
  echo "SERVER_ENABLED=$([[ -n "$server_cmd" ]] && echo true || echo false)"
  echo "NCU_ENABLED=false"
} > "$artifact_dir/run.env"
printf '%s\n' "$benchmark_cmd" > "$artifact_dir/benchmark-command.txt"
printf '%s\n' ${env_values[@]+"${env_values[@]}"} > "$artifact_dir/environment-values.txt"
if [[ -n "$server_cmd" ]]; then
  printf '%s\n' "$server_cmd" > "$artifact_dir/server-command.txt"
  printf '%s\n' "$health_cmd" > "$artifact_dir/health-command.txt"
fi
[[ -z "$cuda_smoke_cmd" ]] || printf '%s\n' "$cuda_smoke_cmd" \
  > "$artifact_dir/cuda-smoke-command.txt"

{
  uname -a
  [[ -r /etc/os-release ]] && cat /etc/os-release
  nvidia-smi
  printf 'CUDA_VERSION=%s\n' "${CUDA_VERSION-}"
  command -v nvcc >/dev/null 2>&1 && nvcc --version || true
  command -v ncu >/dev/null 2>&1 && ncu --version | head -n 4 || true
  python3 --version 2>/dev/null || true
} > "$artifact_dir/environment.txt" 2>&1 || true

if [[ -n "$cuda_smoke_cmd" ]]; then
  (
    cd "$workdir"
    bash -lc "$cuda_smoke_cmd"
  ) 2>&1 | tee "$artifact_dir/cuda-smoke.log"
fi

server_pid=""
server_pgid=""
stop_server() {
  if [[ -n "$server_pid" ]]; then
    if [[ -n "$server_pgid" ]]; then
      kill -TERM -- "-$server_pgid" >/dev/null 2>&1 || true
    else
      kill -TERM "$server_pid" >/dev/null 2>&1 || true
    fi
    for _ in $(seq 1 30); do
      kill -0 "$server_pid" >/dev/null 2>&1 || break
      sleep 1
    done
    if [[ -n "$server_pgid" ]]; then
      kill -KILL -- "-$server_pgid" >/dev/null 2>&1 || true
    else
      kill -KILL "$server_pid" >/dev/null 2>&1 || true
    fi
    wait "$server_pid" >/dev/null 2>&1 || true
  fi
  server_pid=""
  server_pgid=""
}
cleanup_server() {
  local status=$?
  stop_server
  return "$status"
}
trap cleanup_server EXIT

if [[ -n "$server_cmd" ]]; then
  if command -v setsid >/dev/null 2>&1; then
    (
      cd "$workdir"
      exec setsid bash -lc "$server_cmd"
    ) > "$artifact_dir/server.log" 2>&1 &
    server_pid=$!
    server_pgid=$server_pid
  else
    (
      cd "$workdir"
      exec bash -lc "$server_cmd"
    ) > "$artifact_dir/server.log" 2>&1 &
    server_pid=$!
  fi
  printf '%s\n' "$server_pid" > "$artifact_dir/server.pid"

  deadline=$((SECONDS + health_timeout))
  while ((SECONDS <= deadline)); do
    if (
      cd "$workdir"
      bash -lc "$health_cmd"
    ) > "$artifact_dir/health-last.log" 2>&1; then
      printf 'Server became healthy at %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        | tee "$artifact_dir/health-ready.log"
      break
    fi
    if ! kill -0 "$server_pid" >/dev/null 2>&1; then
      echo "Server process exited before becoming healthy" >&2
      exit 1
    fi
    sleep "$health_interval"
  done
  if ! (
    cd "$workdir"
    bash -lc "$health_cmd"
  ) > "$artifact_dir/health-last.log" 2>&1; then
    echo "Server did not become healthy before the deadline" >&2
    exit 1
  fi
fi

: > "$artifact_dir/benchmark-timings.tsv"
printf 'kind\titeration\tstart_ns\tend_ns\tduration_ns\texit_code\n' \
  >> "$artifact_dir/benchmark-timings.tsv"
run_benchmark() {
  local kind=$1 iteration=$2 start end status
  start=$(date +%s%N)
  set +e
  (
    cd "$workdir"
    bash -lc "$benchmark_cmd"
  ) 2>&1 | tee -a "$artifact_dir/benchmark.log"
  status=${PIPESTATUS[0]}
  set -e
  end=$(date +%s%N)
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$kind" "$iteration" "$start" "$end" "$((end - start))" "$status" \
    >> "$artifact_dir/benchmark-timings.tsv"
  ((status == 0))
}

for ((i = 1; i <= warmup; i++)); do run_benchmark warmup "$i"; done
for ((i = 1; i <= repeat; i++)); do run_benchmark measured "$i"; done

stop_server
trap - EXIT
if command -v sha256sum >/dev/null 2>&1; then
  (cd "$artifact_dir" && find . -maxdepth 1 -type f ! -name SHA256SUMS -printf '%P\0' \
    | sort -z | xargs -0 -r sha256sum > SHA256SUMS)
fi
chmod -R a+rX "$artifact_dir" 2>/dev/null || true
printf 'Direct benchmark complete: %s\n' "$artifact_dir"
REMOTE
