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

signal property_changed(property: String, value: Variant)

signal target_pick_requested(target_index: int)

signal name_typed(text: String)

const PORT_NEXT = 0
const PORT_PREVIOUS = 1
const PORT_JUMP = 2
const PORT_COUNTDOWN = 3
const PORT_AUTO = 4

const JUMP_BLOCKED_COLOR = Color(0.55, 0.12, 0.12)

const PORT_COLORS = {
	PORT_NEXT: Color(0.4, 0.8, 1.0),
	PORT_PREVIOUS: Color(1.0, 0.7, 0.3),
	PORT_JUMP: Color(0.6, 1.0, 0.5),
	PORT_COUNTDOWN: Color(1.0, 0.4, 0.6),
	PORT_AUTO: Color(0.65, 0.45, 1.0),
}
const PORT_NAMES = {
	PORT_NEXT: "Next",
	PORT_PREVIOUS: "Previous",
	PORT_JUMP: "Jump",
	PORT_COUNTDOWN: "Countdown",
	PORT_AUTO: "Auto",
}

signal section_toggled(section: String)

const SECTION_TOGGLE = "Toggle"
const SECTION_TIMERS = "Timers"
const SECTION_TARGETS = "Targets"

const STATUS_OPTIONS = ["OK", "Inactive", "Disabled"]

const NODE_BG_COLOR = Color(0.16, 0.17, 0.20)
const NODE_TITLEBAR_COLOR = Color(0.21, 0.22, 0.26)
const NODE_SELECTED_BORDER_COLOR = Color(1, 1, 1)
const NODE_BORDER_WIDTH = 2
const NODE_CORNER_RADIUS = 4

const LABEL_COLUMN_WIDTH = 100

const PORT_ROW_MARGIN = 18

const STATUS_DISABLED_COLOR = Color(0.26, 0.11, 0.12)
const STATUS_INACTIVE_COLOR = Color(0.24, 0.22, 0.13)

const NAME_WARNING_COLOR = Color(1.0, 0.85, 0.2)

var state_index: int = -1
var state: CandyState = null
var name_warning: Label = null

var _slot_jump: int = -1

var _port_fields: Array[int] = []

var collapsed: Dictionary = {}

var name_edit: LineEdit = null
var status_option: OptionButton = null
var blacklist_check: CheckBox = null
var repeat_allowed_check: CheckBox = null
var cooldown_spin: SpinBox = null
var delay_spin: SpinBox = null
var countdown_spin: SpinBox = null
var auto_spin: SpinBox = null


func setup(index: int, candy_state: CandyState, collapsed_sections: Dictionary = {}) -> void:
	state_index = index
	state = candy_state
	collapsed = collapsed_sections
	_port_fields.clear()
	_slot_jump = -1
	name_edit = null
	name_warning = null
	status_option = null
	blacklist_check = null
	repeat_allowed_check = null
	cooldown_spin = null
	delay_spin = null
	countdown_spin = null
	auto_spin = null
	name = "State_%d" % index
	set_meta("state_index", index)
	custom_minimum_size = Vector2(240, 0)
	resizable = true
	_apply_node_theme()
	_refresh_title()

	for child in get_children():
		remove_child(child)
		child.free()

	var in_label := Label.new()
	in_label.text = "In"
	var in_slot := _add_row(in_label)
	set_slot(in_slot, true, 0, Color.WHITE, false, 0, Color.WHITE)

	name_edit = _make_line_edit(
		state.state_name,
		"state_name",
		"Reference name. Must NOT be a valid integer."
	)
	name_edit.text_submitted.connect(func(t): _emit_if_changed("state_name", t))
	name_edit.focus_exited.connect(func(): _emit_if_changed("state_name", name_edit.text))
	name_edit.text_changed.connect(func(t): name_typed.emit(t))

	name_warning = Label.new()
	name_warning.text = "Duplicate name"
	name_warning.add_theme_color_override("font_color", NAME_WARNING_COLOR)
	name_warning.visible = false

	var name_box := VBoxContainer.new()
	name_box.add_child(name_edit)
	name_box.add_child(name_warning)
	_add_row(name_box)

	status_option = OptionButton.new()
	for opt in STATUS_OPTIONS:
		status_option.add_item(opt)
	status_option.select(max(0, STATUS_OPTIONS.find(state.state_status)))
	status_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_option.item_selected.connect(
		func(i): _emit_if_changed("state_status", STATUS_OPTIONS[i])
	)
	_add_row(_label_wrap("Status", status_option))

	_add_row(_make_section_header(SECTION_TOGGLE))

	if not is_collapsed(SECTION_TOGGLE):
		repeat_allowed_check = CheckBox.new()
		repeat_allowed_check.text = "Repeat Allowed"
		repeat_allowed_check.tooltip_text = "Allow this state to repeat itself."
		repeat_allowed_check.button_pressed = state.repeat_allowed
		repeat_allowed_check.toggled.connect(func(p): _emit_if_changed("repeat_allowed", p))
		_add_row(repeat_allowed_check)

		_add_port_row(PORT_NEXT)
		_add_port_row(PORT_PREVIOUS)

		blacklist_check = CheckBox.new()
		blacklist_check.text = "Jump Blacklist"
		blacklist_check.tooltip_text = "When on, Jump links mark states that CANNOT be reached."
		blacklist_check.button_pressed = state.jump_blacklist
		blacklist_check.toggled.connect(func(p): _emit_if_changed("jump_blacklist", p))
		_add_row(blacklist_check)

		_slot_jump = _add_port_row(PORT_JUMP)

	_add_row(_make_section_header(SECTION_TIMERS))

	if not is_collapsed(SECTION_TIMERS):
		cooldown_spin = _make_spin(state.cooldown, "Seconds before switching is possible again.")
		cooldown_spin.value_changed.connect(func(v): _emit_if_changed("cooldown", v))
		_add_row(_label_wrap("Cooldown", cooldown_spin))

		delay_spin = _make_spin(state.delay, "Seconds before effects are triggered.")
		delay_spin.value_changed.connect(func(v): _emit_if_changed("delay", v))
		_add_row(_label_wrap("Delay", delay_spin))

		countdown_spin = _make_spin(state.countdown, "Seconds before auto-toggling to the Countdown state.")
		countdown_spin.value_changed.connect(func(v): _emit_if_changed("countdown", v))
		_add_port_field_row(PORT_COUNTDOWN, countdown_spin)

		auto_spin = _make_spin(state.auto, "Seconds after effects finish, before toggling to the Auto state.")
		auto_spin.value_changed.connect(func(v): _emit_if_changed("auto", v))
		_add_port_field_row(PORT_AUTO, auto_spin)

	_add_row(_make_section_header(SECTION_TARGETS))

	if not is_collapsed(SECTION_TARGETS):
		for ti in state.state_targets.size():
			_add_row(_make_target_row(ti, state.state_targets[ti]))

		var add_button := Button.new()
		add_button.text = "+ Add Target"
		add_button.pressed.connect(_on_add_target)
		_add_row(add_button)

	_refresh_jump_color()
	_apply_status_style()


func is_collapsed(section: String) -> bool:
	return collapsed.get(section, false)


func set_duplicate_warning(is_duplicate: bool) -> void:
	if name_warning:
		name_warning.visible = is_duplicate


func _make_section_header(section: String) -> Button:
	var button := Button.new()
	button.flat = true
	button.text = "%s  %s" % ["▶" if is_collapsed(section) else "▼", section]
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.tooltip_text = "Collapse or expand the %s section." % section
	button.pressed.connect(func(): section_toggled.emit(section))
	return button


func port_to_field(port: int) -> int:
	if port < 0 or port >= _port_fields.size():
		return -1
	return _port_fields[port]


func field_to_port(field: int) -> int:
	return _port_fields.find(field)


func _make_target_row(target_index: int, candy_target: CandyTarget) -> VBoxContainer:
	var box := VBoxContainer.new()

	var path_row := HBoxContainer.new()
	var path_edit := _make_line_edit(
		String(candy_target.target),
		"target NodePath",
		"Node to trigger effects on, relative to the CandyTrigger."
	)
	path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	path_edit.text_submitted.connect(
		func(t): _emit_target_field(target_index, "target", NodePath(t))
	)
	path_edit.focus_exited.connect(
		func(): _emit_target_field(target_index, "target", NodePath(path_edit.text))
	)
	path_row.add_child(path_edit)

	var pick_button := Button.new()
	pick_button.text = "..."
	pick_button.tooltip_text = "Pick a node that implements trigger_effect()."
	pick_button.pressed.connect(func(): target_pick_requested.emit(target_index))
	path_row.add_child(pick_button)

	var remove_button := Button.new()
	remove_button.text = "X"
	remove_button.tooltip_text = "Remove this target."
	remove_button.pressed.connect(func(): _on_remove_target(target_index))
	path_row.add_child(remove_button)

	box.add_child(path_row)

	var effects_row := HBoxContainer.new()

	var effects_edit := _make_line_edit(
		",".join(candy_target.effects),
		"effects, comma separated",
		"Effect names passed to the target's trigger_effect()."
	)
	effects_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	effects_edit.text_submitted.connect(
		func(t): _emit_target_field(target_index, "effects", _split_effects(t))
	)
	effects_edit.focus_exited.connect(
		func(): _emit_target_field(target_index, "effects", _split_effects(effects_edit.text))
	)
	effects_row.add_child(effects_edit)

	var wait_check := CheckBox.new()
	wait_check.text = "Wait"
	wait_check.tooltip_text = "Hold the switch until this target reports its effects are complete.\nA target that never erases itself from awaited_targets locks the trigger."
	wait_check.button_pressed = candy_target.wait_target
	wait_check.toggled.connect(
		func(p): _emit_target_field(target_index, "wait_target", p)
	)
	effects_row.add_child(wait_check)

	box.add_child(effects_row)

	return box


func _split_effects(raw: String) -> Array[String]:
	var out: Array[String] = []
	for piece in raw.split(","):
		var trimmed := piece.strip_edges()
		if trimmed != "":
			out.append(trimmed)
	return out


func _snapshot_targets() -> Array[CandyTarget]:
	var out: Array[CandyTarget] = []
	for t in state.state_targets:
		var copy := CandyTarget.new()
		copy.target = t.target
		copy.wait_target = t.wait_target
		copy.effects = t.effects.duplicate()
		out.append(copy)
	return out


func _emit_target_field(target_index: int, field: String, value: Variant) -> void:
	if state == null or target_index < 0 or target_index >= state.state_targets.size():
		return
	if state.state_targets[target_index].get(field) == value:
		return
	var snapshot := _snapshot_targets()
	snapshot[target_index].set(field, value)
	property_changed.emit("state_targets", snapshot)


func _on_add_target() -> void:
	if state == null:
		return
	var snapshot := _snapshot_targets()
	snapshot.append(CandyTarget.new())
	property_changed.emit("state_targets", snapshot)


func _on_remove_target(target_index: int) -> void:
	if state == null or target_index < 0 or target_index >= state.state_targets.size():
		return
	var snapshot := _snapshot_targets()
	snapshot.remove_at(target_index)
	property_changed.emit("state_targets", snapshot)


func apply_picked_target(target_index: int, path: NodePath) -> void:
	_emit_target_field(target_index, "target", path)


func _make_line_edit(text: String, placeholder: String, tooltip: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.text = text
	edit.placeholder_text = placeholder
	edit.tooltip_text = tooltip
	edit.caret_blink = true
	edit.caret_blink_interval = 0.65
	edit.focus_mode = Control.FOCUS_ALL
	edit.mouse_filter = Control.MOUSE_FILTER_STOP
	return edit


func _apply_node_theme() -> void:
	var panel := StyleBoxFlat.new()
	panel.bg_color = NODE_BG_COLOR
	panel.set_content_margin_all(8)
	panel.corner_radius_bottom_left = NODE_CORNER_RADIUS
	panel.corner_radius_bottom_right = NODE_CORNER_RADIUS
	panel.border_width_left = NODE_BORDER_WIDTH
	panel.border_width_right = NODE_BORDER_WIDTH
	panel.border_width_bottom = NODE_BORDER_WIDTH
	panel.border_color = Color(0, 0, 0, 0)

	var panel_selected: StyleBoxFlat = panel.duplicate()
	panel_selected.border_color = NODE_SELECTED_BORDER_COLOR

	var titlebar := StyleBoxFlat.new()
	titlebar.bg_color = NODE_TITLEBAR_COLOR
	titlebar.set_content_margin_all(8)
	titlebar.corner_radius_top_left = NODE_CORNER_RADIUS
	titlebar.corner_radius_top_right = NODE_CORNER_RADIUS
	titlebar.border_width_left = NODE_BORDER_WIDTH
	titlebar.border_width_right = NODE_BORDER_WIDTH
	titlebar.border_width_top = NODE_BORDER_WIDTH
	titlebar.border_color = Color(0, 0, 0, 0)

	var titlebar_selected: StyleBoxFlat = titlebar.duplicate()
	titlebar_selected.border_color = NODE_SELECTED_BORDER_COLOR

	add_theme_stylebox_override("panel", panel)
	add_theme_stylebox_override("panel_selected", panel_selected)
	add_theme_stylebox_override("titlebar", titlebar)
	add_theme_stylebox_override("titlebar_selected", titlebar_selected)


func _add_row(control: Control) -> int:
	add_child(control)
	return get_child_count() - 1


func _add_port_row(port_type: int) -> int:
	var label := Label.new()
	label.text = PORT_NAMES[port_type]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var slot := _add_row(label)
	set_slot(
		slot,
		false, 0, Color.WHITE,
		true, port_type, PORT_COLORS[port_type]
	)
	_port_fields.append(port_type)
	return slot


func _add_port_field_row(port_type: int, control: Control) -> int:
	var slot := _add_row(_label_wrap(PORT_NAMES[port_type], control))
	set_slot(
		slot,
		false, 0, Color.WHITE,
		true, port_type, PORT_COLORS[port_type]
	)
	_port_fields.append(port_type)
	return slot


func _make_spin(value: float, tooltip: String) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = 0.0
	spin.max_value = 36000000000.0
	spin.step = 0.1
	spin.allow_greater = true
	spin.value = value
	spin.tooltip_text = tooltip
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spin


func _label_wrap(text: String, control: Control) -> HBoxContainer:
	var box := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(LABEL_COLUMN_WIDTH, 0)
	box.add_child(label)
	box.add_child(control)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(PORT_ROW_MARGIN, 0)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(spacer)
	return box


func _emit_if_changed(property: String, value: Variant) -> void:
	if state == null:
		return
	if state.get(property) == value:
		return
	property_changed.emit(property, value)


func refresh_from_state() -> void:
	if state == null:
		return
	if name_edit and not name_edit.has_focus():
		name_edit.text = state.state_name
	if status_option:
		status_option.select(max(0, STATUS_OPTIONS.find(state.state_status)))
	if blacklist_check:
		blacklist_check.set_pressed_no_signal(state.jump_blacklist)
	if repeat_allowed_check:
		repeat_allowed_check.set_pressed_no_signal(state.repeat_allowed)
	_set_spin_no_signal(cooldown_spin, state.cooldown)
	_set_spin_no_signal(delay_spin, state.delay)
	_set_spin_no_signal(countdown_spin, state.countdown)
	_set_spin_no_signal(auto_spin, state.auto)
	_refresh_title()
	_refresh_jump_color()
	_apply_status_style()


func _set_spin_no_signal(spin: SpinBox, value: float) -> void:
	if spin == null or is_equal_approx(spin.value, value):
		return
	spin.set_block_signals(true)
	spin.value = value
	spin.set_block_signals(false)


func _refresh_jump_color() -> void:
	if _slot_jump < 0:
		return
	var jump_color: Color = JUMP_BLOCKED_COLOR if state.jump_blacklist else PORT_COLORS[PORT_JUMP]
	set_slot_color_right(_slot_jump, jump_color)


func _refresh_title() -> void:
	title = "[%d] %s" % [state_index, state.state_name if state.state_name != "" else "(unnamed)"]


func _apply_status_style() -> void:
	var tint: Color
	match state.state_status:
		"Disabled":
			tint = STATUS_DISABLED_COLOR
		"Inactive":
			tint = STATUS_INACTIVE_COLOR
		_:
			tint = NODE_BG_COLOR

	var panel := get_theme_stylebox("panel") as StyleBoxFlat
	if panel:
		panel.bg_color = tint
	var panel_selected := get_theme_stylebox("panel_selected") as StyleBoxFlat
	if panel_selected:
		panel_selected.bg_color = tint