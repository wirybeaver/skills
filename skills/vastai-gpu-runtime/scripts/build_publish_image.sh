#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Build and optionally publish a Docker image with source and image metadata.

Usage:
  build_publish_image.sh --image REPOSITORY [options]

Required:
  --image REPOSITORY       Image repository without a tag.

Options:
  --context DIR            Build context (default: .).
  --dockerfile FILE        Dockerfile path, relative to context or absolute (default: Dockerfile).
  --tag TAG                Image tag (default: sha-<12-char git commit>; required outside git).
  --platform LIST          Buildx platform list, for example linux/amd64.
  --target STAGE           Docker build target.
  --build-arg KEY=VALUE    Repeatable non-secret build argument; values are redacted from script output.
  --label KEY=VALUE        Repeatable non-secret image label.
  --no-cache               Disable the build cache.
  --push                   Push with docker buildx; otherwise load/build locally.
  --registry HOST          Registry used for optional login.
  --username USER          Registry username; requires --registry and --token-env.
  --token-env NAME         Environment variable containing the registry token.
  --metadata-dir DIR       Metadata output (default: ./artifacts/docker-build).
  --dry-run                Print the Docker command without executing it.
  -h, --help               Show this help.

Credentials are read only from the named environment variable and sent through
`docker login --password-stdin`. They are never accepted as command arguments.
Build arguments and labels are visible to Docker; this helper rejects common
secret-bearing key names. Use a different, reviewed BuildKit-secret workflow
when the build genuinely needs a secret.
USAGE
}

sha256_file() {
  if command -v sha256sum >/dev/null; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

reject_sensitive_key() {
  local kind=$1
  local value=$2
  local key=${value%%=*}
  local upper_key
  [[ "$value" == *=* && -n "$key" ]] || {
    echo "$kind must use KEY=VALUE" >&2
    exit 2
  }
  upper_key=$(printf '%s' "$key" | tr '[:lower:]' '[:upper:]')
  if [[ "$upper_key" =~ (TOKEN|PASSWORD|PASSWD|SECRET|CREDENTIAL|PRIVATE_KEY|API_KEY|AUTH) ]]; then
    echo "$kind key looks secret-bearing and is not accepted: $key" >&2
    exit 2
  fi
}

print_sanitized_command() {
  local redact_next=false
  local arg key
  for arg in "$@"; do
    if $redact_next; then
      key=${arg%%=*}
      printf ' %q' "${key}=<redacted>"
      redact_next=false
    else
      printf ' %q' "$arg"
      [[ "$arg" == --build-arg ]] && redact_next=true
    fi
  done
  printf '\n'
}

context="."
dockerfile="Dockerfile"
image=""
tag=""
platform=""
target=""
push=false
no_cache=false
registry=""
username=""
token_env=""
metadata_dir="./artifacts/docker-build"
dry_run=false
build_args=()
labels=()

while (($#)); do
  case "$1" in
    --context) context=${2:?missing value}; shift 2 ;;
    --dockerfile) dockerfile=${2:?missing value}; shift 2 ;;
    --image) image=${2:?missing value}; shift 2 ;;
    --tag) tag=${2:?missing value}; shift 2 ;;
    --platform) platform=${2:?missing value}; shift 2 ;;
    --target) target=${2:?missing value}; shift 2 ;;
    --build-arg) build_args+=("${2:?missing value}"); shift 2 ;;
    --label) labels+=("${2:?missing value}"); shift 2 ;;
    --no-cache) no_cache=true; shift ;;
    --push) push=true; shift ;;
    --registry) registry=${2:?missing value}; shift 2 ;;
    --username) username=${2:?missing value}; shift 2 ;;
    --token-env) token_env=${2:?missing value}; shift 2 ;;
    --metadata-dir) metadata_dir=${2:?missing value}; shift 2 ;;
    --dry-run) dry_run=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

for value in ${build_args[@]+"${build_args[@]}"}; do
  reject_sensitive_key "--build-arg" "$value"
done
for value in ${labels[@]+"${labels[@]}"}; do
  reject_sensitive_key "--label" "$value"
done

[[ -n "$image" ]] || { echo "--image is required" >&2; exit 2; }
[[ -d "$context" ]] || { echo "Build context does not exist: $context" >&2; exit 2; }
command -v docker >/dev/null || { echo "docker is required" >&2; exit 1; }
context=$(cd "$context" && pwd)
if [[ "$dockerfile" != /* ]]; then
  dockerfile="$context/$dockerfile"
fi
[[ -f "$dockerfile" ]] || { echo "Dockerfile does not exist: $dockerfile" >&2; exit 2; }

source_commit="unknown"
source_dirty="unknown"
if git -C "$context" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  source_commit=$(git -C "$context" rev-parse HEAD)
  if [[ -n $(git -C "$context" status --porcelain --untracked-files=normal) ]]; then
    source_dirty=true
  else
    source_dirty=false
  fi
fi

if [[ -z "$tag" ]]; then
  [[ "$source_commit" != unknown ]] || {
    echo "--tag is required when the context is not in a Git worktree" >&2
    exit 2
  }
  tag="sha-${source_commit:0:12}"
fi
full_ref="${image}:${tag}"

if [[ -n "$registry" || -n "$username" || -n "$token_env" ]]; then
  [[ -n "$registry" && -n "$username" && -n "$token_env" ]] || {
    echo "--registry, --username, and --token-env must be supplied together" >&2
    exit 2
  }
  [[ -n "${!token_env-}" ]] || {
    echo "Registry token environment variable is unset or empty: $token_env" >&2
    exit 2
  }
fi

if $push || [[ -n "$platform" ]]; then
  docker buildx version >/dev/null 2>&1 || {
    echo "docker buildx is required for --push or --platform" >&2
    exit 1
  }
  cmd=(docker buildx build --file "$dockerfile" --tag "$full_ref")
  [[ -n "$platform" ]] && cmd+=(--platform "$platform")
  [[ -n "$target" ]] && cmd+=(--target "$target")
  $no_cache && cmd+=(--no-cache)
  for value in ${build_args[@]+"${build_args[@]}"}; do cmd+=(--build-arg "$value"); done
  for value in ${labels[@]+"${labels[@]}"}; do cmd+=(--label "$value"); done
  if $push; then
    cmd+=(--push)
  else
    [[ "$platform" != *,* ]] || {
      echo "A multi-platform build cannot be loaded locally; add --push" >&2
      exit 2
    }
    cmd+=(--load)
  fi
  cmd+=("$context")
else
  cmd=(docker build --file "$dockerfile" --tag "$full_ref")
  [[ -n "$target" ]] && cmd+=(--target "$target")
  $no_cache && cmd+=(--no-cache)
  for value in ${build_args[@]+"${build_args[@]}"}; do cmd+=(--build-arg "$value"); done
  for value in ${labels[@]+"${labels[@]}"}; do cmd+=(--label "$value"); done
  cmd+=("$context")
fi

printf 'Source commit: %s\nSource dirty: %s\nImage: %s\nCommand:' "$source_commit" "$source_dirty" "$full_ref"
print_sanitized_command "${cmd[@]}"

if $dry_run; then
  exit 0
fi

docker_config_dir=""
cleanup() {
  if [[ -n "$docker_config_dir" ]]; then
    DOCKER_CONFIG="$docker_config_dir" docker logout "$registry" >/dev/null 2>&1 || true
    rm -f -- "$docker_config_dir/config.json"
    rmdir -- "$docker_config_dir" 2>/dev/null || true
  fi
}
trap cleanup EXIT

if [[ -n "$registry" ]]; then
  docker_config_dir=$(mktemp -d)
  printf '%s' "${!token_env}" | DOCKER_CONFIG="$docker_config_dir" \
    docker login "$registry" --username "$username" --password-stdin >/dev/null
fi

if [[ -n "$docker_config_dir" ]]; then
  DOCKER_CONFIG="$docker_config_dir" "${cmd[@]}"
else
  "${cmd[@]}"
fi
mkdir -p "$metadata_dir"
metadata_dir=$(cd "$metadata_dir" && pwd)
metadata_rel=""
case "$metadata_dir/" in
  "$context/"*) metadata_rel=${metadata_dir#"$context/"} ;;
esac

cp "$dockerfile" "$metadata_dir/Dockerfile"
dockerfile_sha256=$(sha256_file "$metadata_dir/Dockerfile")

source_tree_sha256=unknown
source_status_sha256=unknown
source_patch_sha256=unknown
if [[ "$source_commit" != unknown ]]; then
  git -C "$context" status --porcelain=v1 --untracked-files=all \
    > "$metadata_dir/source-status.txt"
  git -C "$context" diff --binary HEAD > "$metadata_dir/source.patch"
  (
    cd "$context"
    git ls-files -co --exclude-standard | LC_ALL=C sort | while IFS= read -r path; do
      [[ -f "$path" ]] || continue
      if [[ -n "$metadata_rel" && ( "$path" == "$metadata_rel" || "$path" == "$metadata_rel/"* ) ]]; then
        continue
      fi
      printf '%s  %s\n' "$(sha256_file "$path")" "$path"
    done
  ) > "$metadata_dir/source-files.sha256"
  source_tree_sha256=$(sha256_file "$metadata_dir/source-files.sha256")
  source_status_sha256=$(sha256_file "$metadata_dir/source-status.txt")
  source_patch_sha256=$(sha256_file "$metadata_dir/source.patch")
fi

(
  cd "$context"
  find . -type f ! -path './.git/*' -print | LC_ALL=C sort |
    while IFS= read -r path; do
      path=${path#./}
      if [[ -n "$metadata_rel" && ( "$path" == "$metadata_rel" || "$path" == "$metadata_rel/"* ) ]]; then
        continue
      fi
      printf '%s  %s\n' "$(sha256_file "$path")" "$path"
    done
) > "$metadata_dir/context-files.sha256"
context_tree_sha256=$(sha256_file "$metadata_dir/context-files.sha256")

: > "$metadata_dir/build-args.txt"
for value in ${build_args[@]+"${build_args[@]}"}; do
  printf '%s\n' "$value" >> "$metadata_dir/build-args.txt"
done
printf '%s\n' ${labels[@]+"${labels[@]}"} > "$metadata_dir/labels.txt"
print_sanitized_command "${cmd[@]}" > "$metadata_dir/build-command.txt"
build_args_sha256=$(sha256_file "$metadata_dir/build-args.txt")
labels_sha256=$(sha256_file "$metadata_dir/labels.txt")
build_command_sha256=$(sha256_file "$metadata_dir/build-command.txt")

image_id=""
image_digest=""
if docker image inspect "$full_ref" >/dev/null 2>&1; then
  image_id=$(docker image inspect --format '{{.Id}}' "$full_ref")
  image_digest=$(docker image inspect --format '{{join .RepoDigests ","}}' "$full_ref" 2>/dev/null || true)
fi
if $push; then
  if [[ -n "$docker_config_dir" ]]; then
    remote_digest=$(DOCKER_CONFIG="$docker_config_dir" docker buildx imagetools inspect "$full_ref" 2>/dev/null | awk '/^Digest:/ {print $2; exit}')
  else
    remote_digest=$(docker buildx imagetools inspect "$full_ref" 2>/dev/null | awk '/^Digest:/ {print $2; exit}')
  fi
  [[ -z "$remote_digest" ]] || image_digest="${image}@${remote_digest}"
fi

cat > "$metadata_dir/build.env" <<META
SOURCE_COMMIT=$source_commit
SOURCE_DIRTY=$source_dirty
SOURCE_TREE_SHA256=$source_tree_sha256
SOURCE_STATUS_SHA256=$source_status_sha256
SOURCE_PATCH_SHA256=$source_patch_sha256
IMAGE_REF=$full_ref
IMAGE_ID=$image_id
IMAGE_DIGEST=$image_digest
DOCKERFILE=$dockerfile
DOCKERFILE_SHA256=$dockerfile_sha256
BUILD_CONTEXT=$context
BUILD_CONTEXT_TREE_SHA256=$context_tree_sha256
BUILD_ARGS_SHA256=$build_args_sha256
LABELS_SHA256=$labels_sha256
BUILD_COMMAND_SHA256=$build_command_sha256
PLATFORM=$platform
TARGET=$target
NO_CACHE=$no_cache
PUSHED=$push
META

(cd "$metadata_dir" && {
  : > SHA256SUMS
  for file in Dockerfile build-args.txt build-command.txt build.env context-files.sha256 labels.txt source-files.sha256 source-status.txt source.patch; do
    [[ -f "$file" ]] || continue
    printf '%s  %s\n' "$(sha256_file "$file")" "$file" >> SHA256SUMS
  done
})
printf 'Metadata: %s\n' "$metadata_dir/build.env"
[[ -z "$image_digest" ]] || printf 'Immutable image: %s\n' "$image_digest"
