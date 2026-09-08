#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
project_root="$(cd -- "$script_dir/.." && pwd -P)"
config_path="$project_root/config/private-assets.json"
destination="$project_root/.local/private-assets"
repo_url=""
revision=""

fail() {
  printf 'Private asset bootstrap failed: %s\n' "$1" >&2
  exit 1
}

usage() {
  cat >&2 <<'EOF'
Usage: bash tools/bootstrap_private_assets.sh [--destination PATH] [--config PATH]
       [--repo-url URL] [--revision SHA]

The default binding is config/private-assets.json. PATH values are relative to
the code repository root unless absolute. --repo-url is intended for an
explicit test mirror; the pinned revision and manifest remain mandatory.
EOF
  exit 2
}

while (($# > 0)); do
  case "$1" in
    --destination)
      (($# >= 2)) || usage
      destination="$2"
      shift 2
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
case "$destination" in
  /*) ;;
  *) destination="$project_root/$destination" ;;
esac

[[ -f "$config_path" ]] || fail "binding file is missing: $config_path"
command -v git >/dev/null 2>&1 || fail "git is required"
git lfs version >/dev/null 2>&1 || fail "Git LFS is required; install it before retrying"

config_repo_url="$(python3 - "$config_path" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
value = json.loads(path.read_text(encoding="utf-8"))
print(value["clone_url"])
PY
)" || fail "binding file is not valid JSON"
config_revision="$(python3 - "$config_path" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
value = json.loads(path.read_text(encoding="utf-8"))
print(value["revision"])
PY
)" || fail "binding file is missing its revision"

[[ -n "$repo_url" ]] || repo_url="$config_repo_url"
[[ -n "$revision" ]] || revision="$config_revision"
[[ "$revision" == "$config_revision" ]] || fail "requested revision does not match config/private-assets.json"

destination_parent="$(dirname -- "$destination")"
mkdir -p -- "$destination_parent"
[[ ! -e "$destination" ]] || fail "destination already exists; choose a new empty path: $destination"
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

if python3 "$script_dir/atomic_publish.py" "$clone_path" "$destination"; then
  :
else
  publish_status=$?
  if [[ "$publish_status" -eq 2 ]]; then
    fail "destination appeared during bootstrap; no files were replaced: $destination"
  fi
  fail "cannot publish private assets atomically: $destination"
fi
staging=""
printf 'Private assets installed at %s\n' "$destination"
