#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Collect read-only NVIDIA driver diagnostics from an SSH-accessible host.

Usage:
  driver_diagnostics.sh --host SSH_TARGET [options]

Options:
  --host TARGET          SSH target or configured alias.
  --output FILE          Save output locally as well as stdout.
  --ssh-option OPTION    Repeatable ssh -o option.
  -h, --help             Show this help.

This script diagnoses the host driver. It does not install packages, reload
kernel modules, or reboot the host.
USAGE
}

host=""
output=""
ssh_cmd=(ssh)

while (($#)); do
  case "$1" in
    --host) host=${2:?missing value}; shift 2 ;;
    --output) output=${2:?missing value}; shift 2 ;;
    --ssh-option) ssh_cmd+=(-o "${2:?missing value}"); shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -n "$host" ]] || { echo "--host is required" >&2; exit 2; }
command -v ssh >/dev/null || { echo "ssh is required" >&2; exit 1; }
if [[ -n "$output" ]]; then
  mkdir -p "$(dirname "$output")"
fi

run_remote() {
  "${ssh_cmd[@]}" "$host" bash -s <<'REMOTE'
set -uo pipefail
section() { printf '\n== %s ==\n' "$1"; }

section "Identity"
printf 'boot_id='; cat /proc/sys/kernel/random/boot_id 2>/dev/null || true
hostname -f 2>/dev/null || hostname
uname -a
if [[ -r /etc/os-release ]]; then cat /etc/os-release; fi

section "PCI devices"
if command -v lspci >/dev/null 2>&1; then
  lspci -nnk | grep -A3 -Ei 'VGA|3D|NVIDIA' || true
else
  echo "lspci unavailable"
fi

section "NVIDIA userspace"
if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi -L || true
  nvidia-smi || true
  nvidia-smi --query-gpu=name,uuid,driver_version,memory.total \
    --format=csv,noheader || true
else
  echo "nvidia-smi unavailable"
fi

section "NVIDIA kernel modules"
cat /proc/driver/nvidia/version 2>/dev/null || true
lsmod | grep -E '^(nvidia|nouveau)' || true
if command -v modinfo >/dev/null 2>&1; then
  modinfo nvidia 2>/dev/null | grep -E '^(filename|version|vermagic):' || true
fi
if command -v dkms >/dev/null 2>&1; then dkms status || true; fi

section "Kernel log"
if command -v journalctl >/dev/null 2>&1; then
  journalctl -k -b --no-pager 2>&1 \
    | grep -Ei 'nvidia|nouveau|NVRM|Xid' \
    | tail -n 300 || true
elif command -v dmesg >/dev/null 2>&1; then
  dmesg 2>&1 | grep -Ei 'nvidia|nouveau|NVRM|Xid' | tail -n 300 || true
fi
REMOTE
}

if [[ -n "$output" ]]; then
  run_remote 2>&1 | tee "$output"
else
  run_remote
fi
