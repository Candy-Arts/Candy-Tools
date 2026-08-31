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
extends GraphNode

signal pack_field_changed(field: String, value)
signal drop_field_changed(drop_index: int, field: String, value)
signal drop_added()
signal drop_removed(drop_index: int)
signal drop_pick_requested(drop_index: int)
signal pack_drag_dropped(source_key: String, drop_index: int)
signal drops_collapsed_toggled()
signal drop_collapsed_toggled(drop_index: int)
signal drop_moved(from_index: int, to_index: int)

const DRAG_TYPE = "candy_loot_pack"
const DROP_DRAG_TYPE = "candy_loot_drop"

const BG_COLOR = Color(0.16, 0.17, 0.20)
const BG_ITEMS_ONLY = Color(0.24, 0.15, 0.31)
const BG_EMPTY = Color(0.32, 0.20, 0.09)

const HL_PACKS = Color(0.20, 0.48, 0.92)
const HL_ITEMS_ONLY = Color(0.92, 0.35, 0.72)
const HL_EMPTY = Color(0.95, 0.80, 0.20)

const SELECTED_BORDER = Color(1, 1, 1)
const WARNING_COLOR = Color(1.0, 0.4, 0.35)
const BORDER_WIDTH = 2
const CORNER_RADIUS = 4

const RELATIVE_ONLY_TOOLTIP = "Only used when Number is 0 or greater (relative method)."

var pack_index: int = -1
var pack: Dictionary = {}
var pack_key: String = ""
var drops_collapsed: bool = false

var _name_edit: LineEdit
var _warning: Label
var _tint: Color = BG_COLOR


func setup(index: int, source_pack: Dictionary, key: String, collapsed: bool) -> void:
	pack_index = index
	pack = source_pack
	pack_key = key
	drops_collapsed = collapsed
	name = "Pack_%d" % index
	custom_minimum_size = Vector2(280, 0)
	title = key if source_pack.get("name", "") != "" else "(unnamed pack)"

	for child in get_children():
		remove_child(child)
		child.free()

	_apply_theme()
	_accept_drops(self, -1)

	var independent := _is_independent(String(source_pack.get("number", "")))

	var handle := Button.new()
	handle.text = "⠿  drag onto a pack to add as Drop"
	handle.tooltip_text = "Drag this onto another pack, or onto a Drop's key field."
	handle.flat = true
	handle.mouse_default_cursor_shape = Control.CURSOR_MOVE
	handle.set_drag_forwarding(
		_handle_get_drag_data, _can_accept_drag, _accept_drag.bind(-1, false))
	add_child(handle)

	_name_edit = _line_edit(source_pack.get("name", ""), "pack name", "Name without the prefix.")
	_name_edit.text_submitted.connect(func(t): pack_field_changed.emit("name", t))
	_name_edit.focus_exited.connect(func(): pack_field_changed.emit("name", _name_edit.text))

	_warning = Label.new()
	_warning.add_theme_color_override("font_color", WARNING_COLOR)
	_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_warning.visible = false

	var name_box := VBoxContainer.new()
	name_box.add_child(_name_edit)
	name_box.add_child(_warning)
	add_child(name_box)

	add_child(_field_row("Number", source_pack.get("number", ""), "number",
		"Draws. 0 = none, -1 = independent (% chance per drop). Blank = -1."))

	if not independent:
		add_child(_bool_row("Discard", source_pack.get("discard", false), "discard",
			"Reduce Chance of drawn items. " + RELATIVE_ONLY_TOOLTIP))

	var drops: Array = source_pack.get("drops", [])
	var drops_header := Button.new()
	drops_header.flat = true
	drops_header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	drops_header.text = "%s  Drops (%d)" % ["▶" if drops_collapsed else "▼", drops.size()]
	drops_header.pressed.connect(func(): drops_collapsed_toggled.emit())
	_accept_drops(drops_header, -1)
	add_child(drops_header)

	var drops_box := VBoxContainer.new()
	drops_box.custom_minimum_size = Vector2(0, 24)
	_accept_drops(drops_box, -1)
	add_child(drops_box)

	if not drops_collapsed:
		for i in drops.size():
			drops_box.add_child(_drop_row(i, drops[i], independent))

		var add_button := Button.new()
		add_button.text = "+ Add Drop"
		add_button.pressed.connect(func(): drop_added.emit())
		_accept_drops(add_button, -1)
		drops_box.add_child(add_button)
	else:
		var hint := Label.new()
		hint.text = "(drop packs here)"
		hint.modulate = Color(1, 1, 1, 0.4)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		drops_box.add_child(hint)


func _is_independent(number_text: String) -> bool:
	var trimmed := number_text.strip_edges()
	return trimmed == "" or trimmed == "-1"


func _drop_row(index: int, drop: Dictionary, independent: bool) -> Control:
	var box := VBoxContainer.new()
	_accept_drops(box, index)

	var drop_collapsed := bool(drop.get("collapsed", false))

	var key_row := HBoxContainer.new()

	var grip := Button.new()
	grip.text = "⠿"
	grip.flat = true
	grip.custom_minimum_size = Vector2(20, 0)
	grip.tooltip_text = "Drag to reorder this Drop."
	grip.mouse_default_cursor_shape = Control.CURSOR_MOVE
	grip.set_drag_forwarding(
		_drop_get_drag_data.bind(index), _can_accept_drag, _accept_drag.bind(index, false))
	key_row.add_child(grip)

	var fold := Button.new()
	fold.text = "▶" if drop_collapsed else "▼"
	fold.flat = true
	fold.custom_minimum_size = Vector2(22, 0)
	fold.tooltip_text = "Show or hide this Drop's fields."
	fold.pressed.connect(func(): drop_collapsed_toggled.emit(index))
	_accept_drops(fold, index)
	key_row.add_child(fold)

	var key_edit := _line_edit(drop.get("key", ""), "item or §Pack",
		"Item name, or a Pack key. You can drop a pack straight onto this field.")
	key_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key_edit.text_submitted.connect(func(t): drop_field_changed.emit(index, "key", t))
	key_edit.focus_exited.connect(func(): drop_field_changed.emit(index, "key", key_edit.text))
	_accept_drops(key_edit, index, true)
	key_row.add_child(key_edit)

	var pick := Button.new()
	pick.text = "..."
	pick.tooltip_text = "Pick a Pack from this table."
	pick.pressed.connect(func(): drop_pick_requested.emit(index))
	_accept_drops(pick, index, true)
	key_row.add_child(pick)

	var remove := Button.new()
	remove.text = "X"
	remove.tooltip_text = "Remove this Drop."
	remove.pressed.connect(func(): drop_removed.emit(index))
	_accept_drops(remove, index)
	key_row.add_child(remove)

	box.add_child(key_row)

	if not drop_collapsed:
		box.add_child(_drop_field(index, "Chance", drop.get("chance", ""), "chance",
			"Blank = 100 (independent) / 1 (relative)."))
		box.add_child(_drop_field(index, "Amount", drop.get("amount", ""), "amount",
			"1 = exactly 1. 25, 50 = either. [25, 50] = a range. [1, 3], 4 = both. Blank = 1."))

		if not independent:
			box.add_child(_drop_field(index, "Max", drop.get("max", ""), "max",
				"Max draws. Blank/-1 = unlimited. " + RELATIVE_ONLY_TOOLTIP))
			box.add_child(_drop_bool_row(index, "MaxDiscard", drop.get("maxdiscard", false), "maxdiscard",
				"Remove from pool at Max. " + RELATIVE_ONLY_TOOLTIP))
			box.add_child(_drop_field(index, "DiscardX", drop.get("discardx", ""), "discardx",
				"Chance reduction step. Blank = Chance, removing the Drop. " + RELATIVE_ONLY_TOOLTIP))

	box.add_child(HSeparator.new())
	return box


func _drop_field(drop_index: int, label_text: String, value: String, field: String, tip: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	_accept_drops(row, drop_index)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(88, 0)
	label.modulate = Color(1, 1, 1, 0.7)
	row.add_child(label)

	var edit := _line_edit(value, "", tip)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.text_submitted.connect(func(t): drop_field_changed.emit(drop_index, field, t))
	edit.focus_exited.connect(func(): drop_field_changed.emit(drop_index, field, edit.text))
	_accept_drops(edit, drop_index)
	row.add_child(edit)
	return row


func _field_row(label_text: String, value: String, field: String, tip: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	_accept_drops(row, -1)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(88, 0)
	row.add_child(label)

	var edit := _line_edit(value, "", tip)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.text_submitted.connect(func(t): pack_field_changed.emit(field, t))
	edit.focus_exited.connect(func(): pack_field_changed.emit(field, edit.text))
	_accept_drops(edit, -1)
	row.add_child(edit)
	return row


func _bool_row(label_text: String, value, field: String, tip: String) -> HBoxContainer:
	var row := _label_row(label_text, false, -1)
	_fill_bool_row(row, value, tip, -1, func(v): pack_field_changed.emit(field, v))
	return row


func _drop_bool_row(drop_index: int, label_text: String, value, field: String, tip: String) -> HBoxContainer:
	var row := _label_row(label_text, true, drop_index)
	_fill_bool_row(row, value, tip, drop_index,
		func(v): drop_field_changed.emit(drop_index, field, v))
	return row


func _fill_bool_row(row: HBoxContainer, value, tip: String, row_index: int, emit: Callable) -> void:
	var expression_mode := typeof(value) == TYPE_STRING

	if expression_mode:
		var edit := _line_edit(String(value), "€globals.flag", tip)
		edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		edit.text_submitted.connect(func(t): emit.call(t))
		edit.focus_exited.connect(func(): emit.call(edit.text))
		_accept_drops(edit, row_index)
		row.add_child(edit)
	else:
		row.add_child(_check_box(bool(value), tip, row_index,
			func(pressed: bool): emit.call(pressed)))

	var swap := Button.new()
	swap.flat = true
	swap.custom_minimum_size = Vector2(22, 0)
	if expression_mode:
		swap.text = "✓"
		swap.tooltip_text = "Use a checkbox instead."
		swap.pressed.connect(func(): emit.call(_text_is_true(String(value))))
	else:
		swap.text = "€"
		swap.tooltip_text = "Use an expression or variable reference instead."
		swap.pressed.connect(func(): emit.call("true" if bool(value) else ""))
	_accept_drops(swap, row_index)
	row.add_child(swap)


static func _text_is_true(text: String) -> bool:
	return text.strip_edges().to_lower() == "true"


func _label_row(label_text: String, dim: bool, row_index: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	_accept_drops(row, row_index)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(88, 0)
	if dim:
		label.modulate = Color(1, 1, 1, 0.7)
	row.add_child(label)
	return row


func _check_box(value: bool, tip: String, row_index: int, on_toggled: Callable) -> CheckBox:
	var check := CheckBox.new()
	check.button_pressed = value
	check.tooltip_text = tip
	check.focus_mode = Control.FOCUS_ALL
	check.toggled.connect(on_toggled)
	_accept_drops(check, row_index)
	return check


func _line_edit(value: String, placeholder: String, tip: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.text = value
	edit.placeholder_text = placeholder
	edit.tooltip_text = tip
	edit.caret_blink = false
	edit.focus_mode = Control.FOCUS_ALL
	edit.mouse_filter = Control.MOUSE_FILTER_STOP
	return edit


func _accept_drops(control: Control, row_index: int, overwrite_key: bool = false) -> void:
	control.set_drag_forwarding(
		Callable(), _can_accept_drag, _accept_drag.bind(row_index, overwrite_key))


func _handle_get_drag_data(_at: Vector2) -> Variant:
	var preview := Label.new()
	preview.text = pack_key
	set_drag_preview(preview)
	return {"type": DRAG_TYPE, "key": pack_key, "index": pack_index}


func _drop_get_drag_data(_at: Vector2, drop_index: int) -> Variant:
	var drops: Array = pack.get("drops", [])
	var key := ""
	if drop_index >= 0 and drop_index < drops.size():
		key = String(drops[drop_index].get("key", ""))

	var preview := Label.new()
	preview.text = key if key != "" else "(empty drop)"
	set_drag_preview(preview)
	return {"type": DROP_DRAG_TYPE, "pack": pack_index, "drop": drop_index}


func _can_accept_drag(_at: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	match String(data.get("type", "")):
		DRAG_TYPE:
			return data.get("index", -1) != pack_index
		DROP_DRAG_TYPE:
			return data.get("pack", -1) == pack_index
	return false


func _accept_drag(_at: Vector2, data: Variant, row_index: int, overwrite_key: bool) -> void:
	match String(data.get("type", "")):
		DRAG_TYPE:
			pack_drag_dropped.emit(String(data.get("key", "")), row_index if overwrite_key else -1)
		DROP_DRAG_TYPE:
			drop_moved.emit(int(data.get("drop", -1)), row_index)


func set_tint(color: Color) -> void:
	_tint = color
	_apply_theme()


func set_warning(text: String) -> void:
	if _warning == null:
		return
	_warning.text = text
	_warning.visible = text != ""


func _apply_theme() -> void:
	var panel := StyleBoxFlat.new()
	panel.bg_color = _tint
	panel.set_content_margin_all(8)
	panel.corner_radius_bottom_left = CORNER_RADIUS
	panel.corner_radius_bottom_right = CORNER_RADIUS
	panel.border_width_left = BORDER_WIDTH
	panel.border_width_right = BORDER_WIDTH
	panel.border_width_bottom = BORDER_WIDTH
	panel.border_color = Color(0, 0, 0, 0)

	var panel_selected: StyleBoxFlat = panel.duplicate()
	panel_selected.border_color = SELECTED_BORDER

	var titlebar := StyleBoxFlat.new()
	titlebar.bg_color = _tint.lightened(0.06)
	titlebar.set_content_margin_all(8)
	titlebar.corner_radius_top_left = CORNER_RADIUS
	titlebar.corner_radius_top_right = CORNER_RADIUS
	titlebar.border_width_left = BORDER_WIDTH
	titlebar.border_width_right = BORDER_WIDTH
	titlebar.border_width_top = BORDER_WIDTH
	titlebar.border_color = Color(0, 0, 0, 0)

	var titlebar_selected: StyleBoxFlat = titlebar.duplicate()
	titlebar_selected.border_color = SELECTED_BORDER

	add_theme_stylebox_override("panel", panel)
	add_theme_stylebox_override("panel_selected", panel_selected)
	add_theme_stylebox_override("titlebar", titlebar)
	add_theme_stylebox_override("titlebar_selected", titlebar_selected)