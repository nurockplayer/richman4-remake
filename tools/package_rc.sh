#!/usr/bin/env bash
# Build one complete private release-candidate macOS package.
#
# Every derived asset is exported from the pinned private source checkout into
# ignored .local/ output, then tools/package_macos.sh copies the referenced
# files into the .app where the game already looks for them. Original artwork
# and the resulting .app/.zip never enter public Git.
#
# Usage:
#   bash tools/package_rc.sh              # full export + package + smoke
#   RICHMAN4_RC_SKIP_EXPORT=1 bash tools/package_rc.sh   # reuse .local exports
#
# Environment:
#   RICHMAN4_CACHE_ROOT     shared cache (default /Volumes/KIOXIA/richman4-cache)
#   RICHMAN4_RC_OUTPUT_DIR  published zip directory (default <cache>/rc)
#   GODOT_BIN               Godot 4.7.2 binary (default godot)
set -euo pipefail
cd "$(dirname "$0")/.."

cache_root="${RICHMAN4_CACHE_ROOT:-/Volumes/KIOXIA/richman4-cache}"
output_dir="${RICHMAN4_RC_OUTPUT_DIR:-$cache_root/rc}"
godot_bin="${GODOT_BIN:-godot}"
catalog="$PWD/.local/imported-original/maps/catalog.json"
scene_manifest="$PWD/.local/original-scenes/manifest.json"
help_manifest="$PWD/.local/original-help/manifest.json"
report="$PWD/.local/rc-art-report.txt"

scratch="$(mktemp -d "${TMPDIR:-/tmp}/richman4-rc.XXXXXX")"
cleanup() {
  rm -rf "$scratch"
  rm -rf "$PWD/build"
}
trap cleanup EXIT

echo "Private RC package $(date '+%F %H:%M %Z')"
bash tools/disk_guard.sh --operation "Richman4 private RC package"

# 1. Verify or materialize the pinned private source in the shared cache.
bash tools/bootstrap_private_assets.sh --cache-root "$cache_root"
asset_root="$(cd "$PWD/.local/private-assets" && pwd -P)"
asset_source="$asset_root/source/dfw4cskzl_136622"
[[ -d "$asset_source/Game" && -d "$asset_source/MultiverseJourney" ]] || {
  echo "Private source editions are missing under $asset_source" >&2
  exit 1
}

# 2. Export every derived asset the runtime can load. These stay ignored and
#    are reproducible from the pinned source.
if [[ "${RICHMAN4_RC_SKIP_EXPORT:-0}" != "1" ]]; then
  mkdir -p "$PWD/.local"
  touch "$PWD/.local/.gdignore"
  python3 tools/import_original.py \
    --source "$asset_source" \
    --output "$PWD/.local/imported-original"
  python3 tools/decode_original_ground.py \
    --source "$asset_source" \
    --output "$PWD/.local/original-scenes"
  python3 tools/export_original_help.py \
    --asset-root "$asset_source" \
    --output "$PWD/.local/original-help"
fi
for required in "$catalog" "$scene_manifest" "$help_manifest"; do
  [[ -f "$required" ]] || {
    echo "Derived asset is missing: $required" >&2
    exit 1
  }
done

# 3. Build the app with the existing private packaging path.
RICHMAN4_MAP_CATALOG="$catalog" \
RICHMAN4_SCENE_MANIFEST="$scene_manifest" \
RICHMAN4_HELP_MANIFEST="$help_manifest" \
RICHMAN4_AUDIO_ASSETS="$asset_root" \
RICHMAN4_SKIP_INSTALLED_CATALOG_CHECKS=1 \
GODOT_BIN="$godot_bin" \
  bash tools/package_macos.sh

app_path="$(find "$PWD/build" -maxdepth 2 -name '*.app' -type d -print -quit)"
[[ -n "$app_path" ]] || {
  echo "Packaged .app was not found under build/" >&2
  exit 1
}
private_zip="$PWD/build/Richman4-private.zip"
[[ -f "$private_zip" ]] || {
  echo "Private package was not produced: $private_zip" >&2
  exit 1
}

# 4. Smoke the packaged resources headlessly: every presenter key must resolve
#    to a real texture from the copied bundle. No window is opened.
mkdir -p "$scratch/userdata"
set +e
RICHMAN4_USER_ROOT="$scratch/userdata" "$godot_bin" --headless --path . \
  --script tools/rc_art_report.gd -- "$app_path/Contents/Resources/Original" \
  | tee "$report"
report_status="${PIPESTATUS[0]}"
set -e
if [[ "$report_status" -ne 0 ]]; then
  echo "Packaged art report reported missing presenter art; see $report" >&2
  exit 1
fi

# 5. Publish atomically: stage next to the final name, verify the copy, then
#    rename. A failed rebuild must never leave a partial zip under the
#    legitimate release name.
mkdir -p "$output_dir"
short_sha="$(git rev-parse --short=8 HEAD)"
zip_name="Richman4-rc1-$short_sha.zip"
staging_zip="$(mktemp "$output_dir/.$zip_name.XXXXXX")"
staging_sha="$(mktemp "$output_dir/.$zip_name.sha256.XXXXXX")"
trap 'cleanup; rm -f "$staging_zip" "$staging_sha"' EXIT
cp "$private_zip" "$staging_zip"
expected_digest="$(shasum -a 256 "$private_zip" | awk '{print $1}')"
staged_digest="$(shasum -a 256 "$staging_zip" | awk '{print $1}')"
[[ "$staged_digest" == "$expected_digest" ]] || {
  echo "Staged RC copy does not match $private_zip" >&2
  exit 1
}
unzip -tq "$staging_zip" >/dev/null || {
  echo "Staged RC zip failed its integrity check" >&2
  exit 1
}
printf '%s  %s\n' "$staged_digest" "$zip_name" >"$staging_sha"
mv -f "$staging_zip" "$output_dir/$zip_name"
mv -f "$staging_sha" "$output_dir/$zip_name.sha256"
echo "$staged_digest  $zip_name"
echo "RC package: $output_dir/$zip_name"
echo "Art report: $report"
