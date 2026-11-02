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


const VIEW_PATH = "res://addons/Candy_Tools/tools/candy_database/candy_database_view.gd"
const Utils = preload("candy_database_utils.gd")


func get_tool_name() -> String:
	return "Candy Database"


func get_tool_description() -> String:
	return "Install and update Candy Database, and download documentation for it from GitHub"


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


#* What needs the developer's attention, for the drop-down's warning icon, or "":
func get_attention() -> String:
	var waiting := Utils.updates_waiting()
	if waiting.is_empty():
		return ""
	return "Newer on GitHub: %s." % ", ".join(waiting)


#* The editor's startup look, at most once a day: only for what's here and can be updated.
func startup_check(host: Node) -> void:
	await Utils.look_on_github(host, false, false)
