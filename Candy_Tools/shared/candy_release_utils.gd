#!###########################################################################################
#!																							#
#!       THIS SCRIPT MAY CONTAIN CODE THAT IS THE INTELLECTUAL PROPERTY OF CANDY ARTS       #
#!                             Copyright © 2025-2026 Candy Arts                             #
#!																							#
#!    Such code may only be used in compliance with the appropriate Candy Arts licenses.    #
#!                Any unauthorized use may constitute copyright infringement.               #
#!																							#
#!###########################################################################################


@tool
extends RefCounted

#? What Candy Tools' downloads share: hashes, versions, files.
#? The hash rules match Candy Wizard's Wizard_Utils.gd and the release builders: change them together.

const USER_AGENT := "User-Agent: Candy-Tools"

#^ Files hashed with normalized line endings (as the release builders do):
const TEXT_EXTENSIONS := ["gd", "tscn", "tres", "json", "cfg", "gdshader", "md", "txt", "csv", "gitkeep", "gdignore"]


#region Hashing

static func normalized(path: String, bytes: PackedByteArray) -> PackedByteArray:
	if not path.get_extension().to_lower() in TEXT_EXTENSIONS:
		return bytes
	return bytes.get_string_from_utf8().replace("\r\n", "\n").to_utf8_buffer()


#* SHA-256 of a file's normalized content, as a release manifest writes it:
static func content_hash(path: String, bytes: PackedByteArray) -> String:
	return sha256(normalized(path, bytes)).hex_encode()


static func sha256(bytes: PackedByteArray) -> PackedByteArray:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	if bytes.size() > 0:
		context.update(bytes)
	return context.finish()


#* A content's git blob hash (SHA-1), as GitHub lists files.
#? normalize false checks a download is exactly GitHub's.
static func git_blob_hash(path: String, bytes: PackedByteArray, normalize: bool = true) -> String:
	var data := bytes
	if normalize:
		data = normalized(path, bytes)
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA1)
	var header := ("blob %d" % data.size()).to_utf8_buffer()
	header.append(0)
	context.update(header)
	if data.size() > 0:
		context.update(data)
	return context.finish().hex_encode()

#endregion


#region Versions

#* -1 when a is older than b, 0 when equal, 1 when newer ("4.6" == "4.6.0", a leading "v" ignored):
static func compare_versions(a: String, b: String) -> int:
	var parts_a := a.strip_edges().trim_prefix("v").split("-")[0].split(".")
	var parts_b := b.strip_edges().trim_prefix("v").split("-")[0].split(".")
	for index in maxi(parts_a.size(), parts_b.size()):
		var number_a := parts_a[index].to_int() if index < parts_a.size() else 0
		var number_b := parts_b[index].to_int() if index < parts_b.size() else 0
		if number_a != number_b:
			return -1 if number_a < number_b else 1
	return 0


static var _plain_version_regex := RegEx.create_from_string(r"^\d+(\.\d+)*\z")

#* Digits and dots only ("1.2.0"). Versions name folders, so nothing else is used:
static func is_plain_version(version: String) -> bool:
	return _plain_version_regex.search(version) != null


static func godot_version() -> String:
	var info := Engine.get_version_info()
	return "%d.%d.%d" % [info["major"], info["minor"], info["patch"]]


#* A plugin's version (its plugin.cfg's), or "" when it isn't there:
static func plugin_version(folder: String) -> String:
	var config := ConfigFile.new()
	if config.load(folder.path_join("plugin.cfg")) != OK:
		return ""
	return str(config.get_value("plugin", "version", "?"))

#endregion


#region Files

#* Writes a file, making its folder. Returns an error message, or "":
static func write_file(path: String, bytes: PackedByteArray) -> String:
	var dir_error := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if dir_error != OK:
		return "Couldn't create the folder %s (%s)." % [path.get_base_dir(), error_string(dir_error)]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "Couldn't write %s (%s)." % [path, error_string(FileAccess.get_open_error())]
	file.store_buffer(bytes)
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		return "Couldn't write %s (%s)." % [path, error_string(write_error)]
	return ""


#* Copies a file, making the target's folder. Returns an error message, or "":
static func copy_file(from: String, to: String) -> String:
	var dir_error := DirAccess.make_dir_recursive_absolute(to.get_base_dir())
	if dir_error != OK:
		return "Couldn't create the folder %s (%s)." % [to.get_base_dir(), error_string(dir_error)]
	var error := DirAccess.copy_absolute(from, to)
	if error != OK:
		return "Couldn't copy %s to %s (%s)." % [from, to, error_string(error)]
	return ""


#* Removes a file and its .uid / .import. Returns false if one couldn't be removed:
static func remove_with_generated(path: String) -> bool:
	var removed_all := true
	for candidate in [path, path + ".uid", path + ".import"]:
		if FileAccess.file_exists(candidate) and DirAccess.remove_absolute(candidate) != OK:
			removed_all = false
	return removed_all


#* Removes the now-empty folders (inside base) that held the given files, deepest first:
static func remove_emptied_folders(base: String, paths: PackedStringArray) -> void:
	for relative in paths:
		var folder := relative.get_base_dir()
		while folder != "":
			if not remove_if_empty(base.path_join(folder)) and DirAccess.dir_exists_absolute(base.path_join(folder)):
				break
			folder = folder.get_base_dir()


#* Removes a folder if nothing is in it, hidden files included. Returns whether it was removed:
static func remove_if_empty(path: String) -> bool:
	var dir := DirAccess.open(path)
	if dir == null:
		return false
	dir.include_hidden = true
	if not dir.get_files().is_empty() or not dir.get_directories().is_empty():
		return false
	return DirAccess.remove_absolute(path) == OK


#* Whether a path from outside stays inside the folder it's joined to:
static func is_safe_relative_path(path: String) -> bool:
	if path == "" or path.begins_with("/") or "\\" in path or ":" in path:
		return false
	for part in path.split("/"):
		if part == "" or part == "." or part == "..":
			return false
	return true


#* A folder that doesn't exist yet: base, else "base (2)", "base (3)"...
static func new_folder_path(base: String) -> String:
	var path := base
	var number := 2
	while DirAccess.dir_exists_absolute(path):
		path = "%s (%d)" % [base, number]
		number += 1
	return path


#* Has Godot scan the project's files, and waits until it's done:
static func scan_filesystem(tree: SceneTree) -> void:
	var file_system := EditorInterface.get_resource_filesystem()
	file_system.scan()
	await tree.process_frame
	while file_system.is_scanning():
		await tree.process_frame
	await tree.process_frame


#* Opens a web page, only http(s): a link from outside must never open a local file or program.
static func open_web_link(address: String) -> void:
	var link := address.strip_edges()
	if link.to_lower().begins_with("https://") or link.to_lower().begins_with("http://"):
		OS.shell_open(link)
	else:
		push_warning("Candy Tools: the link \"%s\" wasn't opened (only web links are)." % link)


#* A Dictionary kept in the EditorSettings (per machine, not per project), or {}:
static func editor_setting(setting: String) -> Dictionary:
	var settings := EditorInterface.get_editor_settings()
	if not settings.has_setting(setting):
		return {}
	var value = settings.get_setting(setting)
	return value if value is Dictionary else {}


static func set_editor_setting(setting: String, value: Dictionary) -> void:
	EditorInterface.get_editor_settings().set_setting(setting, value)

#endregion


#region Text

#* "2026-09-29T23:35:42" or "2026-09-29 23:35:42" as "on 29 Sep 2026 at 23:35":
static func readable_date(date_time: String) -> String:
	var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	var parts := date_time.replace("T", " ").split(" ")
	var date := parts[0].split("-")
	if date.size() != 3:
		return "on " + date_time
	var text := "on %d %s %s" % [date[2].to_int(), months[clampi(date[1].to_int() - 1, 0, 11)], date[0]]
	if parts.size() > 1:
		text += " at " + parts[1].substr(0, 5)
	return text


static func readable_size(bytes: int) -> String:
	if bytes < 1024:
		return "%d B" % bytes
	if bytes < 1024 * 1024:
		return "%.1f KB" % (bytes / 1024.0)
	return "%.1f MB" % (bytes / (1024.0 * 1024.0))

#endregion
