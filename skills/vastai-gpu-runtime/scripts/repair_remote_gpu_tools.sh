#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Preview or apply narrowly scoped NVIDIA Docker/NCU repairs on an SSH host.

Usage:
  repair_remote_gpu_tools.sh --host SSH_TARGET ACTION... [--apply]

Actions:
  --install-toolkit         Install `nvidia-container-toolkit` from configured repos.
  --configure-docker        Run `nvidia-ctk runtime configure --runtime=docker`.
  --restart-docker          Restart Docker; may interrupt running containers.
  --install-ncu             Install the package supplied by --ncu-package.
  --ncu-package PACKAGE     Exact host package name for Nsight Compute.

Other options:
  --host TARGET             SSH target or configured alias.
  --ssh-option OPTION       Repeatable ssh -o option.
  --apply                   Execute changes. Without this flag, print a dry-run plan.
  -h, --help                Show this help.

This script does not add vendor package repositories or reload NVIDIA kernel
modules. Configure trusted repositories separately using vendor documentation.
USAGE
}

host=""
apply=false
install_toolkit=false
configure_docker=false
restart_docker=false
install_ncu=false
ncu_package=""
ssh_cmd=(ssh)

while (($#)); do
  case "$1" in
    --host) host=${2:?missing value}; shift 2 ;;
    --ssh-option) ssh_cmd+=(-o "${2:?missing value}"); shift 2 ;;
    --apply) apply=true; shift ;;
    --install-toolkit) install_toolkit=true; shift ;;
    --configure-docker) configure_docker=true; shift ;;
    --restart-docker) restart_docker=true; shift ;;
    --install-ncu) install_ncu=true; shift ;;
    --ncu-package) ncu_package=${2:?missing value}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -n "$host" ]] || { echo "--host is required" >&2; exit 2; }
if ! $install_toolkit && ! $configure_docker && ! $restart_docker && ! $install_ncu; then
  echo "At least one repair action is required" >&2
  exit 2
fi
if $install_ncu && [[ -z "$ncu_package" ]]; then
  echo "--install-ncu requires --ncu-package" >&2
  exit 2
fi

remote_argv=(
  bash -s --
  "$apply"
  "$install_toolkit"
  "$configure_docker"
  "$restart_docker"
  "$install_ncu"
  "$ncu_package"
)
printf -v remote_command '%q ' "${remote_argv[@]}"
"${ssh_cmd[@]}" "$host" "$remote_command" <<'REMOTE'
set -Eeuo pipefail
apply=$1
install_toolkit=$2
configure_docker=$3
restart_docker=$4
install_ncu=$5
ncu_package=$6

if [[ $(id -u) -eq 0 ]]; then
  sudo_cmd=()
elif [[ $apply == false ]]; then
  sudo_cmd=(sudo)
elif command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
  sudo_cmd=(sudo -n)
else
  echo "Root or passwordless sudo is required for host repair" >&2
  exit 1
fi

if command -v apt-get >/dev/null 2>&1; then
  package_manager=apt
elif command -v dnf >/dev/null 2>&1; then
  package_manager=dnf
elif command -v yum >/dev/null 2>&1; then
  package_manager=yum
elif command -v zypper >/dev/null 2>&1; then
  package_manager=zypper
else
  echo "Unsupported package manager; use the host's native process manually" >&2
  exit 1
fi

print_command() {
  printf '[dry-run]'
  printf ' %q' "$@"
  printf '\n'
}
run_root() {
  if $apply; then
    ${sudo_cmd[@]+"${sudo_cmd[@]}"} "$@"
  else
    print_command ${sudo_cmd[@]+"${sudo_cmd[@]}"} "$@"
  fi
}
install_package() {
  local package=$1
  case "$package_manager" in
    apt) run_root env DEBIAN_FRONTEND=noninteractive apt-get install -y "$package" ;;
    dnf) run_root dnf install -y "$package" ;;
    yum) run_root yum install -y "$package" ;;
    zypper) run_root zypper --non-interactive install "$package" ;;
  esac
}

printf 'Mode: %s\nPackage manager: %s\n' "$([[ $apply == true ]] && echo APPLY || echo DRY-RUN)" "$package_manager"
command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L || true
command -v docker >/dev/null 2>&1 && docker info --format 'Runtimes={{json .Runtimes}}' || true
command -v nvidia-ctk >/dev/null 2>&1 && nvidia-ctk --version || true
command -v ncu >/dev/null 2>&1 && ncu --version | head -n 4 || true

if $install_toolkit; then
  install_package nvidia-container-toolkit
fi

if $configure_docker; then
  if $apply && ! command -v nvidia-ctk >/dev/null 2>&1; then
    echo "nvidia-ctk is still unavailable after installation; repository/package repair is required" >&2
    exit 1
  fi
  if [[ -f /etc/docker/daemon.json ]]; then
    backup="/etc/docker/daemon.json.docker-ncu-backup.$(date -u +%Y%m%dT%H%M%SZ)"
    run_root cp -a /etc/docker/daemon.json "$backup"
  fi
  run_root nvidia-ctk runtime configure --runtime=docker
fi

if $install_ncu; then
  install_package "$ncu_package"
fi

if $restart_docker; then
  if command -v systemctl >/dev/null 2>&1; then
    run_root systemctl restart docker
  elif command -v service >/dev/null 2>&1; then
    run_root service docker restart
  else
    echo "No supported service manager found for Docker restart" >&2
    exit 1
  fi
fi

if $apply; then
  printf '\nPost-repair checks:\n'
  command -v nvidia-ctk >/dev/null 2>&1 && nvidia-ctk --version || true
  command -v ncu >/dev/null 2>&1 && ncu --version | head -n 4 || true
  command -v docker >/dev/null 2>&1 && docker info --format 'Runtimes={{json .Runtimes}}' || true
  echo "Re-run remote_gpu_preflight.sh before benchmarking."
  echo "Run ncu_smoke.sh only when the requested branch includes NCU profiling."
else
  echo "Dry run only. Review impact and add --apply to execute the repair."
fi
REMOTE
