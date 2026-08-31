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

var host: Control


func _enter_tree() -> void:
	host = CandyToolHost.new()
	host.name = "Candy Tools"
	host.custom_minimum_size = Vector2(0, 320)
	host.undo_redo = get_undo_redo()
	host.discover_tools()

	add_control_to_bottom_panel(host, "Candy Tools")

	var selection := get_editor_interface().get_selection()
	selection.selection_changed.connect(_on_selection_changed)
	_on_selection_changed()


func _exit_tree() -> void:
	var selection := get_editor_interface().get_selection()
	if selection.selection_changed.is_connected(_on_selection_changed):
		selection.selection_changed.disconnect(_on_selection_changed)

	if host:
		host.cleanup()
		remove_control_from_bottom_panel(host)
		host.queue_free()
		host = null


func _on_selection_changed() -> void:
	if host == null:
		return
	var nodes := get_editor_interface().get_selection().get_selected_nodes()
	host.show_for_object(nodes[0] if nodes.size() > 0 else null)
