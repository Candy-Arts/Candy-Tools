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

const SETTINGS_DIR = "user://candy_tools"


static func _path(tool_id: String) -> String:
	return "%s/%s_settings.cfg" % [SETTINGS_DIR, tool_id]


static func load_config(tool_id: String) -> ConfigFile:
	var config := ConfigFile.new()
	config.load(_path(tool_id))
	return config


static func get_color(tool_id: String, section: String, key: String, default: Color) -> Color:
	var value = get_value(tool_id, section, key, default)
	if typeof(value) == TYPE_COLOR:
		return value 
	return default


static func get_value(tool_id: String, section: String, key: String, default: Variant) -> Variant:
	return load_config(tool_id).get_value(section, key, default)


static func set_values(tool_id: String, section: String, values: Dictionary) -> int:
	if not DirAccess.dir_exists_absolute(SETTINGS_DIR):
		var made := DirAccess.make_dir_recursive_absolute(SETTINGS_DIR)
		if made != OK:
			push_warning("Candy Tools: could not create %s (error %d)" % [SETTINGS_DIR, made])
			return made

	var config := load_config(tool_id)
	for key in values.keys():
		config.set_value(section, key, values[key])

	var result := config.save(_path(tool_id))
	if result != OK:
		push_warning("Candy Tools: could not save settings for '%s' (error %d)" % [tool_id, result])
	return result


static func clear(tool_id: String) -> int:
	var path := _path(tool_id)
	if not FileAccess.file_exists(path):
		return OK
	return DirAccess.remove_absolute(path)
