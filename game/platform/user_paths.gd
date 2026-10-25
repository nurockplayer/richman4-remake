class_name RichmanUserPaths
extends RefCounted
## One switch for every runtime write root.
##
## Tests export RICHMAN4_USER_ROOT as an absolute scratch directory so a
## headless run never reads or writes the owner's real user:// files. An unset
## or empty variable keeps the shipped user:// behaviour unchanged.

const ENV_ROOT := "RICHMAN4_USER_ROOT"
const USER_ROOT := "user://"


## The absolute override root, or "" when the owner's user:// stays in charge.
static func override_root() -> String:
	return OS.get_environment(ENV_ROOT)


## Resolve a path relative to the active write root.
static func path(relative: String) -> String:
	var root := override_root()
	if root.is_empty():
		return USER_ROOT + relative
	# Plain FileAccess writes (settings, hotkeys, audio, legacy save) do not
	# create parents, so make sure the override root itself exists.
	DirAccess.make_dir_recursive_absolute(root)
	return root.path_join(relative)


## Translate a path explicitly written as user://. Absolute and res:// paths
## pass through so callers keep their own validation.
static func resolve(candidate: String) -> String:
	if not candidate.begins_with(USER_ROOT):
		return candidate
	return path(candidate.trim_prefix(USER_ROOT))
