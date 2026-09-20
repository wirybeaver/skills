#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Pull an image on an SSH GPU host, run normal benchmarks, gate on an NCU
hardware counter, and collect a bounded Nsight Compute profile remotely.

This is the profiling branch. For normal benchmarks without NCU, use
run_remote_benchmark.sh.

Usage:
  run_remote_profile.sh --host SSH_TARGET --image IMAGE --benchmark-cmd COMMAND [options]

Required:
  --host TARGET                 SSH target or configured alias.
  --image IMAGE                 Prefer an immutable digest-qualified reference.
  --benchmark-cmd COMMAND       Trusted command executed inside the container.

Options:
  --profile-cmd COMMAND         Command profiled by NCU (default: benchmark command).
  --remote-artifacts DIR        Absolute path or path under remote $HOME
                                (default: docker-ncu-runs/<UTC run id>).
  --warmup N                    Unmeasured container runs (default: 1).
  --repeat N                    Measured normal runs (default: 3).
  --launch-count N              Maximum NCU kernel launches (default: 10).
  --ncu-set NAME                NCU section set (default: basic).
  --kernel-regex REGEX          Optional NCU kernel-name regex.
  --shm-size SIZE               Container shared memory (default: 16g).
  --mount SPEC                  Repeatable Docker volume specification.
  --env KEY=VALUE               Repeatable container environment value. Avoid secrets.
  --docker-arg ARG              Repeatable extra `docker run` argument.
  --ncu-arg ARG                 Repeatable additional NCU argument.
  --cap-sys-admin               Add CAP_SYS_ADMIN.
  --cap-sys-ptrace              Add CAP_SYS_PTRACE.
  --privileged                  Run privileged; approved last resort only.
  --skip-pull                   Do not pull the image.
  --registry HOST               Temporary remote registry login host.
  --registry-username USER      Username for temporary remote login.
  --registry-token-env NAME     Local environment variable containing registry token.
  --ssh-option OPTION           Repeatable ssh -o option.
  --dry-run                     Print configuration without connecting.
  -h, --help                    Show this help.

Profile wall time includes NCU replay overhead and is never normal latency.
USAGE
}

host=""
image=""
benchmark_cmd=""
profile_cmd=""
run_id=$(date -u +%Y%m%dT%H%M%SZ)
remote_artifacts="docker-ncu-runs/$run_id"
warmup=1
repeat=3
launch_count=10
ncu_set="basic"
kernel_regex=""
shm_size="16g"
cap_sys_admin=false
cap_sys_ptrace=false
privileged=false
skip_pull=false
registry=""
registry_username=""
registry_token_env=""
dry_run=false
ssh_cmd=(ssh)
mounts=()
env_values=()
docker_args=()
ncu_args=()

is_uint() { [[ $1 =~ ^[0-9]+$ ]]; }

while (($#)); do
  case "$1" in
    --host) host=${2:?missing value}; shift 2 ;;
    --image) image=${2:?missing value}; shift 2 ;;
    --benchmark-cmd) benchmark_cmd=${2:?missing value}; shift 2 ;;
    --profile-cmd) profile_cmd=${2:?missing value}; shift 2 ;;
    --remote-artifacts) remote_artifacts=${2:?missing value}; shift 2 ;;
    --warmup) warmup=${2:?missing value}; shift 2 ;;
    --repeat) repeat=${2:?missing value}; shift 2 ;;
    --launch-count) launch_count=${2:?missing value}; shift 2 ;;
    --ncu-set) ncu_set=${2:?missing value}; shift 2 ;;
    --kernel-regex) kernel_regex=${2:?missing value}; shift 2 ;;
    --shm-size) shm_size=${2:?missing value}; shift 2 ;;
    --mount) mounts+=("${2:?missing value}"); shift 2 ;;
    --env) env_values+=("${2:?missing value}"); shift 2 ;;
    --docker-arg) docker_args+=("${2:?missing value}"); shift 2 ;;
    --ncu-arg) ncu_args+=("${2:?missing value}"); shift 2 ;;
    --cap-sys-admin) cap_sys_admin=true; shift ;;
    --cap-sys-ptrace) cap_sys_ptrace=true; shift ;;
    --privileged) privileged=true; shift ;;
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
[[ -n "$profile_cmd" ]] || profile_cmd=$benchmark_cmd
is_uint "$warmup" && is_uint "$repeat" && is_uint "$launch_count" || {
  echo "--warmup, --repeat, and --launch-count must be non-negative integers" >&2
  exit 2
}
((repeat > 0 && launch_count > 0)) || { echo "--repeat and --launch-count must be greater than zero" >&2; exit 2; }

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

printf 'Host: %s\nImage: %s\nRemote artifacts: %s\nWarmup/repeat: %s/%s\nNCU set/launch count: %s/%s\n' \
  "$host" "$image" "$remote_artifacts" "$warmup" "$repeat" "$ncu_set" "$launch_count"
printf 'Benchmark command: %s\nProfile command: %s\n' "$benchmark_cmd" "$profile_cmd"
if $dry_run; then
  printf 'Mounts:'; printf ' %q' ${mounts[@]+"${mounts[@]}"}; printf '\nDocker args:'; printf ' %q' ${docker_args[@]+"${docker_args[@]}"}; printf '\n'
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
case "$1" in /tmp/docker-ncu-auth.*) rm -rf -- "$1" ;; esac
CLEANUP
  fi
}
trap cleanup_auth EXIT

if [[ -n "$registry" ]]; then
  auth_dir=$("${ssh_cmd[@]}" "$host" 'mktemp -d /tmp/docker-ncu-auth.XXXXXX')
  [[ "$auth_dir" =~ ^/tmp/docker-ncu-auth\.[A-Za-z0-9]+$ ]] || {
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
for value in ${ncu_args[@]+"${ncu_args[@]}"}; do records+=("N:$value"); done

remote_argv=(bash -s -- \
  "$image" "$benchmark_cmd" "$profile_cmd" "$remote_artifacts" \
  "$warmup" "$repeat" "$launch_count" "$ncu_set" "${kernel_regex:--}" "$shm_size" \
  "$cap_sys_admin" "$cap_sys_ptrace" "$privileged" "$skip_pull" "${auth_dir:--}" \
  ${records[@]+"${records[@]}"})
printf -v remote_command '%q ' "${remote_argv[@]}"
"${ssh_cmd[@]}" "$host" "$remote_command" <<'REMOTE'
set -Eeuo pipefail
image=$1; shift
benchmark_cmd=$1; shift
profile_cmd=$1; shift
artifact_input=$1; shift
warmup=$1; shift
repeat=$1; shift
launch_count=$1; shift
ncu_set=$1; shift
kernel_regex=$1; shift
[[ "$kernel_regex" == "-" ]] && kernel_regex=""
shm_size=$1; shift
cap_sys_admin=$1; shift
cap_sys_ptrace=$1; shift
privileged=$1; shift
skip_pull=$1; shift
auth_dir=$1; shift
[[ "$auth_dir" == "-" ]] && auth_dir=""

mounts=()
env_values=()
extra_docker_args=()
extra_ncu_args=()
for record in "$@"; do
  case "$record" in
    M:*) mounts+=("${record#M:}") ;;
    E:*) env_values+=("${record#E:}") ;;
    D:*) extra_docker_args+=("${record#D:}") ;;
    N:*) extra_ncu_args+=("${record#N:}") ;;
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
  echo "HOST=$(hostname -f 2>/dev/null || hostname)"
  echo "IMAGE=$image"
  echo "ARTIFACT_DIR=$artifact_dir"
  echo "WARMUP=$warmup"
  echo "REPEAT=$repeat"
  echo "NCU_SET=$ncu_set"
  echo "NCU_LAUNCH_COUNT=$launch_count"
  echo "CAP_SYS_ADMIN=$cap_sys_admin"
  echo "CAP_SYS_PTRACE=$cap_sys_ptrace"
  echo "PRIVILEGED=$privileged"
} > "$artifact_dir/run.env"
printf '%s\n' "$benchmark_cmd" > "$artifact_dir/benchmark-command.txt"
printf '%s\n' "$profile_cmd" > "$artifact_dir/profile-command.txt"

{
  uname -a
  [[ -r /etc/os-release ]] && cat /etc/os-release
  nvidia-smi
  docker version
  docker info
  "${docker_cmd[@]}" image inspect "$image"
} > "$artifact_dir/environment.txt" 2>&1 || true

docker_run=("${docker_cmd[@]}" run --rm --gpus all --ipc=host --shm-size "$shm_size" --entrypoint /bin/bash)
$cap_sys_admin && docker_run+=(--cap-add SYS_ADMIN)
$cap_sys_ptrace && docker_run+=(--cap-add SYS_PTRACE)
$privileged && docker_run+=(--privileged)
for value in ${mounts[@]+"${mounts[@]}"}; do docker_run+=(-v "$value"); done
for value in ${env_values[@]+"${env_values[@]}"}; do docker_run+=(-e "$value"); done
for value in ${extra_docker_args[@]+"${extra_docker_args[@]}"}; do docker_run+=("$value"); done
base=("${docker_run[@]}" -e "BENCHMARK_COMMAND=$benchmark_cmd" -e "PROFILE_COMMAND=$profile_cmd" -v "$artifact_dir:/artifacts" "$image")

"${base[@]}" -lc 'nvidia-smi -L' | tee "$artifact_dir/docker-gpu-smoke.log"

: > "$artifact_dir/benchmark-timings.tsv"
printf 'kind\titeration\tstart_ns\tend_ns\tduration_ns\texit_code\n' >> "$artifact_dir/benchmark-timings.tsv"
run_benchmark() {
  local kind=$1 iteration=$2 start end status
  start=$(date +%s%N)
  set +e
  "${base[@]}" -lc 'eval "$BENCHMARK_COMMAND"' 2>&1 | tee -a "$artifact_dir/benchmark.log"
  status=${PIPESTATUS[0]}
  set -e
  end=$(date +%s%N)
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$kind" "$iteration" "$start" "$end" "$((end - start))" "$status" >> "$artifact_dir/benchmark-timings.tsv"
  ((status == 0))
}

for ((i = 1; i <= warmup; i++)); do run_benchmark warmup "$i"; done
for ((i = 1; i <= repeat; i++)); do run_benchmark measured "$i"; done

smoke_ncu=(--target-processes all --metrics sm__cycles_elapsed.avg --launch-count 1 --force-overwrite -o /artifacts/ncu-smoke --csv --log-file /artifacts/ncu-smoke.csv)
set +e
"${base[@]}" -lc 'command -v ncu >/dev/null || { echo "ncu is absent from the image" >&2; exit 4; }; exec ncu "$@" /bin/bash -lc "$PROFILE_COMMAND"' _ "${smoke_ncu[@]}" 2>&1 | tee "$artifact_dir/ncu-smoke.log"
smoke_status=${PIPESTATUS[0]}
set -e
if ((smoke_status != 0)); then
  if grep -Eqi 'ERR_NVGPUCTRPERM|permission.*performance counter' "$artifact_dir/ncu-smoke.log"; then
    echo "NCU performance counters are restricted; inspect RmProfilingAdminOnly and consider CAP_SYS_ADMIN." >&2
  fi
  exit "$smoke_status"
fi
"${base[@]}" -lc 'ncu --import /artifacts/ncu-smoke.ncu-rep --page details --csv > /artifacts/ncu-smoke-details.csv'
grep -F 'sm__cycles_elapsed.avg' "$artifact_dir/ncu-smoke-details.csv" >/dev/null || {
  echo "NCU smoke report lacks sm__cycles_elapsed.avg; refusing full profile" >&2
  exit 1
}

profile_ncu=(--target-processes all --set "$ncu_set" --launch-count "$launch_count" --force-overwrite -o /artifacts/profile --csv --log-file /artifacts/ncu-profile.csv)
[[ -z "$kernel_regex" ]] || profile_ncu+=(--kernel-name "regex:$kernel_regex")
profile_ncu+=(${extra_ncu_args[@]+"${extra_ncu_args[@]}"})
profile_start=$(date +%s%N)
set +e
"${base[@]}" -lc 'exec ncu "$@" /bin/bash -lc "$PROFILE_COMMAND"' _ "${profile_ncu[@]}" 2>&1 | tee "$artifact_dir/ncu-profile.log"
profile_status=${PIPESTATUS[0]}
set -e
profile_end=$(date +%s%N)
printf 'PROFILE_START_NS=%s\nPROFILE_END_NS=%s\nPROFILE_DURATION_NS=%s\nPROFILE_EXIT_CODE=%s\nPROFILE_TIME_INCLUDES_REPLAY=true\n' \
  "$profile_start" "$profile_end" "$((profile_end - profile_start))" "$profile_status" > "$artifact_dir/profile-timing.env"
((profile_status == 0)) || exit "$profile_status"
"${base[@]}" -lc 'ncu --import /artifacts/profile.ncu-rep --page details --csv > /artifacts/ncu-profile-details.csv'

if command -v sha256sum >/dev/null 2>&1; then
  (cd "$artifact_dir" && find . -maxdepth 1 -type f ! -name SHA256SUMS -printf '%P\0' | sort -z | xargs -0 -r sha256sum > SHA256SUMS)
fi
chmod -R a+rX "$artifact_dir" 2>/dev/null || true
printf 'Remote benchmark and profile complete: %s\n' "$artifact_dir"
REMOTE
