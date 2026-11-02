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


const VIEW_PATH = "res://addons/Candy_Tools/tools/candy_tools/candy_tools_view.gd"
const Updates = preload("candy_tools_updates.gd")
const News = preload("candy_news.gd")


func get_tool_name() -> String:
	return "Candy Tools"


func get_tool_description() -> String:
	return "Update Candy Tools, and read Candy Arts' news"


func is_selectable() -> bool:
	return true


func is_available() -> bool:
	return true


#* The tool the panel shows when the editor opens:
func is_default() -> bool:
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
	var lines: PackedStringArray = []
	var newer := Updates.newer_version()
	if newer != "":
		lines.append("Candy Tools %s is out." % newer)
	if News.has_unread():
		lines.append("There's news you haven't read.")
	return "\n".join(lines)


#* The editor's startup look, at most once a day: a newer Candy Tools, and the news (with Auto on).
func startup_check(host: Node) -> void:
	await Updates.look_on_github(host, false)
	await News.refresh(host, false)
