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

#? Replaces Candy Tools' files with a checked release's. A port of Candy Wizard's Self_Updater.gd, with one
#? difference: other add-ons install their tools in Candy Tools' tools folder (Candy Loot, Candy Triggers),
#? so only the files Candy Tools owns are ever removed - the core, and the tool folders the release names
#? in its manifest's "tools" (the ones it ships, and ones Candy Tools no longer ships).
#? The running Candy Tools is still the old one in memory: nothing here makes Godot scan the files, and the
#? editor restarts right after.

signal progress(fraction: float, message: String)

const Updates = preload("candy_tools_updates.gd")
const TOOLS_FOLDER := "tools"

#^ Set before plan() - Updates.package(), opened and verified:
var package = null

#^ The plan, paths inside Candy Tools' folder:
var problem := ""
var installed_version := ""
var changed: PackedStringArray = []
var added: PackedStringArray = []
var removed: PackedStringArray = []

#^ What update() did:
var backup_folder := ""


#* Plan the update, changing nothing. Sets problem on failure:
func plan() -> void:
	problem = ""
	changed.clear()
	added.clear()
	removed.clear()
	installed_version = Updates.installed_version()
	if Updates.is_dev_project():
		problem = "This is Candy Tools' development project: its folder is the source, so Candy Tools never updates itself here."
		return
	if Updates.compare_versions(package.version(), installed_version) <= 0:
		problem = "Candy Tools %s is installed, and this release is %s: only a newer release can update it." % [installed_version, package.version()]
		return

	var release_files: Dictionary = package.relative_files()
	for relative in release_files:
		var target := Updates.FOLDER.path_join(relative)
		if not FileAccess.file_exists(target):
			added.append(relative)
		elif Updates.content_hash(relative, FileAccess.get_file_as_bytes(target)) != String(package.files()[release_files[relative]].get("sha256", "")):
			changed.append(relative)
	var owned_tools := _owned_tools()
	for relative in _files_in(Updates.FOLDER):
		if relative.get_extension() in ["uid", "import"] or release_files.has(relative):
			continue
		if _is_owned(relative, owned_tools):
			removed.append(relative)
	changed.sort()
	added.sort()
	removed.sort()


#* The tool folders Candy Tools owns, from the manifest - only these are cleaned:
func _owned_tools() -> PackedStringArray:
	var owned: PackedStringArray = []
	var listed = package.manifest.get("tools", [])
	if listed is Array:
		for folder_name in listed:
			if Updates.is_safe_relative_path(String(folder_name)) and not "/" in String(folder_name):
				owned.append(String(folder_name))
	return owned


static func _is_owned(relative: String, owned_tools: PackedStringArray) -> bool:
	if not relative.begins_with(TOOLS_FOLDER + "/"):
		return true		#/ The core
	var parts := relative.split("/")
	return parts.size() > 2 and parts[1] in owned_tools


#* Update the files. Returns an error, or "". The editor must restart after:
func update(tree: SceneTree) -> String:
	plan()
	if problem != "":
		return problem
	progress.emit(0.05, "Keeping a copy of Candy Tools %s…" % installed_version)
	await tree.process_frame
	var error := _back_up()
	if error != "":
		return error
	var journal := []
	error = await _apply(tree, journal)
	if error != "":
		progress.emit(0.5, "Putting Candy Tools back…")
		var failures := _roll_back(journal)
		if failures.is_empty():
			return error + " Nothing was changed: Candy Tools was put back as it was."
		return "%s Some of Candy Tools' files couldn't be put back (%s): copy them from %s." % [error, ", ".join(failures), ProjectSettings.globalize_path(backup_folder)]
	progress.emit(1.0, "Done.")
	return ""


#* Back up the whole folder (other add-ons' tools too, so a failed update can't lose them):
func _back_up() -> String:
	var base := Updates.BACKUPS_FOLDER.path_join(installed_version if Updates.is_plain_version(installed_version) else "unknown_version")
	backup_folder = Updates.new_folder_path(base)
	for relative in _files_in(Updates.FOLDER):
		var error := Updates.copy_file(Updates.FOLDER.path_join(relative), backup_folder.path_join(relative))
		if error != "":
			return "Couldn't keep a copy of Candy Tools, so nothing was changed: " + error
	return ""


func _apply(tree: SceneTree, journal: Array) -> String:
	var release_files: Dictionary = package.relative_files()
	var total := maxi(changed.size() + added.size() + removed.size(), 1)
	var count := 0
	for relative in changed + added:
		journal.append({"type": "written", "path": relative, "existed": relative in changed})
		var error := Updates.write_file(Updates.FOLDER.path_join(relative), package.read(release_files[relative]))
		if error != "":
			return error
		count += 1
		if count % 10 == 0:
			progress.emit(0.1 + 0.85 * count / total, "Updating Candy Tools… %d / %d" % [count, total])
			await tree.process_frame
	for relative in removed:
		for path in [relative, relative + ".uid", relative + ".import"]:
			var target := Updates.FOLDER.path_join(path)
			if FileAccess.file_exists(target):
				journal.append({"type": "removed", "path": path})
				if DirAccess.remove_absolute(target) != OK:
					return "Couldn't remove %s." % target
	Updates.remove_emptied_folders(Updates.FOLDER, removed)
	return ""


#* Undo the journal from the backup, last first. Returns files not put back:
func _roll_back(journal: Array) -> PackedStringArray:
	var failures: PackedStringArray = []
	var created: PackedStringArray = []
	for index in range(journal.size() - 1, -1, -1):
		var entry: Dictionary = journal[index]
		var target := Updates.FOLDER.path_join(entry["path"])
		if entry["type"] == "written" and not entry["existed"]:
			created.append(entry["path"])
			if FileAccess.file_exists(target) and DirAccess.remove_absolute(target) != OK:
				failures.append(entry["path"])
		elif Updates.copy_file(backup_folder.path_join(entry["path"]), target) != "":
			failures.append(entry["path"])
	Updates.remove_emptied_folders(Updates.FOLDER, created)
	return failures


#* Files under a folder, relative, hidden ones included:
static func _files_in(base: String) -> PackedStringArray:
	var found: PackedStringArray = []
	_list(base, "", found)
	return found


static func _list(base: String, relative: String, found: PackedStringArray) -> void:
	var dir := DirAccess.open(base.path_join(relative))
	if dir == null:
		return
	dir.include_hidden = true
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var path := entry if relative == "" else relative + "/" + entry
		if dir.current_is_dir():
			_list(base, path, found)
		else:
			found.append(path)
		entry = dir.get_next()
	dir.list_dir_end()
