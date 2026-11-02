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

#? Candy Arts' news: a News.txt file per source on Candy Arts' GitHub repository, shown source after source.
#? A port of Candy Wizard's News.gd (and Candy Dialogue Creator's Core/news.gd): same file format.
#?
#? News.txt is BBCode, one item after another, each starting with a line that starts with =====. The rest of
#? that line is the item's identifier (never shown), which is how a read item is remembered. Text before
#? the first marker is ignored.
#? The news isn't signed: it's shown without the BBCode tags that load a file, and its links only open web pages.

const Utils = preload("res://addons/Candy_Tools/shared/candy_release_utils.gd")
const GitHubSource = preload("res://addons/Candy_Tools/shared/candy_github_source.gd")

enum Result { UPDATED, UNCHANGED, FAILED }

const REPOSITORY_ID := 1177938775		#/ Candy-Arts/Candy-Arts
const BRANCH := "main"
#^ Shown in this order. "id" prefixes its items' identifiers, so two files can use the same one:
const SOURCES := [
	{"id": "candy_tools", "title": "Candy Tools news", "path": "NEWS/Candy Tools/News.txt"},
	{"id": "candy_arts", "title": "Candy Arts news", "path": "NEWS/Candy Arts/News.txt"},
]
const ITEM_MARKER := "====="
const DEFAULT_AUTO := true
const MAX_BYTES := 256 * 1024
const CHECK_INTERVAL := 24 * 60 * 60

#^ Per machine, so news read in one project is read in all - {"auto", "time", "copies", "read"}:
const SETTING := "candy_tools/news"

#^ Tests only - a local stand-in for GitHub's API:
static var test_api_base := ""
static var busy := false
#^ Why the last look failed (one line per source), or "":
static var problem := ""
#^ Automatic look done this session:
static var _looked := false

static var _font_regex: RegEx = null
static var _dropcap_font_regex: RegEx = null
static var _image_regex: RegEx = null


#==============================================================================
#  WHAT'S KEPT
#==============================================================================

static func state() -> Dictionary:
	return Utils.editor_setting(SETTING)


static func _keep(values: Dictionary) -> void:
	var kept := state().duplicate()
	kept.merge(values, true)
	Utils.set_editor_setting(SETTING, kept)


#* Whether the news is looked for when the editor opens:
static func auto() -> bool:
	return bool(state().get("auto", DEFAULT_AUTO))


static func set_auto(value: bool) -> void:
	_keep({"auto": value})


static func last_look() -> float:
	return float(state().get("time", 0.0))


static func copy(source_id: String) -> Dictionary:
	var copies = state().get("copies", {})
	if copies is Dictionary and copies.get(source_id) is Dictionary:
		return copies[source_id]
	return {}


static func _keep_copy(source_id: String, text: String, etag: String) -> void:
	var copies = state().get("copies", {})
	copies = copies.duplicate() if copies is Dictionary else {}
	copies[source_id] = {"text": text, "etag": etag}
	_keep({"copies": copies})


#==============================================================================
#  ITEMS
#==============================================================================

#* Every source's items, source after source, safe to show - [{id, text}]:
static func items() -> Array:
	var result: Array = []
	for source in SOURCES:
		result.append_array(source_items(str(source["id"])))
	return result


static func source_items(source_id: String) -> Array:
	var result: Array = []
	var item_id := ""
	var item_lines: PackedStringArray = []
	var in_item := false
	for line in str(copy(source_id).get("text", "")).replace("\r\n", "\n").split("\n"):
		var stripped := line.strip_edges()
		if stripped.begins_with(ITEM_MARKER):
			if in_item:
				_add_item(result, source_id, item_id, item_lines)
			item_id = stripped.trim_prefix(ITEM_MARKER).strip_edges()
			item_lines.clear()
			in_item = true
		elif in_item:
			item_lines.append(line)
	if in_item:
		_add_item(result, source_id, item_id, item_lines)
	return result


static func _add_item(result: Array, source_id: String, item_id: String, lines: PackedStringArray) -> void:
	var item := without_resources("\n".join(lines)).strip_edges()
	if item == "":
		return
	#% No identifier: its text stands in, so editing it makes it unread again.
	if item_id == "":
		item_id = "text:" + item.sha256_text()
	result.append({"id": source_id + "/" + item_id, "text": item})


static func read_ids() -> PackedStringArray:
	return PackedStringArray(state().get("read", []))


#* Remember an item as read. Returns whether it was unread:
static func mark_read(item_id: String) -> bool:
	var ids := read_ids()
	if ids.has(item_id):
		return false
	ids.append(item_id)
	_keep({"read": ids})
	return true


static func has_unread() -> bool:
	var ids := read_ids()
	for item in items():
		if not ids.has(item["id"]):
			return true
	return false


#* Forget the read items a source's copy no longer has (only that source's):
static func _forget_deleted(source_id: String) -> void:
	var present: Array = source_items(source_id).map(func(item: Dictionary) -> String: return item["id"])
	var ids := read_ids()
	var kept: PackedStringArray = []
	for item_id in ids:
		if not item_id.begins_with(source_id + "/") or present.has(item_id):
			kept.append(item_id)
	if kept.size() != ids.size():
		_keep({"read": kept})


#* Strip the tags that load a file ([img], [font], a [dropcap]'s font): a resource can carry a script.
static func without_resources(bbcode: String) -> String:
	if _font_regex == null:
		_font_regex = RegEx.create_from_string("\\[font[= ][^\\]]*\\]")
		_dropcap_font_regex = RegEx.create_from_string("(\\[dropcap[^\\]]*?)\\s+font=[^\\s\\]]*")
		_image_regex = RegEx.create_from_string("\\[img[^\\]]*\\][^\\[]*\\[/img\\]")
	var out := _image_regex.sub(bbcode, "", true)
	out = out.replace("[img", "[lb]img")	#/ An [img] with no clear end is shown as text
	out = _font_regex.sub(out, "", true)
	out = out.replace("[/font]", "")
	out = _dropcap_font_regex.sub(out, "$1", true)
	return out


#==============================================================================
#  LOOKING ON GITHUB
#==============================================================================

#* Download every source, keeping the changed copies. Returns a Result, or -1 when GitHub wasn't asked:
#? forced: now; else only with Auto on, at most once a day and once per session.
#? UPDATED if any source changed; FAILED if none did and one failed (the reasons go in problem).
static func refresh(parent: Node, forced: bool) -> int:
	if busy:
		return -1
	if not forced:
		if _looked or not auto() or Time.get_unix_time_from_system() - last_look() < CHECK_INTERVAL:
			return -1
		_looked = true
	busy = true
	problem = ""
	var github := GitHubSource.new()
	if test_api_base != "":
		github.api_base = test_api_base
	parent.add_child(github)
	var updated := false
	var failures: PackedStringArray = []
	for source in SOURCES:
		var source_id := str(source["id"])
		var kept := copy(source_id)
		var etag := str(kept.get("etag", "")) if str(kept.get("text", "")) != "" else ""
		var answer: Dictionary = await github.fetch_file(REPOSITORY_ID, BRANCH, str(source["path"]), etag, MAX_BYTES)
		if answer.has("error"):
			failures.append("%s couldn't be downloaded. %s" % [source["title"], answer["error"]])
			continue
		if answer.has("unchanged"):
			continue
		var new_text := (answer["bytes"] as PackedByteArray).get_string_from_utf8()
		var changed := new_text != str(kept.get("text", ""))
		_keep_copy(source_id, new_text, str(answer.get("etag", "")))
		if changed:
			updated = true
			_forget_deleted(source_id)
	github.queue_free()
	busy = false
	problem = "\n".join(failures)
	if failures.size() < SOURCES.size():
		_keep({"time": Time.get_unix_time_from_system()})
	if updated:
		return Result.UPDATED
	if not failures.is_empty():
		return Result.FAILED
	return Result.UNCHANGED
