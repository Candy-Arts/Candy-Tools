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
extends VBoxContainer

const CandyToolRegistry = preload("res://addons/Candy_Tools/candy_tool_registry.gd")

#^ Seconds after the editor opens before the tools' startup checks (startup_check()) run:
const STARTUP_CHECK_DELAY := 5.0

var undo_redo: EditorUndoRedoManager = null

var _tools: Array = []
var _selectable: Array = []
var _views: Dictionary = {}

var _dropdown: OptionButton
var _auto_label: Label
var _content: PanelContainer
var _empty_state: Label
var _startup_checked := false


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
	for i in _selectable.size():
		_dropdown.add_item(_selectable[i].get_tool_name(), i)
	refresh_attention()

	#? The tool shown first: the one whose is_default() is true (Candy Tools), else the first listed.
	if _selectable.is_empty():
		_show_empty("No tools are installed.")
	else:
		var default_index := 0
		for i in _selectable.size():
			if _selectable[i].has_method("is_default") and _selectable[i].is_default():
				default_index = i
				break
		_dropdown.select(default_index)
		_apply_dropdown_selection()
	_run_startup_checks.call_deferred()


#* Show a warning icon on the entries of tools that need attention (an update, unread news...).
#? A tool reports it with get_attention() -> String ("" for nothing), shown in the entry's tooltip.
func refresh_attention() -> void:
	var warning: Texture2D = null
	var editor_theme := EditorInterface.get_editor_theme()
	if editor_theme != null and editor_theme.has_icon("StatusWarning", "EditorIcons"):
		warning = editor_theme.get_icon("StatusWarning", "EditorIcons")
	for i in _selectable.size():
		var descriptor = _selectable[i]
		var attention := ""
		if descriptor.has_method("get_attention"):
			attention = str(descriptor.get_attention())
		var tooltip := ""
		if descriptor.has_method("get_tool_description"):
			tooltip = descriptor.get_tool_description()
		if attention != "":
			tooltip = (tooltip + "\n\n" + attention).strip_edges()
		_dropdown.set_item_icon(i, warning if attention != "" else null)
		_dropdown.set_item_tooltip(i, tooltip)


#* Once per editor session, a few seconds after it opens: each tool's startup_check(host), if it has one.
#? Tools use it to look on GitHub (at most once a day).
func _run_startup_checks() -> void:
	if _startup_checked:
		return
	_startup_checked = true
	if not is_inside_tree():
		await tree_entered
	await get_tree().create_timer(STARTUP_CHECK_DELAY).timeout
	for descriptor in _tools.duplicate():
		if not is_inside_tree():
			return
		if descriptor.has_method("startup_check"):
			await descriptor.startup_check(self)
	refresh_attention()


func show_for_object(object: Object) -> void:
	var auto = _find_auto_tool(object)

	if auto != null:
		_open_tool(auto, object)
		_auto_label.text = "▶ %s (from selection)" % auto.get_tool_name()
		_auto_label.visible = true
		_dropdown.disabled = true
		return

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
	if index < 0 or index >= _selectable.size():
		_show_empty("No tools are installed.")
		return
	_open_tool(_selectable[index], null)


func _open_tool(descriptor, object: Object) -> void:
	var view: Control = _views.get(descriptor)
	if view == null:
		view = descriptor.create_view(undo_redo)
		if view == null:
			_show_empty("%s could not be opened." % descriptor.get_tool_name())
			return
		view.size_flags_vertical = Control.SIZE_EXPAND_FILL
		if view.has_signal("attention_changed"):
			view.connect("attention_changed", refresh_attention)
		_views[descriptor] = view

	_swap_content(view)
	descriptor.set_target(view, object)


func _show_empty(message: String) -> void:
	_empty_state.text = message
	_swap_content(_empty_state)


func _swap_content(control: Control) -> void:
	#% Already showing: re-adding it would make it leave and re-enter the tree,
	#% dropping focus and any edit in progress.
	if control.get_parent() == _content and _content.get_child_count() == 1:
		return
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
