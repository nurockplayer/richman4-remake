# Issue #101 private render-fixture runner

`capture_runner.gd` prepares a deterministic 640x480 render batch for the
repaired property, stock and other HUD projections, the full-map and player
inspection overlays, and settlement layering. It uses the pinned `Game:1`
entry from the full local catalog, creates save-valid fixture states, and
records the actual checkout SHA plus catalog, scene-manifest and code hashes in
each sidecar.

The runner is intentionally unlaunched during code handback. Root may run it
after the candidate HEAD is frozen and the owner-isolated graphical batch is
authorized. It drives presentation methods in a `SubViewport`; it does not
send OS input and its output is not ordinary native-input acceptance evidence.
Every sidecar marks `fixture=true`, stores the complete validated fixture state,
and records whether the render action changed simulation state. The exact
source composition of the full-map and player-inspect overlays is explicitly
marked unknown.

Example invocation (run only in the private asset environment):

```sh
RICHMAN4_MAP_CATALOG=/private/path/catalog.json \
RICHMAN4_SCENE_MANIFEST=/private/path/scenes/manifest.json \
RICHMAN4_NATIVE_CAPTURE_DIR=/private/path/issue101-render-batch \
godot --headless --path . --script E/native-101-integrated-repair/capture_runner.gd
```

The output directory is intentionally external to the repository. Do not add
its PNG/JSON captures or original/derived assets to Git.
