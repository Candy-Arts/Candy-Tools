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

const GRAPH_EDIT_PATH = "res://addons/Candy_Tools/tools/candy_triggers/candy_triggers_graph_edit.gd"

const REQUIRED_CLASS = "CandyTrigger"


func get_tool_name() -> String:
	return "Candy Triggers"


func get_tool_description() -> String:
	return "State machine graph"


func is_selectable() -> bool:
	return false


func is_available() -> bool:
	for entry in ProjectSettings.get_global_class_list():
		if entry.get("class", "") == REQUIRED_CLASS:
			return true
	return false


func handles(object: Object) -> bool:
	if object == null or not (object is Node):
		return false
	return object.has_method("switch_state") and "states" in object


func create_view(undo_redo: EditorUndoRedoManager) -> Control:
	if not is_available():
		return null
	var script = load(GRAPH_EDIT_PATH)
	if script == null:
		push_warning("Candy Tools: could not load %s" % GRAPH_EDIT_PATH)
		return null
	var graph: Control = script.new()
	graph.undo_redo = undo_redo
	return graph


func set_target(view: Control, object: Object) -> void:
	view.set_trigger(object as Node)
