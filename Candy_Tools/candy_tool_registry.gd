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


const TOOLS_DIR = "res://addons/Candy_Tools/tools"

const DESCRIPTOR_SUFFIX = "_tool.gd"

const REQUIRED_METHODS = [
	"get_tool_name",
	"handles",
	"create_view",
	"set_target",
]



static func descriptor_paths() -> PackedStringArray:
	var out: PackedStringArray = []
	var root := DirAccess.open(TOOLS_DIR)
	if root == null:
		return out
	root.list_dir_begin()
	var entry := root.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = root.get_next()
			continue
		var path := "%s/%s" % [TOOLS_DIR, entry]
		if root.current_is_dir():
			_collect_from(path, out)
		elif entry.ends_with(DESCRIPTOR_SUFFIX):
			out.append(path)
		entry = root.get_next()
	root.list_dir_end()

	out.sort()
	return out


static func _collect_from(folder: String, out: PackedStringArray) -> void:
	var dir := DirAccess.open(folder)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.ends_with(DESCRIPTOR_SUFFIX):
			out.append("%s/%s" % [folder, entry])
		entry = dir.get_next()
	dir.list_dir_end()


static func load_tools() -> Array:
	var out: Array = []
	for path in descriptor_paths():
		var script = load(path)
		if script == null:
			push_warning("Candy Tools: %s could not be loaded. See the errors above." % path)
			continue
		var descriptor = script.new()
		var valid := true
		for method in REQUIRED_METHODS:
			if not descriptor.has_method(method):
				push_warning("Candy Tools: %s is missing %s(), skipping." % [path, method])
				valid = false
				break
		if valid:
			out.append(descriptor)
	return out


static func available_tools() -> Array:
	var out: Array = []
	for descriptor in load_tools():
		if not descriptor.has_method("is_available") or descriptor.is_available():
			out.append(descriptor)
	return out