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
extends GraphEdit

const PORT_NEXT = 0
const PORT_PREVIOUS = 1
const PORT_JUMP = 2
const PORT_COUNTDOWN = 3
const PORT_AUTO = 4

const CandyTriggersStateNodeScript = preload("res://addons/Candy_Tools/tools/candy_triggers/candy_triggers_state_node.gd")

var trigger: Node = null
var undo_redo: EditorUndoRedoManager = null
var state_nodes: Array = []
var _rebuilding: bool = false

var _node_sizes: Dictionary = {}

var _node_collapsed: Dictionary = {}

const DUPLICATE_OFFSET = Vector2(40, 40)

const AUTO_LAYOUT_SPACING = 260

const PORT_TYPE_IN = 0


func _init() -> void:
	right_disconnects = true
	set_process(false)
	visibility_changed.connect(_update_process_state)
	for out_type in [PORT_NEXT, PORT_PREVIOUS, PORT_JUMP, PORT_COUNTDOWN, PORT_AUTO]:
		add_valid_connection_type(out_type, PORT_TYPE_IN)
	connection_request.connect(_on_connection_request)
	disconnection_request.connect(_on_disconnection_request)
	popup_request.connect(_on_popup_request)
	delete_nodes_request.connect(_on_delete_nodes_request)


func set_trigger(new_trigger: Node) -> void:
	trigger = new_trigger
	rebuild()
	_update_process_state()
	_update_placeholder()


func _update_placeholder() -> void:
	if _placeholder == null:
		_placeholder = Label.new()
		_placeholder.text = "Select a CandyTrigger node to edit its states."
		_placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_placeholder.modulate = Color(1, 1, 1, 0.6)
		_placeholder.set_anchors_preset(Control.PRESET_FULL_RECT)
		_placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_placeholder)
	_placeholder.visible = trigger == null


func _update_process_state() -> void:
	set_process(trigger != null and is_visible_in_tree())
	_sync_accum = INSPECTOR_SYNC_INTERVAL


func rebuild() -> void:
	_rebuilding = true
	clear_connections()
	for child in get_children():
		if child is GraphNode:
			child.queue_free()
	state_nodes.clear()

	if trigger == null or not ("states" in trigger):
		_last_snapshot = ""
		_rebuilding = false
		return

	var states: Array = trigger.states

	for i in states.size():
		var state: CandyState = states[i]
		if state == null:
			continue
		var node := _make_state_node(i, state)
		add_child(node)
		state_nodes.append(node)

	_rebuilding = false
	_redraw_connections()
	_refresh_name_warnings()
	_last_snapshot = _states_snapshot()


func _refresh_name_warnings() -> void:
	if trigger == null:
		return
	for i in state_nodes.size():
		if i >= trigger.states.size():
			continue
		var nm: String = trigger.states[i].state_name
		state_nodes[i].set_duplicate_warning(nm != "" and _name_used_by_other(nm, i))


func _name_used_by_other(nm: String, except_index: int) -> bool:
	for i in trigger.states.size():
		if i == except_index:
			continue
		var s: CandyState = trigger.states[i]
		if s != null and s.state_name == nm:
			return true
	return false


func _on_name_typed(text: String, index: int) -> void:
	if trigger == null or index >= state_nodes.size():
		return
	state_nodes[index].set_duplicate_warning(text != "" and _name_used_by_other(text, index))


func _make_state_node(index: int, state: CandyState) -> GraphNode:
	var node: GraphNode = CandyTriggersStateNodeScript.new()
	node.setup(index, state, _node_collapsed.get(index, {}))
	node.position_offset = _position_for_state(index, state)
	node.dragged.connect(_on_node_dragged.bind(index))
	node.property_changed.connect(_on_property_changed.bind(index))
	node.target_pick_requested.connect(_on_target_pick_requested.bind(index))
	node.resize_request.connect(_on_node_resize_request.bind(index))
	node.section_toggled.connect(_on_section_toggled.bind(index))
	node.name_typed.connect(_on_name_typed.bind(index))
	node.gui_input.connect(_on_state_node_gui_input.bind(index))
	if _node_sizes.has(index):
		node.size = _node_sizes[index]
	return node


func _on_section_toggled(section: String, index: int) -> void:
	var sections: Dictionary = _node_collapsed.get(index, {}).duplicate()
	sections[section] = not sections.get(section, false)
	_node_collapsed[index] = sections
	_node_sizes.erase(index)
	rebuild.call_deferred()


func _on_node_resize_request(new_size: Vector2, index: int) -> void:
	if index < 0 or index >= state_nodes.size():
		return
	var node: GraphNode = state_nodes[index]
	var clamped := new_size.max(node.get_combined_minimum_size())
	node.size = clamped
	_node_sizes[index] = clamped


func _position_for_state(index: int, state: CandyState) -> Vector2:
	if state != null and state.graph_position_set:
		return state.graph_position
	return Vector2(index * AUTO_LAYOUT_SPACING, 0)


func _on_node_dragged(_from: Vector2, to: Vector2, index: int) -> void:
	if trigger == null or index < 0 or index >= trigger.states.size():
		return
	var state: CandyState = trigger.states[index]
	if state == null:
		return
	if state.graph_position_set and state.graph_position == to:
		return
	state.graph_position = to
	state.graph_position_set = true
	state.emit_changed()
	_mark_scene_dirty()


func _mark_scene_dirty() -> void:
	if not Engine.is_editor_hint():
		return
	if EditorInterface.has_method("mark_scene_as_unsaved"):
		EditorInterface.mark_scene_as_unsaved()


func _resolve_state_ref(ref: String) -> int:
	if ref == "":
		return -1
	if ref.is_valid_int():
		var idx = int(ref)
		if idx >= 0 and idx < trigger.states.size():
			return idx
		return -1
	for i in trigger.states.size():
		var s: CandyState = trigger.states[i]
		if s != null and s.state_name == ref:
			return i
	return -1


func _parse_jump_states(raw: String) -> Array:
	var out := []
	for piece in raw.split(","):
		var trimmed = piece.strip_edges()
		if trimmed == "":
			continue
		out.append(trimmed)
	return out


func _connect_field(from_index: int, port: int, ref: String) -> void:
	var to_index = _resolve_state_ref(ref)
	if to_index == -1:
		return
	_make_connection(from_index, port, to_index)


func _connect_by_ref(from_index: int, port: int, ref: String) -> void:
	var to_index = _resolve_state_ref(ref)
	if to_index == -1:
		return
	_make_connection(from_index, port, to_index)


func _make_connection(from_index: int, port: int, to_index: int) -> void:
	if from_index < 0 or from_index >= state_nodes.size():
		return
	if to_index < 0 or to_index >= state_nodes.size():
		return
	var from_node = state_nodes[from_index]
	var to_node = state_nodes[to_index]
	var from_port: int = from_node.field_to_port(port)
	if from_port == -1:
		return
	connect_node(from_node.name, from_port, to_node.name, 0)


func _ref_string_for_index(index: int) -> String:
	var s: CandyState = trigger.states[index]
	if s.state_name != "":
		return s.state_name
	return str(index)


func _index_from_node_name(node_name: String) -> int:
	for i in state_nodes.size():
		if state_nodes[i].name == node_name:
			return i
	return -1


const CONNECTION_PICK_DISTANCE = 8.0

const CONNECTION_CLICK_DISTANCE = 12.0

const OUTPUT_PORT_SAFE_RADIUS = 28.0

var _hovered_connection: Dictionary = {}

var _placeholder: Label = null


const CandyToolsSettings = preload("res://addons/Candy_Tools/candy_tools_settings.gd")

const SETTINGS_ID = "candy_triggers"
const SETTINGS_SECTION = "graph"

const DEFAULT_BG_COLOR = Color(0.12, 0.13, 0.15)

const DEFAULT_GRID_COLOR = Color(0.4, 0.4, 0.45, 0.5)

const GRID_MINOR_ALPHA_SCALE = 0.4

var _bg_color: Color = DEFAULT_BG_COLOR
var _bg_button: ColorPickerButton = null
var _grid_color: Color = DEFAULT_GRID_COLOR
var _grid_button: ColorPickerButton = null


func _ready() -> void:
	_bg_color = CandyToolsSettings.get_color(SETTINGS_ID, SETTINGS_SECTION, "bg_color", DEFAULT_BG_COLOR)
	_grid_color = CandyToolsSettings.get_color(SETTINGS_ID, SETTINGS_SECTION, "grid_color", DEFAULT_GRID_COLOR)

	var menu := get_menu_hbox()

	_bg_button = ColorPickerButton.new()
	_bg_button.custom_minimum_size = Vector2(44, 0)
	_bg_button.color = _bg_color
	_bg_button.tooltip_text = "Graph background colour"
	_bg_button.color_changed.connect(_on_bg_color_changed)
	_bg_button.popup_closed.connect(_save_colors)
	menu.add_child(_bg_button)

	_grid_button = ColorPickerButton.new()
	_grid_button.custom_minimum_size = Vector2(44, 0)
	_grid_button.color = _grid_color
	_grid_button.tooltip_text = "Grid line colour"
	_grid_button.color_changed.connect(_on_grid_color_changed)
	_grid_button.popup_closed.connect(_save_colors)
	menu.add_child(_grid_button)

	_apply_bg_color()
	_apply_grid_color()
	_update_process_state()


func _on_bg_color_changed(color: Color) -> void:
	_bg_color = color
	_apply_bg_color()


func _apply_bg_color() -> void:
	var panel := StyleBoxFlat.new()
	panel.bg_color = _bg_color
	add_theme_stylebox_override("panel", panel)


func _on_grid_color_changed(color: Color) -> void:
	_grid_color = color
	_apply_grid_color()


func _apply_grid_color() -> void:
	add_theme_color_override("grid_major", _grid_color)
	var minor := _grid_color
	minor.a *= GRID_MINOR_ALPHA_SCALE
	add_theme_color_override("grid_minor", minor)
	queue_redraw()


func _save_colors() -> void:
	CandyToolsSettings.set_values(SETTINGS_ID, SETTINGS_SECTION, {
		"bg_color": _bg_color,
		"grid_color": _grid_color,
	})


const INSPECTOR_SYNC_INTERVAL = 0.25

var _sync_accum: float = 0.0
var _last_snapshot: String = ""


func _states_snapshot() -> String:
	if trigger == null or not ("states" in trigger):
		return ""
	var parts: PackedStringArray = []
	for s in trigger.states:
		if s == null:
			parts.append("~")
			continue
		var targets: PackedStringArray = []
		for t in s.state_targets:
			if t == null:
				targets.append("~")
			else:
				targets.append("%s>%s>%s" % [String(t.target), str(t.wait_target), ",".join(t.effects)])
		parts.append("|".join(PackedStringArray([
			s.state_name,
			s.state_status,
			s.next_state,
			s.previous_state,
			s.jump_states,
			str(s.jump_blacklist),
			s.countdown_state,
			s.auto_state,
			str(s.cooldown),
			str(s.delay),
			str(s.countdown),
			str(s.repeat_allowed),
			";".join(targets),
		])))
	return "\n".join(parts)


func _sync_from_inspector(delta: float) -> void:
	_sync_accum += delta
	if _sync_accum < INSPECTOR_SYNC_INTERVAL:
		return
	_sync_accum = 0.0

	var snapshot := _states_snapshot()
	if snapshot == _last_snapshot:
		return

	var viewport := get_viewport()
	if viewport:
		var focused := viewport.gui_get_focus_owner()
		if focused and is_ancestor_of(focused):
			return

	rebuild()


func _process(delta: float) -> void:
	_sync_from_inspector(delta)

	var mouse := get_local_mouse_position()
	if not Rect2(Vector2.ZERO, size).has_point(mouse):
		return
	if _is_over_any_node(mouse):
		return
	var conn := get_closest_connection_at_point(mouse, CONNECTION_PICK_DISTANCE)
	if not conn.is_empty():
		_hovered_connection = conn


func _gui_input(event: InputEvent) -> void:
	if _rebuilding or trigger == null:
		return
	if not (event is InputEventMouseButton):
		return
	if not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return

	if _is_over_any_node(event.position):
		return

	if _is_near_any_output_port(event.position):
		return

	var conn := get_closest_connection_at_point(event.position, CONNECTION_CLICK_DISTANCE)
	if conn.is_empty():
		return

	_disconnect_connection(conn)
	accept_event()


func _is_over_any_node(point: Vector2) -> bool:
	for node in state_nodes:
		if node == null or not is_instance_valid(node):
			continue
		if Rect2(node.position, node.size * zoom).has_point(point):
			return true
	return false


func _is_near_any_output_port(point: Vector2) -> bool:
	var radius := OUTPUT_PORT_SAFE_RADIUS * zoom
	for node in state_nodes:
		if node == null:
			continue
		for i in node.get_output_port_count():
			var port_pos: Vector2 = node.position + node.get_output_port_position(i) * zoom
			if point.distance_to(port_pos) <= radius:
				return true
	return false


func _disconnect_connection(conn: Dictionary) -> void:
	var from_index := _index_from_node_name(str(conn["from_node"]))
	var to_index := _index_from_node_name(str(conn["to_node"]))
	if from_index == -1 or to_index == -1:
		return

	var field: int = state_nodes[from_index].port_to_field(int(conn["from_port"]))
	if field < 0:
		return

	var ref_str := _ref_string_for_index(to_index)
	_push_field_edit(from_index, field, ref_str, false)


func _on_connection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	if _rebuilding:
		return
	var from_index = _index_from_node_name(from_node)
	var to_index = _index_from_node_name(to_node)
	if from_index == -1 or to_index == -1:
		return

	var port: int = state_nodes[from_index].port_to_field(from_port)
	if port < 0:
		return

	var ref_str = _ref_string_for_index(to_index)
	_push_field_edit(from_index, port, ref_str, true)


func _on_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	if _rebuilding:
		return

	var use_from_node := from_node
	var use_from_port := from_port
	if not _hovered_connection.is_empty():
		var hov_to_node := StringName(str(_hovered_connection["to_node"]))
		var hov_to_port := int(_hovered_connection["to_port"])
		if hov_to_node == to_node and hov_to_port == to_port:
			use_from_node = StringName(str(_hovered_connection["from_node"]))
			use_from_port = int(_hovered_connection["from_port"])
	_hovered_connection = {}

	var conn := {
		"from_node": use_from_node,
		"from_port": use_from_port,
		"to_node": to_node,
		"to_port": to_port,
	}
	_disconnect_connection(conn)


func _on_property_changed(property: String, value: Variant, index: int) -> void:
	if _rebuilding or trigger == null:
		return
	if index < 0 or index >= trigger.states.size():
		return
	var state: CandyState = trigger.states[index]
	var old_value: Variant = state.get(property)
	if old_value == value:
		return

	if undo_redo:
		undo_redo.create_action("Set %s" % property)
		undo_redo.add_do_method(self, "_apply_property", index, property, value)
		undo_redo.add_undo_method(self, "_apply_property", index, property, old_value)
		undo_redo.commit_action()
	else:
		_apply_property(index, property, value)


func _apply_property(index: int, property: String, value: Variant) -> void:
	if trigger == null or index < 0 or index >= trigger.states.size():
		return
	var state: CandyState = trigger.states[index]
	state.set(property, value)
	if index < state_nodes.size():
		state_nodes[index].refresh_from_state()
	_notify_state_changed(state)

	if property == "state_name":
		_redraw_connections.call_deferred()
	elif property == "state_targets":
		rebuild.call_deferred()
	else:
		queue_redraw()


func _redraw_connections() -> void:
	if trigger == null:
		return
	_rebuilding = true
	clear_connections()
	for i in trigger.states.size():
		var state: CandyState = trigger.states[i]
		if state == null:
			continue
		_connect_field(i, PORT_NEXT, state.next_state)
		_connect_field(i, PORT_PREVIOUS, state.previous_state)
		_connect_field(i, PORT_COUNTDOWN, state.countdown_state)
		_connect_field(i, PORT_AUTO, state.auto_state)
		for jump_target in _parse_jump_states(state.jump_states):
			_connect_by_ref(i, PORT_JUMP, jump_target)
	_rebuilding = false


func _on_target_pick_requested(target_index: int, state_index: int) -> void:
	if trigger == null:
		return

	var candidates := _find_effect_targets()
	var popup := PopupMenu.new()
	add_child(popup)

	if candidates.is_empty():
		popup.add_item("No nodes with trigger_effect() found")
		popup.set_item_disabled(0, true)
	else:
		for path in candidates:
			popup.add_item(String(path))

	popup.id_pressed.connect(
		func(id):
			if id >= 0 and id < candidates.size():
				if state_index < state_nodes.size():
					state_nodes[state_index].apply_picked_target(target_index, candidates[id])
	)
	popup.popup_hide.connect(popup.queue_free)
	popup.popup(Rect2i(DisplayServer.mouse_get_position(), Vector2i(0, 0)))


func _find_effect_targets() -> Array[NodePath]:
	var out: Array[NodePath] = []
	var root := trigger.get_tree().edited_scene_root if trigger.is_inside_tree() else null
	if root == null:
		return out
	var stack: Array = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node.has_method("trigger_effect"):
			out.append(trigger.get_path_to(node))
		for child in node.get_children():
			stack.append(child)
	return out


func _on_popup_request(pos: Vector2) -> void:
	if trigger == null or not ("states" in trigger):
		return
	var graph_pos = (pos + scroll_offset) / zoom

	var popup := _make_popup()
	popup.add_item("New State", 0)
	popup.id_pressed.connect(
		func(id):
			if id == 0:
				_push_add_state(graph_pos)
	)
	_show_popup(popup)


func _on_state_node_gui_input(event: InputEvent, index: int) -> void:
	if _rebuilding or trigger == null:
		return
	if not (event is InputEventMouseButton):
		return
	if not event.pressed or event.button_index != MOUSE_BUTTON_RIGHT:
		return

	var popup := _make_popup()
	popup.add_item("Duplicate", 0)
	popup.add_item("Delete", 1)
	popup.id_pressed.connect(
		func(id):
			match id:
				0:
					_push_duplicate_state(index)
				1:
					_push_delete_states([index])
	)
	_show_popup(popup)
	get_viewport().set_input_as_handled()


func _make_popup() -> PopupMenu:
	var popup := PopupMenu.new()
	add_child(popup)
	popup.popup_hide.connect(popup.queue_free)
	return popup


func _show_popup(popup: PopupMenu) -> void:
	popup.popup(Rect2i(DisplayServer.mouse_get_position(), Vector2i(0, 0)))


func _push_duplicate_state(index: int) -> void:
	if index < 0 or index >= trigger.states.size():
		return
	var source: CandyState = trigger.states[index]
	var copy: CandyState = source.duplicate(true)
	copy.graph_position = _position_for_state(index, source) + DUPLICATE_OFFSET
	copy.graph_position_set = true
	var new_index = trigger.states.size()

	if undo_redo:
		undo_redo.create_action("Duplicate state")
		undo_redo.add_do_method(self, "_apply_insert_states", [new_index], [copy])
		undo_redo.add_undo_method(self, "_apply_remove_states", [new_index])
		undo_redo.commit_action()
	else:
		_apply_insert_states([new_index], [copy])


func _push_add_state(spawn_pos: Vector2) -> void:
	var new_index = trigger.states.size()
	if undo_redo:
		undo_redo.create_action("Add state")
		undo_redo.add_do_method(self, "_apply_add_state", spawn_pos)
		undo_redo.add_undo_method(self, "_apply_remove_states", [new_index])
		undo_redo.commit_action()
	else:
		_apply_add_state(spawn_pos)


func _apply_add_state(spawn_pos: Vector2) -> void:
	if trigger == null:
		return
	var new_states: Array[CandyState] = trigger.states.duplicate()
	var new_state := CandyState.new()
	new_state.graph_position = spawn_pos
	new_state.graph_position_set = true
	new_states.append(new_state)
	trigger.states = new_states
	trigger.notify_property_list_changed()
	rebuild()


func _on_delete_nodes_request(nodes: Array) -> void:
	if _rebuilding or trigger == null:
		return

	var indices: Array = []
	for node_name in nodes:
		var i = _index_from_node_name(node_name)
		if i != -1 and not indices.has(i):
			indices.append(i)
	_push_delete_states(indices)


func _push_delete_states(indices: Array) -> void:
	if trigger == null or indices.is_empty():
		return
	indices = indices.duplicate()
	indices.sort()

	var removed: Array = []
	for i in indices:
		if i < 0 or i >= trigger.states.size():
			return
		removed.append(trigger.states[i])

	if undo_redo:
		undo_redo.create_action("Delete state" if indices.size() == 1 else "Delete states")
		undo_redo.add_do_method(self, "_apply_remove_states", indices)
		undo_redo.add_undo_method(self, "_apply_insert_states", indices, removed)
		undo_redo.commit_action()
	else:
		_apply_remove_states(indices)


func _apply_remove_states(indices: Array) -> void:
	if trigger == null:
		return
	var new_states: Array[CandyState] = trigger.states.duplicate()
	var ordered := indices.duplicate()
	ordered.sort()
	ordered.reverse()
	for i in ordered:
		if i >= 0 and i < new_states.size():
			new_states.remove_at(i)
	trigger.states = new_states
	_shift_positions(ordered, true)
	trigger.notify_property_list_changed()
	rebuild()


func _apply_insert_states(indices: Array, removed: Array) -> void:
	if trigger == null:
		return
	var new_states: Array[CandyState] = trigger.states.duplicate()
	for n in indices.size():
		var i = indices[n]
		if i >= 0 and i <= new_states.size():
			new_states.insert(i, removed[n])
	trigger.states = new_states
	_shift_positions(indices, false)
	trigger.notify_property_list_changed()
	rebuild()


func _shift_positions(indices: Array, removing: bool) -> void:
	_node_sizes = _shift_index_keys(_node_sizes, indices, removing)
	_node_collapsed = _shift_index_keys(_node_collapsed, indices, removing)


func _shift_index_keys(source: Dictionary, indices: Array, removing: bool) -> Dictionary:
	var rebuilt: Dictionary = {}
	for old_index in source.keys():
		var offset := 0
		var dropped := false
		for i in indices:
			if removing:
				if old_index == i:
					dropped = true
					break
				elif old_index > i:
					offset -= 1
			else:
				if old_index >= i:
					offset += 1
		if dropped:
			continue
		rebuilt[old_index + offset] = source[old_index]
	return rebuilt


func _push_field_edit(from_index: int, port: int, ref_str: String, adding: bool) -> void:
	var state: CandyState = trigger.states[from_index]

	var old_value: String
	var new_value: String

	match port:
		PORT_NEXT, PORT_PREVIOUS, PORT_COUNTDOWN, PORT_AUTO:
			old_value = _get_single_field(state, port)
			new_value = ref_str if adding else ""
		PORT_JUMP:
			var jumps = _parse_jump_states(state.jump_states)
			old_value = state.jump_states
			if adding:
				if not jumps.has(ref_str):
					jumps.append(ref_str)
			else:
				jumps.erase(ref_str)
			new_value = ",".join(jumps)
		_:
			return

	if old_value == new_value:
		return

	var action_name = "%s state link" % ("Add" if adding else "Remove")
	if undo_redo:
		undo_redo.create_action(action_name)
		undo_redo.add_do_method(self, "_apply_field", from_index, port, new_value)
		undo_redo.add_undo_method(self, "_apply_field", from_index, port, old_value)
		undo_redo.commit_action()
	else:
		_apply_field(from_index, port, new_value)


func _apply_field(state_index: int, port: int, value: String) -> void:
	if trigger == null or state_index < 0 or state_index >= trigger.states.size():
		return
	var state: CandyState = trigger.states[state_index]
	match port:
		PORT_NEXT:
			state.next_state = value
		PORT_PREVIOUS:
			state.previous_state = value
		PORT_COUNTDOWN:
			state.countdown_state = value
		PORT_AUTO:
			state.auto_state = value
		PORT_JUMP:
			state.jump_states = value
	_notify_state_changed(state)
	rebuild()


func _get_single_field(state: CandyState, port: int) -> String:
	match port:
		PORT_NEXT:
			return state.next_state
		PORT_PREVIOUS:
			return state.previous_state
		PORT_COUNTDOWN:
			return state.countdown_state
		PORT_AUTO:
			return state.auto_state
	return ""


func _notify_state_changed(state: CandyState) -> void:
	state.emit_changed()
	if trigger:
		trigger.notify_property_list_changed()
	_last_snapshot = _states_snapshot()