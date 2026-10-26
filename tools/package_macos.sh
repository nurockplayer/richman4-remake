#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT_BIN="${GODOT_BIN:-godot}"
if [[ "$("$GODOT_BIN" --version)" != 4.7.2.stable.* ]]; then
  echo 'Packaging requires Godot 4.7.2 stable.' >&2
  exit 1
fi
# Run the test gate without the packaging environment.  The installed-catalog
# lane requires the owner's canonical catalog identity, and tests assert the
# explicit art-free/catalog-free fallbacks: they must not see the private
# exports being packaged, including the res://.local fallbacks the runtime
# takes when an environment variable is unset.
hidden=()
restore_hidden() {
  for dir in "${hidden[@]}"; do
    if [[ -d "$dir.gate-hidden" && ! -e "$dir" ]]; then
      mv "$dir.gate-hidden" "$dir"
    fi
  done
  hidden=()
}
check_status=0
# A killed run (SIGKILL, power loss) skips the EXIT trap and leaves a
# *.gate-hidden directory; moving a fresh export onto it would nest the two.
for dir in .local/original-scenes .local/original-help .local/imported-original; do
  if [[ -e "$dir.gate-hidden" ]]; then
    echo "Found $dir.gate-hidden from an interrupted run; move it back to $dir (or remove the stale copy) and retry." >&2
    exit 1
  fi
done
trap restore_hidden EXIT
for dir in .local/original-scenes .local/original-help .local/imported-original; do
  if [[ -d "$dir" ]]; then
    mv "$dir" "$dir.gate-hidden"
    hidden+=("$dir")
  fi
done
env -u RICHMAN4_MAP_CATALOG -u RICHMAN4_SCENE_MANIFEST -u RICHMAN4_SCENE_BASE_MANIFEST \
    -u RICHMAN4_HELP_MANIFEST -u RICHMAN4_AUDIO_ASSETS bash tools/check.sh \
  || check_status=$?
restore_hidden
(( check_status == 0 )) || exit "$check_status"
catalog_path="${RICHMAN4_MAP_CATALOG:-}"
if [[ -n "$catalog_path" ]]; then
  "$GODOT_BIN" --headless --path . --script tools/validate_catalog.gd -- "$catalog_path" --original-facilities
fi
scene_path="${RICHMAN4_SCENE_MANIFEST:-}"
scene_base_manifest="${RICHMAN4_SCENE_BASE_MANIFEST:-}"
if [[ -n "$scene_path" ]]; then
  scene_base_args=()
  if [[ -n "$scene_base_manifest" ]]; then
    scene_base_args+=(--base-manifest "$scene_base_manifest")
  fi
  python3 tools/package_scene_images.py "$scene_path" "${scene_base_args[@]}"
fi
audio_assets="${RICHMAN4_AUDIO_ASSETS:-}"
help_path="${RICHMAN4_HELP_MANIFEST:-}"
if [[ -n "$help_path" ]]; then
  python3 tools/package_help.py "$help_path"
fi
mkdir -p build
"$GODOT_BIN" --headless --path . --export-release macOS build/Richman4.zip
# Extract only our generated application, keeping earlier artifacts untouched.
package_dir="$(mktemp -d "$PWD/build/package.XXXXXX")"
ditto -x -k build/Richman4.zip "$package_dir"
app_path="$(find "$package_dir" -maxdepth 1 -name '*.app' -type d -print -quit)"
[[ -n "$app_path" ]]
output_zip="build/Richman4.zip"
if [[ -n "$catalog_path" ]]; then
  mkdir -p "$app_path/Contents/Resources/Original/maps"
  cp "$catalog_path" "$app_path/Contents/Resources/Original/maps/catalog.json"
fi
if [[ -n "$scene_path" ]]; then
  python3 tools/package_scene_images.py "$scene_path" "${scene_base_args[@]}" --destination "$app_path/Contents/Resources/Original/scenes"
fi
if [[ -n "$help_path" ]]; then
  python3 tools/package_help.py "$help_path" --destination "$app_path/Contents/Resources/Original/help"
fi
if [[ -n "$audio_assets" ]]; then
  python3 tools/package_music.py \
    --asset-root "$audio_assets" \
    --config config/private-assets.json \
    --destination "$app_path/Contents/Resources/Original/audio"
fi
if [[ -n "$catalog_path" || -n "$scene_path" || -n "$audio_assets" || -n "$help_path" ]]; then
  codesign --force --deep --sign - "$app_path"
  output_zip="build/Richman4-private.zip"
  ditto -c -k --sequesterRsrc --keepParent "$app_path" "$output_zip"
fi
codesign --verify --deep --strict "$app_path"
echo "Application: $app_path"
shasum -a 256 "$output_zip"
