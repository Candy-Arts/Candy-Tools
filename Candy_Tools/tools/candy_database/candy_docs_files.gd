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

#? Downloads one database's documentation into Candy Database's Databases folder.
#? A port of Candy Wizard's Docs_Files.gd and Docs_Zip.gd: the database is a zip signed by Candy Arts,
#? checked before anything is written, and only files that differ are written.

const Utils = preload("candy_database_utils.gd")
const Signature = preload("res://addons/Candy_Tools/shared/candy_release_signature.gd")

#^ Where a downloaded zip is put to be read (ZIPReader only opens files):
const TEMP_ZIP := Utils.TEMP_FOLDER + "/docs_download.zip"

#^ Set before fetch():
var docs_set: Dictionary = {}		#/ Utils.docs_set()
var tree: Dictionary = {}			#/ Utils.fetch_docs_tree()'s answer

#^ The checked zip (fetch()), paths inside Databases:
var zip_hash := ""
var contents := {}					#/ path -> bytes

#^ The plan, paths inside Databases:
var problem := ""
var upstream := {}					#/ Every file of the zip: path -> git hash
var to_download: PackedStringArray = []
var to_remove: PackedStringArray = []
var changed_here: PackedStringArray = []
var left_out: PackedStringArray = []	#/ Files of a type never downloaded

#^ What apply() did:
var backup_folder := ""


#* Whether the zip on GitHub is the one last downloaded, and every file it brought is still here as it was:
func is_current() -> bool:
	var entry := Utils.docs_entry(docs_set)
	var on_github := String(tree.get("files", {}).get(Utils.docs_zip_path(docs_set), ""))
	if on_github == "" or String(entry.get("zip_hash", "")) != on_github:
		return false
	var recorded := recorded_files()
	for relative in recorded:
		var target := Utils.DOCS_DATABASES_FOLDER.path_join(relative)
		if not FileAccess.file_exists(target) or not _has_hash(relative, FileAccess.get_file_as_bytes(target), String(recorded[relative])):
			return false
	return not recorded.is_empty()


#* Download the set's zip and check it, then plan(). Sets problem on failure:
#? source: Utils.new_source().
func fetch(source: Node) -> void:
	problem = ""
	contents = {}
	if not DirAccess.dir_exists_absolute(Utils.DATABASE_FOLDER):
		problem = "Install Candy Database first: the documentation goes in its folder."
		return
	var zip_path := Utils.docs_zip_path(docs_set)
	if not tree.get("files", {}).has(zip_path):
		problem = "The %s documentation isn't on GitHub anymore." % docs_set["title"]
		return
	zip_hash = String(tree["files"][zip_path])
	var downloaded: Dictionary = await source.download_files(Utils.DOCS_GITHUB_REPOSITORY, tree["commit"], {zip_path: zip_hash})
	if downloaded.has("error"):
		problem = downloaded["error"] + " Nothing was changed."
		return
	var unpacked := _read_zip(downloaded["files"][zip_path], String(docs_set["name"]), "%s documentation" % docs_set["title"])
	if unpacked.has("error"):
		problem = unpacked["error"] + " Nothing was changed."
		return
	contents = unpacked["files"]
	left_out = unpacked["left_out"]
	plan()


#* Plan the download from the checked zip, changing nothing:
func plan() -> void:
	upstream.clear()
	to_download.clear()
	to_remove.clear()
	changed_here.clear()
	for relative in contents:
		upstream[relative] = Utils.git_blob_hash(relative, contents[relative], false)

	var recorded := recorded_files()
	for relative in upstream:
		var target := Utils.DOCS_DATABASES_FOLDER.path_join(relative)
		if not FileAccess.file_exists(target):
			to_download.append(relative)
			continue
		var bytes := FileAccess.get_file_as_bytes(target)
		if _has_hash(relative, bytes, upstream[relative]):
			continue
		to_download.append(relative)
		if not _has_hash(relative, bytes, String(recorded.get(relative, ""))):
			changed_here.append(relative)
	for relative in recorded:
		if upstream.has(relative):
			continue
		var target := Utils.DOCS_DATABASES_FOLDER.path_join(relative)
		if not FileAccess.file_exists(target):
			continue
		to_remove.append(relative)
		if not _has_hash(relative, FileAccess.get_file_as_bytes(target), String(recorded[relative])):
			changed_here.append(relative)
	to_download.sort()
	to_remove.sort()
	changed_here.sort()


#* Whether a file matches a git hash, as is or with normalized line endings (git may change them on checkout):
static func _has_hash(relative: String, bytes: PackedByteArray, git_hash: String) -> bool:
	return Utils.git_blob_hash(relative, bytes, false) == git_hash or Utils.git_blob_hash(relative, bytes) == git_hash


#* Files of the last download - path inside Databases -> git hash:
func recorded_files() -> Dictionary:
	return Utils.safe_record_files(Utils.docs_entry(docs_set).get("files"))


#* Write the zip's files, remove dropped ones and record the set. Returns an error, or "":
func apply() -> String:
	if contents.is_empty():
		return "Download the documentation first."
	plan()
	var error := _back_up()
	if error != "":
		return error
	for relative in to_download:
		error = Utils.write_file(Utils.DOCS_DATABASES_FOLDER.path_join(relative), contents[relative])
		if error != "":
			return error + " The documentation is only partly updated: download it again."
	for relative in to_remove:
		if not Utils.remove_with_generated(Utils.DOCS_DATABASES_FOLDER.path_join(relative)):
			return "Couldn't remove %s. The documentation is only partly updated: download it again." % Utils.DOCS_DATABASES_FOLDER.path_join(relative)
	Utils.remove_emptied_folders(Utils.DOCS_DATABASES_FOLDER, to_remove)

	#? The same entry Candy Wizard writes, so either can update what the other downloaded.
	var record := Utils.read_database_record()
	var docs = record.get("docs", {})
	if not docs is Dictionary:
		docs = {}
	docs[docs_set["id"]] = {
		"repository": Utils.DOCS_GITHUB_REPOSITORY,
		"folder": docs_set["folder"],
		"commit": tree["commit"],
		"zip_hash": zip_hash,
		"date": Time.get_datetime_string_from_system(false, true),
		"files": upstream,
	}
	record["docs"] = docs
	error = Utils.write_database_record(record)
	if error != "":
		return "The documentation was downloaded, but the record couldn't be written, so its next update won't remove the files it drops. " + error
	return ""


func _back_up() -> String:
	backup_folder = ""
	if changed_here.is_empty():
		return ""
	backup_folder = Utils.new_folder_path(Utils.DOCS_BACKUPS_FOLDER.path_join("%s %s" % [docs_set["id"], Time.get_datetime_string_from_system(false, true).replace(":", "-")]))
	for relative in changed_here:
		var error := Utils.copy_file(Utils.DOCS_DATABASES_FOLDER.path_join(relative), backup_folder.path_join(relative))
		if error != "":
			return "Couldn't keep a copy of the files changed here, so nothing was changed: " + error
	return ""


#==============================================================================
#  THE ZIP
#==============================================================================

#* A documentation zip's files - {"files" = {path = bytes}, "left_out" = [paths]}, or {"error"}:
#? folder_name - the database's folder, which every path starts with.
static func _read_zip(zip_bytes: PackedByteArray, folder_name: String, title: String) -> Dictionary:
	var error := Utils.write_file(TEMP_ZIP, zip_bytes)
	if error != "":
		return {"error": error}
	var reader := ZIPReader.new()
	var result := {}
	if reader.open(TEMP_ZIP) != OK:
		result = {"error": "The %s download isn't a zip file that can be read." % title}
	else:
		result = _read_open_zip(reader, folder_name, title)
		reader.close()
	DirAccess.remove_absolute(TEMP_ZIP)
	return result


static func _read_open_zip(reader: ZIPReader, folder_name: String, title: String) -> Dictionary:
	#@ Step 1 - The signature, before anything in the zip is believed:
	var manifest_name := Utils.DOCS_MANIFEST_NAME
	if not reader.file_exists(manifest_name):
		return {"error": "The %s download has no %s: it isn't a documentation zip." % [title, manifest_name]}
	var manifest_bytes := reader.read_file(manifest_name)
	var signature := ""
	if reader.file_exists(manifest_name + Signature.SIGNATURE_SUFFIX):
		signature = reader.read_file(manifest_name + Signature.SIGNATURE_SUFFIX).get_string_from_utf8()
	var signature_problem := Signature.problem(manifest_bytes, signature, title)
	if signature_problem != "":
		return {"error": signature_problem}

	#@ Step 2 - The manifest:
	var manifest = JSON.parse_string(manifest_bytes.get_string_from_utf8())
	if not manifest is Dictionary or not manifest.get("files") is Dictionary:
		return {"error": "The %s zip's manifest can't be read." % title}
	if int(manifest.get("format", 0)) > Utils.DOCS_MANIFEST_FORMAT:
		return {"error": "The %s was made for a newer version of Candy Tools. Update Candy Tools first." % title}
	if manifest.get("package") != Utils.DOCS_PACKAGE_NAME or manifest.get("database") != folder_name:
		return {"error": "The %s zip holds another database. It was refused." % title}

	#@ Step 3 - Every file, checked against the manifest:
	var files := {}
	var left_out: PackedStringArray = []
	var prefix := folder_name + "/"
	for path in manifest["files"]:
		var relative := String(path)
		if not relative.begins_with(prefix) or not Utils.is_safe_relative_path(relative):
			return {"error": "The %s zip names a file outside its folder (%s). It was refused." % [title, relative]}
		if not relative.get_extension().to_lower() in Utils.DOCS_EXTENSIONS:
			left_out.append(relative)
			continue
		if not reader.file_exists(relative):
			return {"error": "The %s zip is incomplete: %s is missing." % [title, relative]}
		var entry = manifest["files"][path]
		var bytes := reader.read_file(relative)
		if not entry is Dictionary or Utils.sha256(bytes).hex_encode() != String(entry.get("sha256", "")):
			return {"error": "The %s zip is damaged: %s doesn't match its manifest. Download it again." % [title, relative]}
		files[relative] = bytes
	if files.is_empty():
		return {"error": "The %s zip has no files to download." % title}
	left_out.sort()
	return {"files": files, "left_out": left_out}
