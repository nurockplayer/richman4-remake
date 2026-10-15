# Linux x86_64

Use Godot **4.7.2 stable**, Python 3, Bash and standard `tar`/`sha256sum`.
No Node, browser, or Godot editor is required by the exported game.
A desktop session and OpenGL 3.3-capable driver are required. The compatibility
renderer can also run with Mesa software rendering. Audio playback additionally
requires a working desktop audio device.

## Build and start

```sh
python3 tools/install_templates.py --platform linux
bash tools/package_linux.sh
tar -xzf build/Richman4-linux-x86_64.tar.gz
./Richman4/Richman4.x86_64
```

`GODOT_BIN` selects the pinned executable. Template installation honors
`XDG_DATA_HOME` and supports `--template-dir` for an explicit Godot template
location. The installer downloads the official full template archive, verifies
the repository's pinned SHA-512, and extracts only the two Linux x86_64 templates.
The packaging script runs `tools/check.sh` before export; a failed check stops it.

The executable, `Richman4.pck`, and optional `Original/` tree must stay together.
Launch works from another current directory and after relocating the bundle.
Saves/settings remain under Godot's per-user app-data directory. Tests should
set isolated `XDG_DATA_HOME`, `XDG_CONFIG_HOME`, and `XDG_CACHE_HOME` to avoid
modifying the player's saves. If the execution sandbox exposes a non-repository
`.git` marker under `/tmp`, set `TMPDIR` to an existing ignored directory such
as `$PWD/.local/test-tmp`; do not weaken the private-output Git safety checks.

## Private content

The canonical source and pinned manifest remain unchanged. Follow
[assets.md](assets.md) using authenticated Git and Git LFS access. On Linux the
shared source cache defaults to `${XDG_CACHE_HOME:-~/.cache}/richman4-remake`.
Set `RICHMAN4_CACHE_ROOT` when an explicit shared cache location is required.

The existing four inputs are supported by both desktop packagers:

- `RICHMAN4_MAP_CATALOG`: validated original-map catalog
- `RICHMAN4_SCENE_MANIFEST`: decoded scene/UI manifest
- `RICHMAN4_HELP_MANIFEST`: source help manifest
- `RICHMAN4_AUDIO_ASSETS`: verified canonical private asset root

`RICHMAN4_SCENE_BASE_MANIFEST` remains available for scene-manifest overlays.
A private Linux package places these below `Original/{maps,scenes,help,audio}`
next to the executable and outputs `build/Richman4-linux-x86_64-private.tar.gz`.
It must not be published to the public repository without asset publication rights.
A release package without a complete private catalog opens the title but refuses
to start an ordinary game, with a visible missing-content explanation. The
fallback test board exists only in an explicit development path. Neither an
asset-free launch nor a developer fallback proves original-content playability
or fidelity.

## Validation boundary

Linux packaging and focused path tests do not replace native gameplay QA. Use
normal title/new-game entry and screenshot-driven mouse/keyboard actions, without
scene-tree queries, game-state inspection, or injected fixtures to choose actions
or assert visible outcomes. Code tests and debugging are separate supporting
engineering evidence. Record exercised paths, failures and untested paths; do not
claim exhaustive absence of bugs.
