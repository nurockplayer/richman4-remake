extends RefCounted
## Private assets stay outside the PCK. Resolve relative to the executable,
## never the working directory, so a relocated Linux bundle remains runnable.

static func packaged_root(executable_path: String = OS.get_executable_path(), platform: String = OS.get_name()) -> String:
	var directory := executable_path.get_base_dir()
	if platform == "macOS":
		return directory.path_join("../Resources/Original").simplify_path()
	return directory.path_join("Original").simplify_path()

static func packaged(relative: String) -> String:
	return packaged_root().path_join(relative)
