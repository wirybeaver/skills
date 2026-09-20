#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Stream a remote artifact directory over SSH and create a local checksum manifest.

Usage:
  collect_artifacts.sh --host SSH_TARGET --remote-dir DIR --local-dir DIR [options]

Options:
  --host TARGET          SSH target or configured alias.
  --remote-dir DIR       Absolute path or path under remote $HOME.
  --local-dir DIR        Local destination; must be empty or absent.
  --ssh-option OPTION    Repeatable ssh -o option.
  --delete-remote        Delete the remote directory after verified transfer.
  -h, --help             Show this help.
USAGE
}

sha256_file() {
  if command -v sha256sum >/dev/null; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

verify_sha256_manifest() {
  if command -v sha256sum >/dev/null; then
    sha256sum -c "$1"
  else
    shasum -a 256 -c "$1"
  fi
}

host=""
remote_dir=""
local_dir=""
delete_remote=false
ssh_cmd=(ssh)

while (($#)); do
  case "$1" in
    --host) host=${2:?missing value}; shift 2 ;;
    --remote-dir) remote_dir=${2:?missing value}; shift 2 ;;
    --local-dir) local_dir=${2:?missing value}; shift 2 ;;
    --ssh-option) ssh_cmd+=(-o "${2:?missing value}"); shift 2 ;;
    --delete-remote) delete_remote=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -n "$host" && -n "$remote_dir" && -n "$local_dir" ]] || {
  echo "--host, --remote-dir, and --local-dir are required" >&2
  exit 2
}
if [[ -e "$local_dir" && -n $(find "$local_dir" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null) ]]; then
  echo "Local destination must be empty or absent: $local_dir" >&2
  exit 2
fi
mkdir -p "$local_dir"

remote_argv=(bash -s -- "$remote_dir")
printf -v remote_command '%q ' "${remote_argv[@]}"
"${ssh_cmd[@]}" "$host" "$remote_command" <<'REMOTE' | tar -C "$local_dir" -xf -
set -Eeuo pipefail
case "$1" in
  /*) source_dir=$1 ;;
  *) source_dir="$HOME/$1" ;;
esac
[[ -d "$source_dir" ]] || { echo "Remote artifact directory does not exist: $source_dir" >&2; exit 1; }
tar -C "$source_dir" -cf - .
REMOTE

if [[ -f "$local_dir/SHA256SUMS" ]]; then
  (cd "$local_dir" && verify_sha256_manifest SHA256SUMS)
fi
(
  cd "$local_dir"
  : > SHA256SUMS.local
  find . -type f ! -name SHA256SUMS.local -print | LC_ALL=C sort |
    while IFS= read -r path; do
      path=${path#./}
      printf '%s  %s\n' "$(sha256_file "$path")" "$path"
    done > SHA256SUMS.local
)

if $delete_remote; then
  "${ssh_cmd[@]}" "$host" "$remote_command" <<'REMOTE'
set -Eeuo pipefail
case "$1" in
  /*) target=$1 ;;
  *) target="$HOME/$1" ;;
esac
target=$(cd "$target" && pwd -P)
case "$target" in
  /|"$HOME"|/home|/root|/tmp) echo "Refusing unsafe deletion target: $target" >&2; exit 1 ;;
esac
[[ -d "$target" ]] || { echo "Remote deletion target does not exist: $target" >&2; exit 1; }
rm -rf -- "$target"
REMOTE
fi

printf 'Artifacts collected in %s\n' "$(cd "$local_dir" && pwd)"
