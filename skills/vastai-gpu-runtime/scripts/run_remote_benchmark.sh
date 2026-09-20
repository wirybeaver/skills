#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Run an unprofiled benchmark in Docker on an SSH-accessible NVIDIA GPU host.

Usage:
  run_remote_benchmark.sh --host SSH_TARGET --image IMAGE \
    --benchmark-cmd COMMAND [options]

Required:
  --host TARGET                 SSH target or configured alias.
  --image IMAGE                 Prefer an immutable digest-qualified reference.
  --benchmark-cmd COMMAND       Trusted command executed in the benchmark container.

Benchmark options:
  --remote-artifacts DIR        Absolute path or path under remote $HOME
                                (default: docker-gpu-runs/<UTC run id>).
  --warmup N                    Unmeasured container runs (default: 1).
  --repeat N                    Measured container runs (default: 3).
  --shm-size SIZE               Container shared memory (default: 16g).
  --mount SPEC                  Repeatable Docker volume specification.
  --env KEY=VALUE               Repeatable non-secret container environment value.
  --docker-arg ARG              Repeatable benchmark-container argument.

Optional service lifecycle:
  --server-cmd COMMAND          Start a persistent GPU server container first.
  --health-cmd COMMAND          Trusted host command that succeeds when ready;
                                required with --server-cmd.
  --server-name NAME            Server container name (default: generated).
  --server-docker-arg ARG       Repeatable server-container argument, such as -p.
  --health-timeout N            Readiness deadline in seconds (default: 600).
  --health-interval N           Readiness polling interval in seconds (default: 5).

Image and SSH options:
  --skip-pull                   Do not pull the image.
  --registry HOST               Temporary remote registry login host.
  --registry-username USER      Username for temporary remote login.
  --registry-token-env NAME     Local environment variable containing registry token.
  --ssh-option OPTION           Repeatable ssh -o option.
  --dry-run                     Print configuration without connecting.
  -h, --help                    Show this help.

This runner intentionally does not invoke Nsight Compute. Use
run_remote_profile.sh only when hardware-counter profiling is requested.
USAGE
}

host=""
image=""
benchmark_cmd=""
server_cmd=""
health_cmd=""
run_id=$(date -u +%Y%m%dT%H%M%SZ)
remote_artifacts="docker-gpu-runs/$run_id"
server_name="docker-gpu-benchmark-$run_id"
warmup=1
repeat=3
shm_size="16g"
health_timeout=600
health_interval=5
skip_pull=false
registry=""
registry_username=""
registry_token_env=""
dry_run=false
ssh_cmd=(ssh)
mounts=()
env_values=()
docker_args=()
server_docker_args=()

is_uint() { [[ $1 =~ ^[0-9]+$ ]]; }

while (($#)); do
  case "$1" in
    --host) host=${2:?missing value}; shift 2 ;;
    --image) image=${2:?missing value}; shift 2 ;;
    --benchmark-cmd) benchmark_cmd=${2:?missing value}; shift 2 ;;
    --server-cmd) server_cmd=${2:?missing value}; shift 2 ;;
    --health-cmd) health_cmd=${2:?missing value}; shift 2 ;;
    --server-name) server_name=${2:?missing value}; shift 2 ;;
    --remote-artifacts) remote_artifacts=${2:?missing value}; shift 2 ;;
    --warmup) warmup=${2:?missing value}; shift 2 ;;
    --repeat) repeat=${2:?missing value}; shift 2 ;;
    --shm-size) shm_size=${2:?missing value}; shift 2 ;;
    --health-timeout) health_timeout=${2:?missing value}; shift 2 ;;
    --health-interval) health_interval=${2:?missing value}; shift 2 ;;
    --mount) mounts+=("${2:?missing value}"); shift 2 ;;
    --env) env_values+=("${2:?missing value}"); shift 2 ;;
    --docker-arg=*) docker_args+=("${1#*=}"); shift ;;
    --docker-arg) docker_args+=("${2:?missing value}"); shift 2 ;;
    --server-docker-arg=*) server_docker_args+=("${1#*=}"); shift ;;
    --server-docker-arg) server_docker_args+=("${2:?missing value}"); shift 2 ;;
    --skip-pull) skip_pull=true; shift ;;
    --registry) registry=${2:?missing value}; shift 2 ;;
    --registry-username) registry_username=${2:?missing value}; shift 2 ;;
    --registry-token-env) registry_token_env=${2:?missing value}; shift 2 ;;
    --ssh-option) ssh_cmd+=(-o "${2:?missing value}"); shift 2 ;;
    --dry-run) dry_run=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -n "$host" ]] || { echo "--host is required" >&2; exit 2; }
[[ -n "$image" ]] || { echo "--image is required" >&2; exit 2; }
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
[[ "$server_name" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || {
  echo "--server-name contains unsupported characters: $server_name" >&2
  exit 2
}

if [[ -n "$registry" || -n "$registry_username" || -n "$registry_token_env" ]]; then
  [[ -n "$registry" && -n "$registry_username" && -n "$registry_token_env" ]] || {
    echo "Registry options must be supplied together" >&2
    exit 2
  }
  [[ -n "${!registry_token_env-}" ]] || {
    echo "Registry token environment variable is unset or empty: $registry_token_env" >&2
    exit 2
  }
fi

printf 'Execution target: remote Docker host\nHost: %s\nImage: %s\n' "$host" "$image"
printf 'Remote artifacts: %s\nWarmup/repeat: %s/%s\n' \
  "$remote_artifacts" "$warmup" "$repeat"
printf 'Benchmark command: %s\n' "$benchmark_cmd"
if [[ -n "$server_cmd" ]]; then
  printf 'Server command: %s\nHealth command: %s\n' "$server_cmd" "$health_cmd"
fi
if $dry_run; then
  printf 'Mounts:'; printf ' %q' ${mounts[@]+"${mounts[@]}"}; printf '\n'
  printf 'Docker args:'; printf ' %q' ${docker_args[@]+"${docker_args[@]}"}; printf '\n'
  printf 'Server Docker args:'; printf ' %q' ${server_docker_args[@]+"${server_docker_args[@]}"}; printf '\n'
  exit 0
fi
command -v ssh >/dev/null || { echo "ssh is required" >&2; exit 1; }

auth_dir=""
cleanup_auth() {
  if [[ -n "$auth_dir" ]]; then
    local cleanup_argv cleanup_command
    cleanup_argv=(bash -s -- "$auth_dir")
    printf -v cleanup_command '%q ' "${cleanup_argv[@]}"
    "${ssh_cmd[@]}" "$host" "$cleanup_command" <<'CLEANUP' >/dev/null 2>&1 || true
set -u
case "$1" in /tmp/docker-gpu-auth.*) rm -rf -- "$1" ;; esac
CLEANUP
  fi
}
trap cleanup_auth EXIT

if [[ -n "$registry" ]]; then
  auth_dir=$("${ssh_cmd[@]}" "$host" 'mktemp -d /tmp/docker-gpu-auth.XXXXXX')
  [[ "$auth_dir" =~ ^/tmp/docker-gpu-auth\.[A-Za-z0-9]+$ ]] || {
    echo "Remote mktemp returned an unexpected path: $auth_dir" >&2
    exit 1
  }
  printf -v remote_login 'docker --config %q login %q --username %q --password-stdin' \
    "$auth_dir" "$registry" "$registry_username"
  printf '%s' "${!registry_token_env}" | "${ssh_cmd[@]}" "$host" "$remote_login" >/dev/null
fi

records=()
for value in ${mounts[@]+"${mounts[@]}"}; do records+=("M:$value"); done
for value in ${env_values[@]+"${env_values[@]}"}; do records+=("E:$value"); done
for value in ${docker_args[@]+"${docker_args[@]}"}; do records+=("D:$value"); done
for value in ${server_docker_args[@]+"${server_docker_args[@]}"}; do records+=("S:$value"); done

remote_argv=(bash -s -- \
  "$image" "$benchmark_cmd" "${server_cmd:--}" "${health_cmd:--}" \
  "$remote_artifacts" "$server_name" "$warmup" "$repeat" "$shm_size" \
  "$health_timeout" "$health_interval" "$skip_pull" "${auth_dir:--}" \
  ${records[@]+"${records[@]}"})
printf -v remote_command '%q ' "${remote_argv[@]}"
"${ssh_cmd[@]}" "$host" "$remote_command" <<'REMOTE'
set -Eeuo pipefail
image=$1; shift
benchmark_cmd=$1; shift
server_cmd=$1; shift
health_cmd=$1; shift
[[ "$server_cmd" == "-" ]] && server_cmd=""
[[ "$health_cmd" == "-" ]] && health_cmd=""
artifact_input=$1; shift
server_name=$1; shift
warmup=$1; shift
repeat=$1; shift
shm_size=$1; shift
health_timeout=$1; shift
health_interval=$1; shift
skip_pull=$1; shift
auth_dir=$1; shift
[[ "$auth_dir" == "-" ]] && auth_dir=""

mounts=()
env_values=()
benchmark_docker_args=()
server_docker_args=()
for record in "$@"; do
  case "$record" in
    M:*) mounts+=("${record#M:}") ;;
    E:*) env_values+=("${record#E:}") ;;
    D:*) benchmark_docker_args+=("${record#D:}") ;;
    S:*) server_docker_args+=("${record#S:}") ;;
    *) echo "Malformed option record" >&2; exit 2 ;;
  esac
done

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

if [[ -n "$auth_dir" ]]; then
  docker_cmd=(docker --config "$auth_dir")
else
  docker_cmd=(docker)
fi
command -v docker >/dev/null || { echo "docker is absent" >&2; exit 1; }
command -v nvidia-smi >/dev/null || { echo "nvidia-smi is absent" >&2; exit 1; }

if ! $skip_pull; then
  "${docker_cmd[@]}" pull "$image" 2>&1 | tee "$artifact_dir/docker-pull.log"
fi

{
  echo "RUN_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "EXECUTION_TARGET=docker-host"
  echo "HOST=$(hostname -f 2>/dev/null || hostname)"
  echo "IMAGE=$image"
  echo "ARTIFACT_DIR=$artifact_dir"
  echo "WARMUP=$warmup"
  echo "REPEAT=$repeat"
  echo "SERVER_ENABLED=$([[ -n "$server_cmd" ]] && echo true || echo false)"
  echo "NCU_ENABLED=false"
} > "$artifact_dir/run.env"
printf '%s\n' "$benchmark_cmd" > "$artifact_dir/benchmark-command.txt"
printf '%s\n' ${mounts[@]+"${mounts[@]}"} > "$artifact_dir/mounts.txt"
printf '%s\n' ${env_values[@]+"${env_values[@]}"} > "$artifact_dir/container-env.txt"
printf '%s\n' ${benchmark_docker_args[@]+"${benchmark_docker_args[@]}"} > "$artifact_dir/benchmark-docker-args.txt"
printf '%s\n' ${server_docker_args[@]+"${server_docker_args[@]}"} > "$artifact_dir/server-docker-args.txt"
if [[ -n "$server_cmd" ]]; then
  printf '%s\n' "$server_cmd" > "$artifact_dir/server-command.txt"
  printf '%s\n' "$health_cmd" > "$artifact_dir/health-command.txt"
fi

{
  uname -a
  [[ -r /etc/os-release ]] && cat /etc/os-release
  nvidia-smi
  docker version
  docker info
  command -v nvidia-ctk >/dev/null 2>&1 && nvidia-ctk --version || true
  "${docker_cmd[@]}" image inspect "$image"
} > "$artifact_dir/environment.txt" 2>&1 || true

common_run=("${docker_cmd[@]}" run --rm --gpus all --ipc=host --shm-size "$shm_size" --entrypoint /bin/bash)
for value in ${mounts[@]+"${mounts[@]}"}; do common_run+=(-v "$value"); done
for value in ${env_values[@]+"${env_values[@]}"}; do common_run+=(-e "$value"); done

benchmark_run=("${common_run[@]}")
for value in ${benchmark_docker_args[@]+"${benchmark_docker_args[@]}"}; do benchmark_run+=("$value"); done
benchmark_run+=(-e "BENCHMARK_COMMAND=$benchmark_cmd" -v "$artifact_dir:/artifacts" "$image")

"${benchmark_run[@]}" -lc 'nvidia-smi -L' | tee "$artifact_dir/docker-gpu-smoke.log"

server_started=false
stop_server() {
  if $server_started || "${docker_cmd[@]}" ps -a --format '{{.Names}}' | grep -Fxq "$server_name"; then
    "${docker_cmd[@]}" logs "$server_name" > "$artifact_dir/server.log" 2>&1 || true
    "${docker_cmd[@]}" stop -t 30 "$server_name" >/dev/null 2>&1 \
      || "${docker_cmd[@]}" rm -f "$server_name" >/dev/null 2>&1 \
      || true
  fi
  server_started=false
}
cleanup_server() {
  local status=$?
  stop_server
  return "$status"
}
trap cleanup_server EXIT

if [[ -n "$server_cmd" ]]; then
  if "${docker_cmd[@]}" ps -a --format '{{.Names}}' | grep -Fxq "$server_name"; then
    echo "Server container name already exists: $server_name" >&2
    exit 2
  fi
  server_run=("${common_run[@]}" -d)
  for value in ${server_docker_args[@]+"${server_docker_args[@]}"}; do server_run+=("$value"); done
  server_run+=(--name "$server_name" -e "SERVER_COMMAND=$server_cmd" "$image")
  "${server_run[@]}" -lc 'eval "$SERVER_COMMAND"' > "$artifact_dir/server-container-id.txt"
  server_started=true

  deadline=$((SECONDS + health_timeout))
  while ((SECONDS <= deadline)); do
    if eval "$health_cmd" > "$artifact_dir/health-last.log" 2>&1; then
      printf 'Server became healthy at %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        | tee "$artifact_dir/health-ready.log"
      break
    fi
    if ! "${docker_cmd[@]}" ps --format '{{.Names}}' | grep -Fxq "$server_name"; then
      echo "Server container exited before becoming healthy" >&2
      "${docker_cmd[@]}" logs "$server_name" >&2 || true
      exit 1
    fi
    sleep "$health_interval"
  done
  if ! eval "$health_cmd" > "$artifact_dir/health-last.log" 2>&1; then
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
  "${benchmark_run[@]}" -lc 'eval "$BENCHMARK_COMMAND"' 2>&1 \
    | tee -a "$artifact_dir/benchmark.log"
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
printf 'Remote benchmark complete: %s\n' "$artifact_dir"
REMOTE
