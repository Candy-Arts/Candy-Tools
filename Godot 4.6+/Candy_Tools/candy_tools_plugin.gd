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
extends EditorPlugin

const CandyToolHost = preload("res://addons/Candy_Tools/candy_tool_host.gd")

var dock: EditorDock
var host: Control


func _enter_tree() -> void:
	host = CandyToolHost.new()
	host.name = "Candy Tools"
	host.custom_minimum_size = Vector2(0, 320)
	host.undo_redo = get_undo_redo()
	host.discover_tools()

	dock = EditorDock.new()
	dock.title = "Candy Tools"
	dock.default_slot = EditorDock.DOCK_SLOT_BOTTOM
	dock.available_layouts = EditorDock.DOCK_LAYOUT_HORIZONTAL | EditorDock.DOCK_LAYOUT_FLOATING
	dock.add_child(host)
	add_dock(dock)

	var selection := get_editor_interface().get_selection()
	selection.selection_changed.connect(_on_selection_changed)
	_on_selection_changed()


func _exit_tree() -> void:
	var selection := get_editor_interface().get_selection()
	if selection.selection_changed.is_connected(_on_selection_changed):
		selection.selection_changed.disconnect(_on_selection_changed)

	if dock:
		if host:
			host.cleanup()
		remove_dock(dock)
		dock.queue_free()
		dock = null
		host = null


func _on_selection_changed() -> void:
	if host == null:
		return
	var nodes := get_editor_interface().get_selection().get_selected_nodes()
	host.show_for_object(nodes[0] if nodes.size() > 0 else null)
