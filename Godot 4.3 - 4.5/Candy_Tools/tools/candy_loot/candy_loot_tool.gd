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


const EDITOR_PATH = "res://addons/Candy_Tools/tools/candy_loot/candy_loot_editor.gd"

func get_tool_name() -> String:
	return "Loot Table Editor"


func get_tool_description() -> String:
	return "Edit Candy Loot pack tables"


func is_selectable() -> bool:
	return true


func is_available() -> bool:
	return true


func handles(_object: Object) -> bool:
	return false


func create_view(undo_redo: EditorUndoRedoManager) -> Control:
	var script = load(EDITOR_PATH)
	if script == null:
		push_warning("Candy Tools: could not load %s" % EDITOR_PATH)
		return null
	var view: Control = script.new()
	view.undo_redo = undo_redo
	return view


func set_target(_view: Control, _object: Object) -> void:
	pass
