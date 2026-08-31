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

const CandyLootPackNode = preload("res://addons/Candy_Tools/tools/candy_loot/candy_loot_pack_node.gd")
const CandyLootTemplates = preload("res://addons/Candy_Tools/tools/candy_loot/candy_loot_templates.gd")

signal model_changed()

var undo_redo: EditorUndoRedoManager = null

var model: Array = []
var prefix: String = "§"

var highlight_levels: int = 3
var pack_nodes: Array = []

var _rebuilding: bool = false
var _placeholder: Label = null
var _has_table: bool = false


func _init() -> void:
	right_disconnects = false
	popup_request.connect(_on_popup_request)
	node_selected.connect(_on_node_selected)
	node_deselected.connect(_on_node_deselected)
	delete_nodes_request.connect(_on_delete_nodes_request)


func set_model(new_model: Array, new_prefix: String, has_table: bool) -> void:
	model = new_model
	prefix = new_prefix
	_has_table = has_table
	rebuild()


func set_prefix(new_prefix: String) -> void:
	prefix = new_prefix
	rebuild()


const CandyToolsSettings = preload("res://addons/Candy_Tools/candy_tools_settings.gd")

const SETTINGS_ID = "candy_loot"
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


func rebuild() -> void:
	_rebuilding = true
	for child in get_children():
		if child is GraphNode:
			child.queue_free()
	pack_nodes.clear()

	for i in model.size():
		var pack: Dictionary = model[i]
		var node: GraphNode = CandyLootPackNode.new()
		node.setup(i, pack, prefix + String(pack.get("name", "")), bool(pack.get("collapsed", false)))
		node.position_offset = pack.get("pos", Vector2(i % 4 * 300, floor(i / 4.0) * 340))
		node.dragged.connect(_on_node_dragged.bind(i))
		node.pack_field_changed.connect(_on_pack_field_changed.bind(i))
		node.drop_field_changed.connect(_on_drop_field_changed.bind(i))
		node.drop_added.connect(_on_drop_added.bind(i))
		node.drop_removed.connect(_on_drop_removed.bind(i))
		node.drop_pick_requested.connect(_on_drop_pick_requested.bind(i))
		node.pack_drag_dropped.connect(_on_pack_drag_dropped.bind(i))
		node.drops_collapsed_toggled.connect(_on_drops_collapsed_toggled.bind(i))
		node.drop_collapsed_toggled.connect(_on_drop_collapsed_toggled.bind(i))
		node.drop_moved.connect(_on_drop_moved.bind(i))
		node.gui_input.connect(_on_node_gui_input.bind(i))
		add_child(node)
		pack_nodes.append(node)

	_rebuilding = false
	_refresh_warnings()
	_clear_tints()
	_update_placeholder()


func _update_placeholder() -> void:
	if _placeholder == null:
		_placeholder = Label.new()
		_placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_placeholder.modulate = Color(1, 1, 1, 0.6)
		_placeholder.set_anchors_preset(Control.PRESET_FULL_RECT)
		_placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_placeholder)
	_placeholder.text = "Right-click to add a Pack." if _has_table \
		else "Create or open a loot table to begin."
	_placeholder.visible = not _has_table or model.is_empty()


func _on_node_dragged(_from: Vector2, to: Vector2, index: int) -> void:
	if index < model.size():
		model[index]["pos"] = to
		model_changed.emit()


func _apply_snapshot(data: Array) -> void:
	model = data.duplicate(true)
	rebuild()
	model_changed.emit()


func _push_edit(action_name: String, mutator: Callable) -> void:
	if not _has_table:
		return
	var before := model.duplicate(true)
	mutator.call()
	var after := model.duplicate(true)
	if before == after:
		return

	if undo_redo:
		model = before
		undo_redo.create_action(action_name)
		undo_redo.add_do_method(self, "_apply_snapshot", after)
		undo_redo.add_undo_method(self, "_apply_snapshot", before)
		undo_redo.commit_action()
	else:
		rebuild()
		model_changed.emit()


func _on_pack_field_changed(field: String, value, index: int) -> void:
	if _rebuilding or index >= model.size():
		return
	if _same_value(model[index].get(field, null), value):
		return
	_push_edit("Set pack %s" % field, func(): model[index][field] = value)


func _on_drop_field_changed(drop_index: int, field: String, value, index: int) -> void:
	if _rebuilding or index >= model.size():
		return
	var drops: Array = model[index].get("drops", [])
	if drop_index >= drops.size():
		return
	if _same_value(drops[drop_index].get(field, null), value):
		return
	_push_edit("Set drop %s" % field, func(): model[index]["drops"][drop_index][field] = value)


static func _same_value(a, b) -> bool:
	return typeof(a) == typeof(b) and a == b


func _on_drop_moved(from_index: int, to_index: int, index: int) -> void:
	if _rebuilding or index >= model.size():
		return
	var drops: Array = model[index].get("drops", [])
	if from_index < 0 or from_index >= drops.size():
		return
	var target := to_index
	if target < 0 or target >= drops.size():
		target = drops.size() - 1
	if target == from_index:
		return
	_push_edit("Reorder drop", func():
		var moved = model[index]["drops"][from_index]
		model[index]["drops"].remove_at(from_index)
		model[index]["drops"].insert(target, moved)
	)


func _new_drop(key: String = "") -> Dictionary:
	return {
		"key": key, "chance": "", "amount": "",
		"max": "", "maxdiscard": false, "discardx": "",
		"collapsed": false,
	}


func _on_drop_added(index: int) -> void:
	if index >= model.size():
		return
	_push_edit("Add drop", func(): model[index]["drops"].append(_new_drop()))


func _on_drop_removed(drop_index: int, index: int) -> void:
	if index >= model.size():
		return
	_push_edit("Remove drop", func():
		var drops: Array = model[index]["drops"]
		if drop_index >= 0 and drop_index < drops.size():
			drops.remove_at(drop_index)
	)


func _on_pack_drag_dropped(source_key: String, drop_index: int, index: int) -> void:
	if index >= model.size() or source_key == "":
		return
	if drop_index < 0:
		_push_edit("Add pack as drop", func(): model[index]["drops"].append(_new_drop(source_key)))
		return
	var drops: Array = model[index].get("drops", [])
	if drop_index >= drops.size():
		return
	_push_edit("Set drop key", func(): model[index]["drops"][drop_index]["key"] = source_key)


func _on_drops_collapsed_toggled(index: int) -> void:
	if index >= model.size():
		return
	model[index]["collapsed"] = not bool(model[index].get("collapsed", false))
	rebuild.call_deferred()


func _on_drop_collapsed_toggled(drop_index: int, index: int) -> void:
	if index >= model.size():
		return
	var drops: Array = model[index].get("drops", [])
	if drop_index < 0 or drop_index >= drops.size():
		return
	drops[drop_index]["collapsed"] = not bool(drops[drop_index].get("collapsed", false))
	model_changed.emit()
	rebuild.call_deferred()


func _on_drop_pick_requested(drop_index: int, index: int) -> void:
	var keys: Array = []
	for i in model.size():
		if i == index:
			continue
		var pack_name: String = model[i].get("name", "")
		if pack_name != "":
			keys.append(prefix + pack_name)

	var popup := PopupMenu.new()
	add_child(popup)
	if keys.is_empty():
		popup.add_item("No other packs in this table")
		popup.set_item_disabled(0, true)
	else:
		for key in keys:
			popup.add_item(key)
	popup.id_pressed.connect(func(id):
		if id >= 0 and id < keys.size():
			_on_drop_field_changed(drop_index, "key", keys[id], index)
	)
	popup.popup_hide.connect(popup.queue_free)
	popup.popup(Rect2i(DisplayServer.mouse_get_position(), Vector2i(0, 0)))


func _on_popup_request(pos: Vector2) -> void:
	if not _has_table:
		return
	var graph_pos = (pos + scroll_offset) / zoom
	var popup := PopupMenu.new()
	add_child(popup)
	popup.add_item("New Pack", 0)

	var templates := CandyLootTemplates.names()
	var submenu := PopupMenu.new()
	submenu.name = "TemplatesMenu"
	if templates.is_empty():
		submenu.add_item("No templates saved yet")
		submenu.set_item_disabled(0, true)
	else:
		for i in templates.size():
			submenu.add_item(templates[i], i)
	submenu.id_pressed.connect(func(id):
		if id >= 0 and id < templates.size():
			_add_from_template(templates[id], graph_pos)
	)
	popup.add_child(submenu)
	popup.add_submenu_item("Templates", "TemplatesMenu")

	popup.id_pressed.connect(func(id):
		if id == 0:
			_add_pack(graph_pos)
	)
	popup.popup_hide.connect(popup.queue_free)
	popup.popup(Rect2i(DisplayServer.mouse_get_position(), Vector2i(0, 0)))


func _add_from_template(template_name: String, spawn_pos: Vector2) -> void:
	var pack := CandyLootTemplates.instantiate(template_name, spawn_pos)
	if pack.is_empty():
		push_warning("Candy Tools: template not found: %s" % template_name)
		return
	_push_edit("Add pack from template", func():
		if _name_used_by_other(String(pack.get("name", "")), -1):
			pack["name"] = _unique_name(String(pack.get("name", "Pack")))
		model.append(pack)
	)


func _add_pack(spawn_pos: Vector2) -> void:
	_push_edit("Add pack", func():
		model.append({
			"name": _unique_name("Pack"),
			"number": "-1",
			"discard": false,
			"drops": [],
			"pos": spawn_pos,
			"collapsed": false,
		})
	)


func _unique_name(base: String) -> String:
	var n := 1
	while true:
		var candidate := "%s_%d" % [base, n]
		var taken := false
		for pack in model:
			if pack.get("name", "") == candidate:
				taken = true
				break
		if not taken:
			return candidate
		n += 1
	return base


func _on_node_gui_input(event: InputEvent, index: int) -> void:
	if _rebuilding or not _has_table:
		return
	if not (event is InputEventMouseButton):
		return
	if not event.pressed or event.button_index != MOUSE_BUTTON_RIGHT:
		return

	var popup := PopupMenu.new()
	add_child(popup)
	popup.add_item("Duplicate", 0)
	popup.add_item("Save Template", 1)
	popup.add_separator()
	popup.add_item("Delete", 2)
	popup.id_pressed.connect(func(id):
		match id:
			0:
				_duplicate_pack(index)
			1:
				_save_template(index)
			2:
				_delete_packs([index])
	)
	popup.popup_hide.connect(popup.queue_free)
	popup.popup(Rect2i(DisplayServer.mouse_get_position(), Vector2i(0, 0)))
	get_viewport().set_input_as_handled()


func _duplicate_pack(index: int) -> void:
	if index >= model.size():
		return
	_push_edit("Duplicate pack", func():
		var copy: Dictionary = model[index].duplicate(true)
		copy["name"] = _unique_name(String(model[index].get("name", "Pack")))
		copy["pos"] = model[index].get("pos", Vector2.ZERO) + Vector2(40, 40)
		model.append(copy)
	)


func _save_template(index: int) -> void:
	if index >= model.size():
		return
	var pack: Dictionary = model[index]
	var template_name: String = pack.get("name", "")
	if template_name == "":
		push_warning("Candy Tools: name the pack before saving it as a template.")
		return

	if not CandyLootTemplates.has_template(template_name):
		_write_template(template_name, pack)
		return

	var dialog := ConfirmationDialog.new()
	dialog.title = "Template exists"
	dialog.dialog_text = "A template named \"%s\" already exists.\n\nOverwrite it, or delete it from the library?" % template_name
	dialog.ok_button_text = "Overwrite"
	dialog.cancel_button_text = "Cancel"

	dialog.add_button("Delete Template", false, "delete_template")
	dialog.custom_action.connect(func(action):
		if action == "delete_template":
			_erase_template(template_name)
			dialog.hide()
	)

	dialog.confirmed.connect(func(): _write_template(template_name, pack))
	dialog.close_requested.connect(dialog.queue_free)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.visibility_changed.connect(func():
		if not dialog.visible:
			dialog.queue_free()
	)
	EditorInterface.get_base_control().add_child(dialog)
	dialog.popup_centered()


func _write_template(template_name: String, pack: Dictionary) -> void:
	var result := CandyLootTemplates.save_template(template_name, pack)
	if result != OK:
		push_error("Candy Tools: failed to save template (error %d)" % result)


func _erase_template(template_name: String) -> void:
	var result := CandyLootTemplates.delete_template(template_name)
	if result != OK:
		push_error("Candy Tools: failed to delete template \"%s\" (error %d)" % [template_name, result])


func _on_delete_nodes_request(nodes: Array) -> void:
	var indices: Array = []
	for node_name in nodes:
		for i in pack_nodes.size():
			if pack_nodes[i].name == node_name and not indices.has(i):
				indices.append(i)
	_delete_packs(indices)


func _delete_packs(indices: Array) -> void:
	if indices.is_empty():
		return
	var ordered := indices.duplicate()
	ordered.sort()
	ordered.reverse()
	_push_edit("Delete pack" if indices.size() == 1 else "Delete packs", func():
		for i in ordered:
			if i >= 0 and i < model.size():
				model.remove_at(i)
	)


func _on_node_selected(node: Node) -> void:
	var index: int = pack_nodes.find(node)
	if index != -1:
		_apply_highlight(index)


func _on_node_deselected(_node: Node) -> void:
	_clear_tints()


func _clear_tints() -> void:
	for i in pack_nodes.size():
		pack_nodes[i].set_tint(_base_color(i))


func _apply_highlight(index: int) -> void:
	_clear_tints()
	if index >= model.size():
		return

	var levels: int = max(1, highlight_levels)
	for entry in _depths_from(index, levels):
		var target: int = entry[0]
		var depth: int = entry[1]
		if target >= pack_nodes.size():
			continue
		var strength := 1.0 - float(depth - 1) / float(levels)
		strength = clampf(strength, 0.15, 1.0)
		pack_nodes[target].set_tint(_base_color(target).lerp(_highlight_color(target), strength))


func _depths_from(start: int, levels: int) -> Array:
	var out: Array = []
	var visited: Dictionary = {start: true}
	var frontier: Array = [start]
	var depth := 1

	while depth <= levels and not frontier.is_empty():
		var next: Array = []
		for current in frontier:
			for child in _pack_children(current):
				if visited.has(child):
					continue
				visited[child] = true
				out.append([child, depth])
				next.append(child)
		frontier = next
		depth += 1
	return out


const CATEGORY_EMPTY = 0
const CATEGORY_ITEMS_ONLY = 1
const CATEGORY_PACKS = 2


func _category(index: int) -> int:
	if index < 0 or index >= model.size():
		return CATEGORY_PACKS
	var drops: Array = model[index].get("drops", [])
	var filled := 0
	for drop in drops:
		if String(drop.get("key", "")) == "":
			continue
		filled += 1
		if String(drop.get("key", "")).begins_with(prefix):
			return CATEGORY_PACKS
	return CATEGORY_EMPTY if filled == 0 else CATEGORY_ITEMS_ONLY


func _base_color(index: int) -> Color:
	match _category(index):
		CATEGORY_EMPTY:
			return CandyLootPackNode.BG_EMPTY
		CATEGORY_ITEMS_ONLY:
			return CandyLootPackNode.BG_ITEMS_ONLY
	return CandyLootPackNode.BG_COLOR


func _highlight_color(index: int) -> Color:
	match _category(index):
		CATEGORY_EMPTY:
			return CandyLootPackNode.HL_EMPTY
		CATEGORY_ITEMS_ONLY:
			return CandyLootPackNode.HL_ITEMS_ONLY
	return CandyLootPackNode.HL_PACKS


func _pack_children(index: int) -> Array:
	var out: Array = []
	if index < 0 or index >= model.size():
		return out
	for drop in model[index].get("drops", []):
		var key: String = drop.get("key", "")
		if not key.begins_with(prefix):
			continue
		var target := _index_of_key(key)
		if target != -1 and not out.has(target):
			out.append(target)
	return out


func _index_of_key(key: String) -> int:
	for i in model.size():
		if prefix + String(model[i].get("name", "")) == key:
			return i
	return -1


func _refresh_warnings() -> void:
	for i in pack_nodes.size():
		var messages: Array = []
		var pack: Dictionary = model[i]
		var pack_name: String = pack.get("name", "")

		if pack_name == "":
			messages.append("Pack needs a name")
		elif _name_used_by_other(pack_name, i):
			messages.append("Duplicate pack name")

		for drop in pack.get("drops", []):
			var key: String = drop.get("key", "")
			if key.begins_with(prefix) and _index_of_key(key) == -1:
				messages.append("Unknown pack: %s" % key)

		if _in_cycle(i):
			messages.append("Cycle: this pack can reach itself")

		pack_nodes[i].set_warning("\n".join(messages))


func _name_used_by_other(pack_name: String, except_index: int) -> bool:
	for i in model.size():
		if i != except_index and model[i].get("name", "") == pack_name:
			return true
	return false


func _in_cycle(start: int) -> bool:
	var queue: Array = _pack_children(start)
	var visited: Dictionary = {}
	while not queue.is_empty():
		var current: int = queue.pop_front()
		if current == start:
			return true
		if visited.has(current):
			continue
		visited[current] = true
		for child in _pack_children(current):
			queue.append(child)
	return false