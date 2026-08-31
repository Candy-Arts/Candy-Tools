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


const VIEW_PATH = "res://addons/Candy_Tools/tools/candy_loot/candy_loot_sampler.gd"


func get_tool_name() -> String:
	return "Loot Sampler"


func get_tool_description() -> String:
	return "Run and compare Candy Loot table tests"


func is_selectable() -> bool:
	return true


func is_available() -> bool:
	return true


func handles(_object: Object) -> bool:
	return false


func create_view(undo_redo: EditorUndoRedoManager) -> Control:
	var script = load(VIEW_PATH)
	if script == null:
		push_warning("Candy Tools: could not load %s" % VIEW_PATH)
		return null
	var view: Control = script.new()
	view.undo_redo = undo_redo
	return view


func set_target(_view: Control, _object: Object) -> void:
	pass
