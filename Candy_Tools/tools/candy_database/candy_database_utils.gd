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
extends "res://addons/Candy_Tools/shared/candy_release_utils.gd"

#? Shared by the Candy Database tool's scripts: what's installed, the record, files and hashes.
#? Candy Wizard installs Candy Database the same way: the record, the set ids, the package and
#? manifest names and the hash rules match its Wizard_Utils.gd, so either can update what the other installed.

const CandyToolsSettings = preload("res://addons/Candy_Tools/candy_tools_settings.gd")
const GitHubSource = preload("res://addons/Candy_Tools/shared/candy_github_source.gd")
const ReleasePackage = preload("res://addons/Candy_Tools/shared/candy_release_package.gd")

const TOOL_ID := "candy_database"

#^ Candy Database's releases (GitHub is asked by the repository's ID, never its name):
const DATABASE_PACKAGE_NAME := "Candy_Database"
const DATABASE_MANIFEST_NAME := "candy_database_manifest.json"
const DATABASE_GITHUB_REPOSITORY := "Candy-Arts/Candy-Database"
const DATABASE_GITHUB_REPOSITORY_ID := 1440638590
const DATABASE_FOLDER := "res://addons/Candy_Database"
#^ Record of Candy Database and its documentation (in its folder, which its updates leave alone):
const DATABASE_RECORD_PATH := "res://addons/Candy_Database/Install_Record.json"
const RECORD_FORMAT := 1
#^ Only in Candy Database's development project, where it must never be installed:
const DATABASE_BUILDER_PATH := "res://Database_Tools/Build_Database.gd"

#^ The documentation: a signed zip per database in DOCS_REPOSITORY_FOLDER of Candy Arts' repository.
const DOCS_GITHUB_REPOSITORY := "Candy-Arts/Candy-Arts"
const DOCS_GITHUB_REPOSITORY_ID := 1177938775
const DOCS_BRANCH := "main"
const DOCS_REPOSITORY_FOLDER := "DOCUMENTATION"
const DOCS_DATABASES_FOLDER := "res://addons/Candy_Database/Databases"
const DOCS_MANIFEST_NAME := "candy_docs_manifest.json"
const DOCS_PACKAGE_NAME := "candy_docs"
const DOCS_MANIFEST_FORMAT := 1
#^ Record ids Candy Wizard gives these databases. The rest are "other_<folder>", as in Candy Wizard:
const KNOWN_DOCS_IDS := {
	"Candy_Dialogue_Engine": "candy_de",
	"Candy_Dialogue_Creator": "candy_dc",
	"Candy_Database": "candy_db",
}
const OTHER_DOCS_ID_PREFIX := "other_"
#^ The only file types downloaded as documentation (never scripts, scenes or resources):
const DOCS_EXTENSIONS := ["txt", "json", "md", "png", "jpg", "jpeg", "webp", "svg", "bmp", "ttf", "otf", "woff", "woff2", "gitkeep"]

#^ Downloads and backups:
const TEMP_FOLDER := "user://candy_tools/candy_database"
const DATABASE_BACKUPS_FOLDER := "user://candy_tools/candy_database/database_backups"
const DOCS_BACKUPS_FOLDER := "user://candy_tools/candy_database/docs_backups"

#^ Seconds between automatic looks on GitHub:
const CHECK_INTERVAL := 24 * 60 * 60
#^ Last looks on GitHub, in Candy Tools' settings:
#? release: {"time", "version"}. docs: {"time", "zips" = {folder name: zip's git hash}}.
const SETTINGS_SECTION := "github"
const SETTING_RELEASE := "release"
const SETTING_DOCS := "docs"


#^ Tests only - a local stand-in for GitHub's API and raw files:
static var test_api_base := ""
static var test_raw_base := ""
#^ Automatic looks done this session (even failed ones: a failed look isn't kept, so it would repeat):
static var _release_looked := false
static var _docs_looked := false
static var looking := false


#region Candy Database

#* Candy Database's installed version (its plugin.cfg's), or "" when it isn't there:
static func installed_database_version() -> String:
	return plugin_version(DATABASE_FOLDER)


static func is_database_dev_project() -> bool:
	return FileAccess.file_exists(DATABASE_BUILDER_PATH)


#* A reader for Candy Database's release zips:
static func database_package() -> ReleasePackage:
	return ReleasePackage.new(DATABASE_PACKAGE_NAME, DATABASE_MANIFEST_NAME, DATABASE_FOLDER, "Candy Database")


#* A GitHub source, child of parent (free it after):
static func new_source(parent: Node) -> GitHubSource:
	var source := GitHubSource.new()
	if test_api_base != "":
		source.api_base = test_api_base
	if test_raw_base != "":
		source.raw_base = test_raw_base
	parent.add_child(source)
	return source

#endregion


#region Last looks on GitHub

static func last_check(key: String) -> Dictionary:
	var value = CandyToolsSettings.get_value(TOOL_ID, SETTINGS_SECTION, key, {})
	return value if value is Dictionary else {}


static func set_last_check(key: String, value: Dictionary) -> void:
	value["time"] = Time.get_unix_time_from_system()
	CandyToolsSettings.set_values(TOOL_ID, SETTINGS_SECTION, {key: value})


#* Look up Candy Database's latest release and the documentation's databases, and keep what GitHub has.
#? forced: now; else at most once a day and once per session.
#? everything: also what isn't here yet (the panel); else only what can be updated (the editor's startup check),
#? so a project without Candy Database costs no request.
#? Returns the problems met, or null when GitHub wasn't asked.
static func look_on_github(parent: Node, forced: bool, everything: bool = true) -> Variant:
	if looking:
		return null
	var now := Time.get_unix_time_from_system()
	var installed := installed_database_version() != ""
	var downloaded = read_database_record().get("docs", {})
	var look_for_release := not is_database_dev_project() and (everything or installed)
	var look_for_docs: bool = everything or (installed and downloaded is Dictionary and not downloaded.is_empty())
	if not forced:
		look_for_release = look_for_release and not _release_looked and now - float(last_check(SETTING_RELEASE).get("time", 0.0)) >= CHECK_INTERVAL
		look_for_docs = look_for_docs and not _docs_looked and now - float(last_check(SETTING_DOCS).get("time", 0.0)) >= CHECK_INTERVAL
		_release_looked = _release_looked or look_for_release
		_docs_looked = _docs_looked or look_for_docs
	if not look_for_release and not look_for_docs:
		return null
	looking = true
	var problems: PackedStringArray = []
	var source := new_source(parent)
	if look_for_release:
		var latest: Dictionary = await fetch_latest_release(source)
		if latest.has("error"):
			problems.append("Candy Database: " + String(latest["error"]))
	if look_for_docs:
		var tree: Dictionary = await fetch_docs_tree(source)
		if tree.has("error"):
			problems.append("Documentation: " + String(tree["error"]))
	source.queue_free()
	looking = false
	return problems


#* Candy Database's latest release, kept as the last look:
static func fetch_latest_release(source: GitHubSource) -> Dictionary:
	var latest: Dictionary = await source.fetch_latest_release(DATABASE_GITHUB_REPOSITORY_ID, DATABASE_PACKAGE_NAME, "Candy Database")
	remember_latest_release(latest)
	return latest


#* The documentation branch's files, its databases kept as the last look:
static func fetch_docs_tree(source: GitHubSource) -> Dictionary:
	var tree: Dictionary = await source.fetch_tree(DOCS_GITHUB_REPOSITORY_ID, DOCS_BRANCH)
	if not tree.has("error"):
		set_last_check(SETTING_DOCS, {"zips": docs_zips(tree)})
	return tree


#* What GitHub has newer than what's here, as last looked ("Candy Database 1.0.1", "Candy Dialogue Engine documentation"):
static func updates_waiting() -> PackedStringArray:
	var waiting: PackedStringArray = []
	var installed := installed_database_version()
	if installed == "" or is_database_dev_project():
		return waiting
	var latest := String(last_check(SETTING_RELEASE).get("version", ""))
	if latest != "" and compare_versions(latest, installed) > 0:
		waiting.append("Candy Database %s" % latest)
	var zips = last_check(SETTING_DOCS).get("zips", {})
	if not zips is Dictionary:
		return waiting
	var record := read_database_record()
	for docs in docs_sets():
		var entry := docs_entry(docs, record)
		var on_github := String(zips.get(docs["name"], ""))
		if not entry.is_empty() and on_github != "" and on_github != String(entry.get("zip_hash", "")):
			waiting.append("%s documentation" % docs["title"])
	return waiting


#* Keeps the latest release found (its version when installable, "" when GitHub has none).
#? Nothing is kept when GitHub couldn't be reached.
static func remember_latest_release(latest: Dictionary) -> void:
	var version := ""
	if latest.has("asset_url") and not latest.has("error"):
		version = String(latest["version"])
	elif not latest.has("version"):
		return
	set_last_check(SETTING_RELEASE, {"version": version})

#endregion


#region Record

#* Candy Database's record, or {} when there's none:
#? "version", "installed", "updated", "files" (sha256 each) and "docs" (per set id).
static func read_database_record() -> Dictionary:
	if not FileAccess.file_exists(DATABASE_RECORD_PATH):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATABASE_RECORD_PATH))
	return parsed if parsed is Dictionary else {}


static func write_database_record(record: Dictionary) -> String:
	record["format"] = RECORD_FORMAT
	return write_file(DATABASE_RECORD_PATH, (JSON.stringify(record, "\t") + "\n").to_utf8_buffer())


#* A record's file list without paths that leave their folder (records may come from someone else):
static func safe_record_files(listed: Variant) -> Dictionary:
	var safe := {}
	if not listed is Dictionary:
		return safe
	for path in listed:
		if is_safe_relative_path(String(path)):
			safe[path] = listed[path]
	return safe

#endregion


#region Documentation sets

#* A database's set, by its folder's name in DOCS_REPOSITORY_FOLDER:
#? {"id", "title", "folder" (in the repository), "name" (the folder's name)}.
static func docs_set(folder_name: String) -> Dictionary:
	return {
		"id": KNOWN_DOCS_IDS.get(folder_name, OTHER_DOCS_ID_PREFIX + folder_name),
		"title": docs_title(folder_name),
		"folder": DOCS_REPOSITORY_FOLDER.path_join(folder_name),
		"name": folder_name,
	}


#* The databases offered: those GitHub had at the last look, and those downloaded, sorted by title:
static func docs_sets() -> Array:
	var names := {}
	var zips = last_check(SETTING_DOCS).get("zips", {})
	if zips is Dictionary:
		for folder_name in zips:
			names[String(folder_name)] = true
	var downloaded = read_database_record().get("docs", {})
	if downloaded is Dictionary:
		for id in downloaded:
			var entry = downloaded[id]
			if entry is Dictionary:
				var folder := String(entry.get("folder", ""))
				if folder.begins_with(DOCS_REPOSITORY_FOLDER + "/"):
					names[folder.trim_prefix(DOCS_REPOSITORY_FOLDER + "/")] = true
	var sets := []
	for folder_name in names:
		if is_safe_relative_path(folder_name) and not "/" in folder_name:
			sets.append(docs_set(folder_name))
	sets.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["title"]).naturalnocasecmp_to(String(b["title"])) < 0)
	return sets


#* A set's record entry, or {} when it wasn't downloaded:
static func docs_entry(docs: Dictionary, record: Dictionary = {}) -> Dictionary:
	if record.is_empty():
		record = read_database_record()
	var downloaded = record.get("docs", {})
	if not downloaded is Dictionary:
		return {}
	var entry = downloaded.get(docs["id"], {})
	return entry if entry is Dictionary else {}


#* The databases of a GitHub tree: {folder name: its zip's git hash}:
static func docs_zips(tree: Dictionary) -> Dictionary:
	var found := {}
	var prefix := DOCS_REPOSITORY_FOLDER + "/"
	for path in tree.get("files", {}):
		var file_name := String(path).trim_prefix(prefix)
		if String(path).begins_with(prefix) and not "/" in file_name and file_name.get_extension().to_lower() == "zip":
			var folder_name := file_name.get_basename()
			if is_safe_relative_path(folder_name):
				found[folder_name] = String(tree["files"][path])
	return found


#* A set's zip in the repository ("DOCUMENTATION/Candy_Dialogue_Engine.zip"):
static func docs_zip_path(docs: Dictionary) -> String:
	return String(docs["folder"]) + ".zip"


#* A database's title: its downloaded database.json's, else its folder's name:
static func docs_title(folder_name: String) -> String:
	var path := DOCS_DATABASES_FOLDER.path_join(folder_name).path_join("database.json")
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary and parsed.get("title") is String and String(parsed["title"]).strip_edges() != "":
			return String(parsed["title"]).strip_edges()
	return folder_name.replace("_", " ")

#endregion
