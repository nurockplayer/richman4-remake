#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT_BIN="${GODOT_BIN:-godot}"
if [[ "$("$GODOT_BIN" --version)" != 4.7.2.stable.* ]]; then
  echo 'Packaging requires Godot 4.7.2 stable.' >&2
  exit 1
fi
bash tools/check.sh
catalog_path="${RICHMAN4_MAP_CATALOG:-}"
scene_path="${RICHMAN4_SCENE_MANIFEST:-}"
help_path="${RICHMAN4_HELP_MANIFEST:-}"
audio_assets="${RICHMAN4_AUDIO_ASSETS:-}"
scene_base_args=()
if [[ -n "${RICHMAN4_SCENE_BASE_MANIFEST:-}" ]]; then
  scene_base_args+=(--base-manifest "$RICHMAN4_SCENE_BASE_MANIFEST")
fi
if [[ -n "$catalog_path" ]]; then
  "$GODOT_BIN" --headless --path . --script tools/validate_catalog.gd -- "$catalog_path" --original-facilities
fi
mkdir -p build
touch build/.gdignore
package_dir="$(mktemp -d "$PWD/build/linux-package.XXXXXX")"
bundle="$package_dir/Richman4"
mkdir -p "$bundle"
"$GODOT_BIN" --headless --path . --export-release Linux "$bundle/Richman4.x86_64"
chmod +x "$bundle/Richman4.x86_64"
if [[ -n "$catalog_path" ]]; then
  mkdir -p "$bundle/Original/maps"
  cp "$catalog_path" "$bundle/Original/maps/catalog.json"
fi
if [[ -n "$scene_path" ]]; then
  python3 tools/package_scene_images.py "$scene_path" "${scene_base_args[@]}" --destination "$bundle/Original/scenes"
fi
if [[ -n "$help_path" ]]; then
  python3 tools/package_help.py "$help_path" --destination "$bundle/Original/help"
fi
if [[ -n "$audio_assets" ]]; then
  python3 tools/package_music.py --asset-root "$audio_assets" --config config/private-assets.json --destination "$bundle/Original/audio"
fi
cat > "$bundle/README.txt" <<'README'
Richman4 Linux x86_64
Run ./Richman4.x86_64. Keep Richman4.pck and Original/ beside the executable.
Requires a Linux x86_64 desktop with OpenGL 3.3 support. No Godot editor needed.
Save files use Godot's normal per-user app data directory, not this bundle.
Original assets remain private. A release bundle without the complete original
map catalog opens the title but cannot start an ordinary game. The fallback test
board is available only through an explicit development path.
README
output="build/Richman4-linux-x86_64.tar.gz"
if [[ -n "$catalog_path$scene_path$help_path$audio_assets" ]]; then
  output="build/Richman4-linux-x86_64-private.tar.gz"
fi
tar -C "$package_dir" -czf "$output" Richman4
printf 'Application: %s\n' "$bundle/Richman4.x86_64"
sha256sum "$output"
