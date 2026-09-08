#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
project_root="$(cd -- "$script_dir/.." && pwd -P)"
config_path="$project_root/config/private-assets.json"
cache_root="${RICHMAN4_CACHE_ROOT:-}"
destination=""
destination_explicit=0
link_path=""
link_explicit=0
repo_url=""
revision=""

fail() {
  printf 'Private asset bootstrap failed: %s\n' "$1" >&2
  exit 1
}

usage() {
  cat >&2 <<'EOF'
Usage: bash tools/bootstrap_private_assets.sh [--cache-root PATH]
       [--destination PATH] [--link PATH|--no-link] [--config PATH]
       [--repo-url URL] [--revision SHA]

By default the pinned private asset revision is materialized once below
~/Library/Caches/richman4-remake/private-assets/<revision>/ and the current
worktree receives only .local/private-assets -> that shared cache.

--destination is primarily for an explicit isolated/test install. When it is
used, no worktree link is created unless --link is also supplied. --repo-url is
intended for an explicit test mirror; the pinned revision and manifest remain
mandatory.
EOF
  exit 2
}

while (($# > 0)); do
  case "$1" in
    --cache-root)
      (($# >= 2)) || usage
      cache_root="$2"
      shift 2
      ;;
    --destination)
      (($# >= 2)) || usage
      destination="$2"
      destination_explicit=1
      shift 2
      ;;
    --link)
      (($# >= 2)) || usage
      link_path="$2"
      link_explicit=1
      shift 2
      ;;
    --no-link)
      link_path=""
      link_explicit=1
      shift
      ;;
    --config)
      (($# >= 2)) || usage
      config_path="$2"
      shift 2
      ;;
    --repo-url)
      (($# >= 2)) || usage
      repo_url="$2"
      shift 2
      ;;
    --revision)
      (($# >= 2)) || usage
      revision="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      usage
      ;;
  esac
done

case "$config_path" in
  /*) ;;
  *) config_path="$project_root/$config_path" ;;
esac

[[ -f "$config_path" ]] || fail "binding file is missing: $config_path"
command -v git >/dev/null 2>&1 || fail "git is required"
command -v python3 >/dev/null 2>&1 || fail "python3 is required"

config_values="$(python3 - "$config_path" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
value = json.loads(path.read_text(encoding="utf-8"))
print(value["clone_url"])
print(value["revision"])
PY
)" || fail "binding file is not valid JSON or is missing clone_url/revision"
config_repo_url="$(printf '%s\n' "$config_values" | sed -n '1p')"
config_revision="$(printf '%s\n' "$config_values" | sed -n '2p')"

[[ -n "$repo_url" ]] || repo_url="$config_repo_url"
[[ -n "$revision" ]] || revision="$config_revision"
[[ "$revision" == "$config_revision" ]] || fail "requested revision does not match config/private-assets.json"

if [[ -z "$cache_root" && "$destination_explicit" -eq 0 ]]; then
  [[ -n "${HOME:-}" ]] || fail "HOME is required unless --cache-root or --destination is supplied"
  cache_root="$HOME/Library/Caches/richman4-remake"
fi
if [[ -n "$cache_root" ]]; then
  case "$cache_root" in
    /*) ;;
    *) cache_root="$project_root/$cache_root" ;;
  esac
fi

if (( destination_explicit == 0 )); then
  destination="$cache_root/private-assets/$revision"
else
  case "$destination" in
    /*) ;;
    *) destination="$project_root/$destination" ;;
  esac
fi

if (( link_explicit == 0 )); then
  if (( destination_explicit == 0 )); then
    link_path="$project_root/.local/private-assets"
  else
    link_path=""
  fi
elif [[ -n "$link_path" ]]; then
  case "$link_path" in
    /*) ;;
    *) link_path="$project_root/$link_path" ;;
  esac
fi

verify_destination() {
  python3 "$script_dir/verify_private_assets.py" --asset-root "$destination" --config "$config_path"
}

resolved_path() {
  python3 - "$1" <<'PY'
import os
import sys
print(os.path.realpath(sys.argv[1]))
PY
}

ensure_worktree_link() {
  [[ -n "$link_path" ]] || return 0
  link_parent="$(dirname -- "$link_path")"
  mkdir -p -- "$link_parent"

  if [[ -L "$link_path" ]]; then
    [[ "$(resolved_path "$link_path")" == "$(resolved_path "$destination")" ]] || fail "worktree asset link points somewhere else: $link_path"
    return 0
  fi

  [[ ! -e "$link_path" ]] || fail "worktree asset path already exists and is not a managed symlink: $link_path"
  if ! ln -s -- "$destination" "$link_path"; then
    if [[ -L "$link_path" && "$(resolved_path "$link_path")" == "$(resolved_path "$destination")" ]]; then
      return 0
    fi
    fail "cannot create worktree asset link: $link_path"
  fi
}

if [[ -e "$destination" || -L "$destination" ]]; then
  [[ -d "$destination" && ! -L "$destination" ]] || fail "shared cache path exists but is not a real directory: $destination"
  if ! verify_destination; then
    fail "existing shared cache failed verification; do not reuse or overwrite it: $destination"
  fi
  ensure_worktree_link
  printf 'Reusing verified private assets at %s\n' "$destination"
  [[ -z "$link_path" ]] || printf 'Worktree private asset link: %s\n' "$link_path"
  exit 0
fi

destination_parent="$(dirname -- "$destination")"
mkdir -p -- "$destination_parent"
bash "$script_dir/disk_guard.sh" --path "$destination_parent" --operation "new private asset cache"
git lfs version >/dev/null 2>&1 || fail "Git LFS is required to materialize a new private asset cache"

staging="$(mktemp -d "$destination_parent/.private-assets-bootstrap.XXXXXX")"
clone_path="$staging/repository"
cleanup() {
  if [[ -n "${staging:-}" && -d "$staging" ]]; then
    rm -rf -- "$staging"
  fi
}
trap cleanup EXIT

if ! GIT_TERMINAL_PROMPT=0 GIT_LFS_SKIP_SMUDGE=1 git clone --no-checkout "$repo_url" "$clone_path"; then
  fail "cannot clone the owner-authenticated private asset repository; check GitHub credentials and access"
fi
if ! git -C "$clone_path" checkout --detach "$revision" >/dev/null 2>&1; then
  fail "the pinned private asset revision is unavailable: $revision"
fi
if ! GIT_TERMINAL_PROMPT=0 git -C "$clone_path" lfs pull origin; then
  fail "Git LFS could not retrieve the pinned private asset content"
fi
python3 "$script_dir/verify_private_assets.py" --asset-root "$clone_path" --config "$config_path"

# The shared checkout is an immutable verified snapshot, not an authoring repo.
# LFS already materialized the working files, so its local object store is a
# second, re-downloadable copy of the same large payload. Keep Git tree/pointer
# metadata for future verification, but drop that duplicate local LFS cache.
rm -rf -- "$clone_path/.git/lfs/objects"

publish_status=0
python3 "$script_dir/atomic_publish.py" "$clone_path" "$destination" || publish_status=$?
if [[ "$publish_status" -eq 0 ]]; then
  printf 'Private assets installed in shared cache at %s\n' "$destination"
elif [[ "$publish_status" -eq 2 ]]; then
  if [[ -d "$destination" && ! -L "$destination" ]] && verify_destination; then
    printf 'Another process populated the same verified private asset cache at %s\n' "$destination"
  else
    fail "shared cache appeared during bootstrap but is not the verified pinned source: $destination"
  fi
else
  fail "cannot publish private assets atomically: $destination"
fi

ensure_worktree_link
[[ -z "$link_path" ]] || printf 'Worktree private asset link: %s\n' "$link_path"
