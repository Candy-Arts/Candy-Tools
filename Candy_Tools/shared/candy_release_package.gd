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

#? A release zip of a plugin: addons/<folder>/... plus <manifest_name> and its signature.
#? A port of Candy Wizard's Package.gd. Nothing in the zip is believed before its manifest's signature is checked.

const Utils = preload("candy_release_utils.gd")
const Signature = preload("candy_release_signature.gd")

#^ The newest manifest format Candy Tools reads:
const MANIFEST_FORMAT := 1

#^ What kind of release it is, set before open():
var package_name := ""		#/ The manifest's "package" ("Candy_Database")
var manifest_name := ""		#/ "candy_database_manifest.json"
var root := ""				#/ Every file's path starts with it ("addons/Candy_Database/")
var title := ""				#/ For messages ("Candy Database")

var manifest: Dictionary = {}
var reader: ZIPReader = null
var zip_entries: Dictionary = {}


func _init(package: String = "", manifest_file: String = "", folder: String = "", shown_title: String = "") -> void:
	package_name = package
	manifest_name = manifest_file
	root = folder.trim_prefix("res://").trim_suffix("/") + "/"
	title = shown_title


#* Opens a release zip and reads its manifest, once its signature is checked. Returns an error, or "":
func open(path: String) -> String:
	close()
	reader = ZIPReader.new()
	var error := reader.open(path)
	if error != OK:
		reader = null
		return "Couldn't open '%s' as a zip file (%s)." % [path.get_file(), error_string(error)]
	for entry in reader.get_files():
		zip_entries[entry] = true
	if not zip_entries.has(manifest_name):
		return "'%s' isn't a %s release: it has no %s file." % [path.get_file(), title, manifest_name]
	var manifest_bytes := reader.read_file(manifest_name)
	var signature := ""
	if zip_entries.has(manifest_name + Signature.SIGNATURE_SUFFIX):
		signature = reader.read_file(manifest_name + Signature.SIGNATURE_SUFFIX).get_string_from_utf8()
	var signature_problem := Signature.problem(manifest_bytes, signature, "%s release" % title)
	if signature_problem != "":
		return signature_problem
	var parsed = JSON.parse_string(manifest_bytes.get_string_from_utf8())
	if not parsed is Dictionary:
		return "The release's manifest (%s) can't be read." % manifest_name
	manifest = parsed
	return _check_manifest()


func close() -> void:
	if reader != null:
		reader.close()
	reader = null
	manifest = {}
	zip_entries = {}


func version() -> String:
	return String(manifest.get("version", ""))


func files() -> Dictionary:
	return manifest.get("files", {})


func read(path: String) -> PackedByteArray:
	return reader.read_file(path)


#* The release's files - path inside the plugin's folder -> path in the zip:
func relative_files() -> Dictionary:
	var found := {}
	for path in files():
		found[String(path).trim_prefix(root)] = String(path)
	return found


func _check_manifest() -> String:
	if int(manifest.get("format", 0)) > MANIFEST_FORMAT:
		return "This %s release was made for a newer version of Candy Tools. Update Candy Tools first." % title
	if manifest.get("package", "") != package_name:
		return "This zip isn't a %s release." % title
	if not Utils.is_plain_version(version()):
		return "The release's manifest gives a version that can't be read (%s). It was refused." % version()
	var file_list = manifest.get("files")
	if not file_list is Dictionary or file_list.is_empty():
		return "The release's manifest lists no files."
	for path in file_list:
		if not String(path).begins_with(root) or not Utils.is_safe_relative_path(String(path)):
			return "The release's manifest names a file outside %s's folder (%s). It was refused." % [title, path]
	#? plugin.cfg gives the version Godot shows: it must agree.
	var config_path := root + "plugin.cfg"
	if not file_list.has(config_path) or not zip_entries.has(config_path):
		return "The release has no plugin.cfg."
	var config := ConfigFile.new()
	if config.parse(reader.read_file(config_path).get_string_from_utf8()) != OK or str(config.get_value("plugin", "version", "")) != version():
		return "The release's plugin.cfg doesn't give version %s, as its manifest does." % version()
	var godot_min := String(manifest.get("godot_min", ""))
	if godot_min != "" and Utils.compare_versions(Utils.godot_version(), godot_min) < 0:
		return "%s %s needs Godot %s or newer (this editor is %s)." % [title, version(), godot_min, Utils.godot_version()]
	return ""


#* Checks every file the manifest lists is in the zip, undamaged:
func verify() -> String:
	var file_list := files()
	for path in file_list:
		if not zip_entries.has(path):
			return "The release is incomplete: %s is missing." % path
		var entry = file_list[path]
		if not entry is Dictionary or Utils.content_hash(path, reader.read_file(path)) != String(entry.get("sha256", "")):
			return "The release is damaged: %s doesn't match its manifest. Download it again." % path
	return ""
