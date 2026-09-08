#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT_BIN="${GODOT_BIN:-godot}"
if [[ "$("$GODOT_BIN" --version)" != 4.7.2.stable.* ]]; then
  echo 'Packaging requires Godot 4.7.2 stable.' >&2
  exit 1
fi
bash tools/check.sh
mkdir -p build
"$GODOT_BIN" --headless --path . --export-release macOS build/Richman4.zip
# Extract only our generated application, keeping earlier artifacts untouched.
package_dir="$(mktemp -d "$PWD/build/package.XXXXXX")"
ditto -x -k build/Richman4.zip "$package_dir"
app_path="$(find "$package_dir" -maxdepth 1 -name '*.app' -type d -print -quit)"
[[ -n "$app_path" ]]
codesign --verify --deep --strict "$app_path"
echo "Application: $app_path"
shasum -a 256 build/Richman4.zip
