#!/usr/bin/env bash
set -euo pipefail

warn_gib="${RICHMAN4_DISK_WARN_GIB:-60}"
hard_gib="${RICHMAN4_DISK_HARD_MIN_GIB:-40}"
allow_low="${RICHMAN4_ALLOW_LOW_DISK:-0}"
probe_path="${PWD}"
operation="full materialization"

fail() {
  printf 'Disk guard failed: %s\n' "$1" >&2
  exit 1
}

usage() {
  cat >&2 <<'EOF'
Usage: bash tools/disk_guard.sh [--path PATH] [--operation LABEL]
       [--warn-gib N] [--hard-gib N]

Defaults may be overridden with RICHMAN4_DISK_WARN_GIB,
RICHMAN4_DISK_HARD_MIN_GIB, and RICHMAN4_ALLOW_LOW_DISK=1.
EOF
  exit 2
}

while (($# > 0)); do
  case "$1" in
    --path)
      (($# >= 2)) || usage
      probe_path="$2"
      shift 2
      ;;
    --operation)
      (($# >= 2)) || usage
      operation="$2"
      shift 2
      ;;
    --warn-gib)
      (($# >= 2)) || usage
      warn_gib="$2"
      shift 2
      ;;
    --hard-gib)
      (($# >= 2)) || usage
      hard_gib="$2"
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

[[ "$warn_gib" =~ ^[0-9]+$ ]] || fail "warning threshold must be a non-negative integer GiB"
[[ "$hard_gib" =~ ^[0-9]+$ ]] || fail "hard threshold must be a non-negative integer GiB"
(( warn_gib >= hard_gib )) || fail "warning threshold must be greater than or equal to hard threshold"

while [[ ! -e "$probe_path" ]]; do
  parent="$(dirname -- "$probe_path")"
  [[ "$parent" != "$probe_path" ]] || fail "cannot find an existing filesystem parent for $probe_path"
  probe_path="$parent"
done

available_kib="$(df -Pk "$probe_path" | awk 'NR == 2 { print $4 }')"
[[ "$available_kib" =~ ^[0-9]+$ ]] || fail "cannot determine free space for $probe_path"
available_gib=$(( available_kib / 1024 / 1024 ))

printf 'Disk guard: %s GiB free for %s (warn <%s GiB, hard <%s GiB)\n' \
  "$available_gib" "$operation" "$warn_gib" "$hard_gib"

if (( available_gib < hard_gib )); then
  if [[ "$allow_low" == "1" ]]; then
    printf 'WARNING: continuing below the hard disk threshold because RICHMAN4_ALLOW_LOW_DISK=1.\n' >&2
    exit 0
  fi
  fail "$operation is blocked below ${hard_gib} GiB free; reclaim space first or explicitly set RICHMAN4_ALLOW_LOW_DISK=1"
fi

if (( available_gib < warn_gib )); then
  printf 'WARNING: low free space for %s; do not create another FULL asset/Godot lane.\n' "$operation" >&2
fi
