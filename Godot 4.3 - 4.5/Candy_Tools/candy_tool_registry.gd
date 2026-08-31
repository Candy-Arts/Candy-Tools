#!###########################################################################################
#!																							#
#!         THIS SCRIPT CONTAINS CODE THAT IS THE INTELLECTUAL PROPERTY OF CANDY ARTS        #
#!																							#
#!    Such code may only be used in compliance with the appropriate Candy Arts licenses.    #
#!                 Any unauthorized use constitutes copyright infringement.                 #
#!																							#
#!   This disclaimer must be featured at the top of any script featuring Candy Arts code,   #
#!                            and may not be removed or modified.                           #
#!																							#
#!###########################################################################################


@tool
extends RefCounted

const TOOL_PATHS = [
	"res://addons/Candy_Tools/tools/candy_triggers/candy_triggers_tool.gd",
	"res://addons/Candy_Tools/tools/candy_loot/candy_loot_tool.gd",
	"res://addons/Candy_Tools/tools/candy_loot/candy_loot_sampler_tool.gd",
]

const REQUIRED_METHODS = [
	"get_tool_name",
	"handles",
	"create_view",
	"set_target",
]


static func load_tools() -> Array:
	var out: Array = []
	for path in TOOL_PATHS:
		var script = load(path)
		if script == null:
			push_warning("Candy Tools: could not load descriptor %s" % path)
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
