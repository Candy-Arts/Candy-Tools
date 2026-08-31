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
extends VBoxContainer

const CandyToolRegistry = preload("res://addons/Candy_Tools/candy_tool_registry.gd")

var undo_redo: EditorUndoRedoManager = null

var _tools: Array = []
var _selectable: Array = [] 
var _views: Dictionary = {}
var _current_tool = null
var _auto_tool = null

var _dropdown: OptionButton
var _auto_label: Label
var _content: PanelContainer
var _empty_state: Label


func _init() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_chrome()


func _build_chrome() -> void:
	var header := HBoxContainer.new()

	var caption := Label.new()
	caption.text = "Tool"
	header.add_child(caption)

	_dropdown = OptionButton.new()
	_dropdown.custom_minimum_size = Vector2(180, 0)
	_dropdown.tooltip_text = "Choose a tool. Some tools appear on their own when you select a matching node."
	_dropdown.item_selected.connect(_on_dropdown_selected)
	header.add_child(_dropdown)

	_auto_label = Label.new()
	_auto_label.modulate = Color(1, 1, 1, 0.7)
	_auto_label.visible = false
	header.add_child(_auto_label)

	add_child(header)

	_content = PanelContainer.new()
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_content)

	_empty_state = Label.new()
	_empty_state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_state.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty_state.modulate = Color(1, 1, 1, 0.6)
	_empty_state.size_flags_vertical = Control.SIZE_EXPAND_FILL


func discover_tools() -> void:
	_tools = CandyToolRegistry.available_tools()

	_selectable.clear()
	for descriptor in _tools:
		if not descriptor.has_method("is_selectable") or descriptor.is_selectable():
			_selectable.append(descriptor)
	_selectable.sort_custom(func(a, b): return a.get_tool_name() < b.get_tool_name())

	_dropdown.clear()
	_dropdown.add_item("None", 0)
	for i in _selectable.size():
		_dropdown.add_item(_selectable[i].get_tool_name(), i + 1)
	_dropdown.select(0)

	_show_empty("Select a node to edit it, or choose a tool above.")


func show_for_object(object: Object) -> void:
	var auto = _find_auto_tool(object)

	if auto != null:
		_auto_tool = auto
		_open_tool(auto, object)
		_auto_label.text = "▶ %s (from selection)" % auto.get_tool_name()
		_auto_label.visible = true
		_dropdown.disabled = true
		return

	_auto_tool = null
	_auto_label.visible = false
	_dropdown.disabled = false
	_apply_dropdown_selection()


func _find_auto_tool(object: Object):
	if object == null:
		return null
	for descriptor in _tools:
		if descriptor.handles(object):
			return descriptor
	return null


func _on_dropdown_selected(_index: int) -> void:
	_apply_dropdown_selection()


func _apply_dropdown_selection() -> void:
	var index := _dropdown.get_selected_id()
	if index <= 0 or index > _selectable.size():
		_current_tool = null
		_show_empty("Select a node to edit it, or choose a tool above.")
		return
	_open_tool(_selectable[index - 1], null)


func _open_tool(descriptor, object: Object) -> void:
	var view: Control = _views.get(descriptor)
	if view == null:
		view = descriptor.create_view(undo_redo)
		if view == null:
			_show_empty("%s could not be opened." % descriptor.get_tool_name())
			return
		view.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_views[descriptor] = view

	_swap_content(view)
	_current_tool = descriptor
	descriptor.set_target(view, object)


func _show_empty(message: String) -> void:
	_empty_state.text = message
	_swap_content(_empty_state)
	_current_tool = null


func _swap_content(control: Control) -> void:
	for child in _content.get_children():
		_content.remove_child(child)
	_content.add_child(control)


func cleanup() -> void:
	_swap_content(_empty_state)
	for view in _views.values():
		if is_instance_valid(view):
			view.queue_free()
	_views.clear()
	_tools.clear()
	_selectable.clear()
