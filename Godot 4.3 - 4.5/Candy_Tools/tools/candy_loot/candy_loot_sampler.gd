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


const SamplerIO = preload("res://addons/Candy_Tools/tools/candy_loot/candy_loot_sampler_io.gd")
const SamplerStats = preload("res://addons/Candy_Tools/tools/candy_loot/candy_loot_sampler_stats.gd")
const TestTab = preload("res://addons/Candy_Tools/tools/candy_loot/candy_loot_test_tab.gd")

const SETTINGS_KEY := "candy_tools/loot_sampler"
const WARN_SAMPLE_COUNT := 100000

const TAB_BORDER := Color(1, 1, 1, 0.85)
const TAB_BORDER_DIM := Color(1, 1, 1, 0.35)
const TAB_BORDER_WIDTH := 1

var undo_redo: EditorUndoRedoManager = null

var _engine_edit: LineEdit
var _table_edit: LineEdit
var _dict_edit: LineEdit
var _dict_label: Label
var _prefix_edit: LineEdit
var _start_edit: LineEdit
var _packs_button: Button
var _pack_menu: PopupMenu
var _stacking_option: OptionButton
var _samples_spin: SpinBox
var _run_button: Button
var _config_header: Button
var _config_panel: VBoxContainer
var _status: Label
var _tabs: TabContainer

var _table: Dictionary = {}
var _table_loaded: bool = false
var _styling_tabs: bool = false



func _init() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 6)
	_build_config()
	_build_tabs()


func _ready() -> void:
	_restore_settings()
	_load_existing_tests()
	if not _table_edit.text.strip_edges().is_empty():
		_reload_table(false)


func _build_config() -> void:
	_config_header = Button.new()
	_config_header.flat = true
	_config_header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_config_header.pressed.connect(func(): _set_config_open(not _config_panel.visible))
	add_child(_config_header)

	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 4)
	_config_panel = panel

	var paths := GridContainer.new()
	paths.columns = 3

	var engine_label := Label.new()
	engine_label.text = "Candy Loot script"
	paths.add_child(engine_label)

	_engine_edit = LineEdit.new()
	_engine_edit.text = "res://Candy_Loot/Candy_Loot.gd"
	_engine_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_engine_edit.tooltip_text = "Path to Candy_Loot.gd. The sampler instantiates it to call draw_loot()."
	paths.add_child(_engine_edit)

	var engine_browse := Button.new()
	engine_browse.text = "..."
	engine_browse.pressed.connect(_on_browse_engine)
	paths.add_child(engine_browse)

	var table_label := Label.new()
	table_label.text = "Table"
	paths.add_child(table_label)

	_table_edit = LineEdit.new()
	_table_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_table_edit.placeholder_text = "res://... .tres, .txt or .gd"
	_table_edit.tooltip_text = "A Candy Tools table (.tres/.res), a plain table file (.txt),\nor a GDScript holding a table dictionary (.gd)."
	_table_edit.text_submitted.connect(func(_t): _reload_table(true))
	_table_edit.text_changed.connect(func(_t):
		_update_dict_field()
		_refresh_config_header()
	)
	paths.add_child(_table_edit)

	var table_browse := Button.new()
	table_browse.text = "..."
	table_browse.pressed.connect(_on_browse_table)
	paths.add_child(table_browse)

	_dict_label = Label.new()
	_dict_label.text = "Dictionary"
	paths.add_child(_dict_label)

	_dict_edit = LineEdit.new()
	_dict_edit.text = "packs_table"
	_dict_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dict_edit.tooltip_text = "Name of the table dictionary inside the .gd file.\nIgnored for .tres and .txt tables."
	_dict_edit.text_submitted.connect(func(_t): _reload_table(true))
	paths.add_child(_dict_edit)

	var load_button := Button.new()
	load_button.text = "Load"
	load_button.tooltip_text = "Read the table and list its Packs."
	load_button.pressed.connect(func(): _reload_table(true))
	paths.add_child(load_button)

	panel.add_child(paths)

	var options := HBoxContainer.new()

	var prefix_label := Label.new()
	prefix_label.text = "Pack prefix"
	options.add_child(prefix_label)

	_prefix_edit = LineEdit.new()
	_prefix_edit.text = SamplerIO.DEFAULT_PREFIX
	_prefix_edit.custom_minimum_size = Vector2(48, 0)
	_prefix_edit.tooltip_text = "Must match Candy Loot's pack_prefix.\nCandy Tools tables carry their own prefix and fill this in on load."
	_prefix_edit.text_submitted.connect(func(_t): _refresh_pack_list())
	_prefix_edit.focus_exited.connect(func(): _refresh_pack_list())
	options.add_child(_prefix_edit)

	options.add_child(VSeparator.new())

	var stacking_label := Label.new()
	stacking_label.text = "Stacking"
	options.add_child(stacking_label)

	_stacking_option = OptionButton.new()
	_stacking_option.add_item("0 - No stacking", 0)
	_stacking_option.add_item("1 - Drop stacking", 1)
	_stacking_option.add_item("2 - Pack stacking", 2)
	_stacking_option.add_item("3 - Full stacking", 3)
	_stacking_option.select(1)
	options.add_child(_stacking_option)

	options.add_child(VSeparator.new())

	var samples_label := Label.new()
	samples_label.text = "Samples"
	options.add_child(samples_label)

	_samples_spin = SpinBox.new()
	_samples_spin.min_value = 1
	_samples_spin.max_value = 10000000
	_samples_spin.value = 100
	_samples_spin.tooltip_text = "Large counts take a long time and hold the editor while they run."
	options.add_child(_samples_spin)

	options.add_child(VSeparator.new())

	_run_button = Button.new()
	_run_button.text = "Run Test"
	_run_button.tooltip_text = "Run a new test. Each run gets its own tab and save file."
	_run_button.pressed.connect(_on_run_pressed)
	options.add_child(_run_button)
	_samples_spin.value_changed.connect(func(_v): _refresh_config_header())

	panel.add_child(options)

	var start_row := HBoxContainer.new()

	var start_label := Label.new()
	start_label.text = "Start items"
	start_row.add_child(start_label)

	_start_edit = LineEdit.new()
	_start_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_start_edit.text_changed.connect(func(_t): _refresh_config_header())
	_start_edit.placeholder_text = "§Pack_1, §Pack_1, §Pack_2"
	_start_edit.tooltip_text = "Items handed to draw_loot(), separated by commas and drawn in order.\nThe same Pack can appear more than once.\nPlain items (no prefix) pass straight through to the results."
	start_row.add_child(_start_edit)

	_packs_button = Button.new()
	_packs_button.text = "Packs ▾"
	_packs_button.tooltip_text = "Pick a Pack from the loaded table to append it."
	_packs_button.pressed.connect(_on_packs_pressed)
	start_row.add_child(_packs_button)

	_pack_menu = PopupMenu.new()
	_pack_menu.id_pressed.connect(_on_pack_picked)
	_packs_button.add_child(_pack_menu)

	var clear_button := Button.new()
	clear_button.text = "Clear"
	clear_button.pressed.connect(func(): _start_edit.text = "")
	start_row.add_child(clear_button)

	panel.add_child(start_row)

	add_child(panel)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.visible = false
	add_child(_status)

	var sep := HSeparator.new()
	var sep_style := StyleBoxLine.new()
	sep_style.color = Color(0.97, 0.84, 0.45)
	sep.add_theme_stylebox_override("separator", sep_style)
	add_child(sep)
	_set_config_open(true)


func _set_config_open(open: bool) -> void:
	_config_panel.visible = open
	_refresh_config_header()
	if is_inside_tree():
		_save_settings()


func _refresh_config_header() -> void:
	var arrow := "▾  " if _config_panel.visible else "▸  "
	var summary := ""
	if not _config_panel.visible:
		var table_name: String = _table_edit.text.get_file()
		var start_text: String = _start_edit.text.strip_edges()
		var parts := []
		if not table_name.is_empty():
			parts.append(table_name)
		if not start_text.is_empty():
			parts.append(start_text)
		parts.append("%d samples" % int(_samples_spin.value))
		summary = "    (%s)" % "  ·  ".join(parts)
	_config_header.text = "%sTest Configuration%s" % [arrow, summary]


func _build_tabs() -> void:
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.tab_changed.connect(_on_tab_changed)
	add_child(_tabs)
	_outline_tabs()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		_outline_tabs()


func _outline_tabs() -> void:
	if _tabs == null or _styling_tabs:
		return
	_styling_tabs = true

	for style_name in ["tab_selected", "tab_hovered", "tab_unselected", "tab_disabled"]:
		if _tabs.has_theme_stylebox_override(style_name):
			_tabs.remove_theme_stylebox_override(style_name)
		if not _tabs.has_theme_stylebox(style_name, "TabContainer"):
			continue

		var base: StyleBox = _tabs.get_theme_stylebox(style_name, "TabContainer")
		var box: StyleBoxFlat
		if base is StyleBoxFlat:
			box = base.duplicate()
		else:
			box = StyleBoxFlat.new()
			box.bg_color = Color(0, 0, 0, 0)
			box.content_margin_left = base.content_margin_left
			box.content_margin_right = base.content_margin_right
			box.content_margin_top = base.content_margin_top
			box.content_margin_bottom = base.content_margin_bottom

		box.border_width_top = TAB_BORDER_WIDTH
		box.border_width_left = TAB_BORDER_WIDTH
		box.border_width_right = TAB_BORDER_WIDTH
		box.border_width_bottom = 0
		box.border_color = TAB_BORDER if style_name == "tab_selected" else TAB_BORDER_DIM
		_tabs.add_theme_stylebox_override(style_name, box)

	_styling_tabs = false


func set_table(path: String, dict_name: String = "", prefix: String = "") -> void:
	_table_edit.text = path
	if not dict_name.is_empty():
		_dict_edit.text = dict_name
	if not prefix.is_empty():
		_prefix_edit.text = prefix
	_update_dict_field()
	_reload_table(true)


func _update_dict_field() -> void:
	var is_script := _table_edit.text.get_extension().to_lower() == "gd"
	_dict_edit.editable = is_script
	_dict_edit.modulate = Color(1, 1, 1, 1.0 if is_script else 0.4)
	_dict_label.modulate = Color(1, 1, 1, 1.0 if is_script else 0.4)


func _reload_table(report: bool) -> void:
	var result: Dictionary = SamplerIO.load_table(_table_edit.text.strip_edges(), _dict_edit.text.strip_edges())
	if not result["ok"]:
		_table = {}
		_table_loaded = false
		_pack_menu.clear()
		_packs_button.disabled = true
		if report:
			_show_status(result["error"])
		return

	_table = result["table"]
	_table_loaded = true

	if not String(result["prefix"]).is_empty():
		_prefix_edit.text = result["prefix"]

	_refresh_pack_list()
	if report:
		_show_status("Loaded %d Packs from %s" % [_pack_menu.item_count, _table_edit.text])
	_save_settings()


func _refresh_pack_list() -> void:
	_pack_menu.clear()
	if not _table_loaded:
		_packs_button.disabled = true
		return

	var packs: Array = SamplerIO.list_packs(_table, _prefix_edit.text)
	for i in range(packs.size()):
		_pack_menu.add_item(packs[i], i)
	_packs_button.disabled = packs.is_empty()

	if packs.is_empty():
		_show_status("No keys in this table start with '%s'. Check the Pack prefix." % _prefix_edit.text)


func _on_packs_pressed() -> void:
	if _pack_menu.item_count == 0:
		return
	_pack_menu.reset_size()
	_pack_menu.position = Vector2i(_packs_button.get_screen_position() + Vector2(0, _packs_button.size.y))
	_pack_menu.popup()


func _on_pack_picked(id: int) -> void:
	var pack: String = _pack_menu.get_item_text(_pack_menu.get_item_index(id))
	var text: String = _start_edit.text.strip_edges()
	_start_edit.text = pack if text.is_empty() else "%s, %s" % [text, pack]
	_start_edit.caret_column = _start_edit.text.length()


func _parse_start_items() -> Array:
	var items := []
	for part in _start_edit.text.split(",", false):
		var clean := part.strip_edges()
		if not clean.is_empty():
			items.append(clean)
	return items


func _on_run_pressed() -> void:
	if _parse_start_items().is_empty():
		_show_status("Add at least one start item before running.")
		return
	if not _table_loaded:
		_reload_table(true)
		if not _table_loaded:
			return

	var count := int(_samples_spin.value)
	if count >= WARN_SAMPLE_COUNT:
		var dialog := ConfirmationDialog.new()
		dialog.title = "Large Test"
		dialog.dialog_text = "%d samples will hold the editor until the run finishes.\nRun anyway?" % count
		dialog.confirmed.connect(func(): _start_new_test(count))
		dialog.confirmed.connect(dialog.queue_free)
		dialog.close_requested.connect(func(): dialog.queue_free())
		add_child(dialog)
		dialog.popup_centered()
		return

	_start_new_test(count)


func _start_new_test(count: int) -> void:
	var start_items := _parse_start_items()
	var samples := _draw_samples(_table, start_items, _stacking_option.get_selected_id(), count, _prefix_edit.text)
	if samples.is_empty():
		return

	var aggregate: Dictionary = SamplerStats.new_aggregate()
	SamplerStats.accumulate(aggregate, samples)

	var test_name: String = SamplerIO.unique_test_name()
	var header := {
		"name": test_name,
		"created": Time.get_datetime_string_from_system(false, true),
		"table_path": _table_edit.text.strip_edges(),
		"dict_name": _dict_edit.text.strip_edges() if _table_edit.text.get_extension().to_lower() == "gd" else "",
		"prefix": _prefix_edit.text,
		"engine_path": _engine_edit.text.strip_edges(),
		"start_items": start_items,
		"stacking": _stacking_option.get_selected_id(),
		"table_hash": SamplerIO.table_hash(_table),
		"table_snapshot": _table.duplicate(true),
		"runs": [samples.size()],
		"aggregate": aggregate,
	}

	if SamplerIO.save_header(header) != OK:
		return
	SamplerIO.append_raw(test_name, samples)

	var tab := _add_tab(test_name)
	_tabs.current_tab = tab.get_index()
	_show_status("Ran %s: %d samples." % [test_name, samples.size()])
	_save_settings()


func _on_test_more(test_name: String, extra: int) -> void:
	var header: Dictionary = SamplerIO.load_header(test_name)
	if header.is_empty():
		_show_status("Could not read '%s'." % test_name)
		return

	var result: Dictionary = SamplerIO.load_table(header.get("table_path", ""), header.get("dict_name", ""))
	if not result["ok"]:
		_show_status(result["error"])
		return
	if SamplerIO.table_hash(result["table"]) != int(header.get("table_hash", 0)):
		_show_status("'%s' has changed since %s ran. Run a new test instead." % [header.get("table_path", ""), test_name])
		return

	var samples := _draw_samples(
		result["table"],
		header.get("start_items", []),
		int(header.get("stacking", 0)),
		extra,
		header.get("prefix", SamplerIO.DEFAULT_PREFIX),
		header.get("engine_path", ""),
	)
	if samples.is_empty():
		return

	var aggregate: Dictionary = header.get("aggregate", SamplerStats.new_aggregate())
	SamplerStats.accumulate(aggregate, samples)
	header["aggregate"] = aggregate

	var runs: Array = header.get("runs", [])
	runs.append(samples.size())
	header["runs"] = runs

	if SamplerIO.save_header(header) != OK:
		return
	SamplerIO.append_raw(test_name, samples)

	var tab := _find_tab(test_name)
	if tab != null:
		tab.reload()
	_show_status("%s now holds %d samples." % [test_name, aggregate["samples"]])


func _draw_samples(table: Dictionary, start_items: Array, stacking: int, count: int, prefix: String, engine_override: String = "") -> Array:
	var engine_path: String = engine_override if not engine_override.is_empty() else _engine_edit.text.strip_edges()
	if engine_path.is_empty():
		_show_status("Set the path to Candy_Loot.gd.")
		return []

	var script = load(engine_path)
	if script == null:
		_show_status("Could not load %s. If it references a Candy Dialogue Engine autoload that isn't in this project, the script won't compile." % engine_path)
		return []

	var engine = script.new()
	if engine == null or not engine.has_method("draw_loot"):
		_release(engine)
		_show_status("%s has no draw_loot() method." % engine_path)
		return []

	if "pack_prefix" in engine:
		engine.pack_prefix = prefix

	var samples := []
	for i in range(count):
		samples.append(engine.draw_loot(start_items.duplicate(), table, stacking))

	_release(engine)
	return samples


func _release(instance) -> void:
	if instance is Node:
		instance.free()


func _load_existing_tests() -> void:
	for test_name in SamplerIO.list_tests():
		_add_tab(test_name)
	if _tabs.get_child_count() > 0:
		_on_tab_changed(_tabs.current_tab)


func _add_tab(test_name: String) -> Control:
	var tab: Control = TestTab.new()
	tab.name = test_name
	tab.set_test_name(test_name)
	tab.test_renamed.connect(_on_tab_renamed)
	tab.test_deleted.connect(_on_tab_deleted)
	tab.test_more_requested.connect(_on_test_more)
	tab.item_clicked.connect(_on_item_clicked)
	_tabs.add_child(tab)
	_tabs.set_tab_title(tab.get_index(), test_name)
	return tab


func _find_tab(test_name: String) -> Control:
	for child in _tabs.get_children():
		if child.test_name == test_name:
			return child
	return null


func _on_tab_changed(index: int) -> void:
	for child in _tabs.get_children():
		if child.get_index() == index:
			child.ensure_loaded()
		else:
			child.unload()


func _on_tab_renamed(_old_name: String, new_name: String) -> void:
	var tab := _find_tab(new_name)
	if tab != null:
		tab.name = new_name
		_tabs.set_tab_title(tab.get_index(), new_name)


func _on_tab_deleted(test_name: String) -> void:
	var tab := _find_tab(test_name)
	if tab == null:
		return
	_tabs.remove_child(tab)
	tab.queue_free()
	_show_status("Deleted %s." % test_name)


func _on_item_clicked(_test_name: String, _item: String) -> void:
	pass


func _on_browse_engine() -> void:
	_browse(["*.gd"], func(path: String):
		_engine_edit.text = path
		_save_settings()
	)


func _on_browse_table() -> void:
	_browse(["*.tres", "*.res", "*.txt", "*.gd"], func(path: String):
		_table_edit.text = path
		_update_dict_field()
		_reload_table(true)
	)


func _browse(filters: Array, on_selected: Callable) -> void:
	var dialog := EditorFileDialog.new()
	dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	dialog.access = EditorFileDialog.ACCESS_RESOURCES
	for filter in filters:
		dialog.add_filter(filter)
	dialog.file_selected.connect(func(path: String):
		on_selected.call(path)
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered_ratio(0.6)


func _show_status(text: String) -> void:
	_status.text = text
	_status.visible = true


func _save_settings() -> void:
	var settings := EditorInterface.get_editor_settings()
	settings.set_project_metadata(SETTINGS_KEY, "engine_path", _engine_edit.text)
	settings.set_project_metadata(SETTINGS_KEY, "table_path", _table_edit.text)
	settings.set_project_metadata(SETTINGS_KEY, "dict_name", _dict_edit.text)
	settings.set_project_metadata(SETTINGS_KEY, "prefix", _prefix_edit.text)
	settings.set_project_metadata(SETTINGS_KEY, "start_items", _start_edit.text)
	settings.set_project_metadata(SETTINGS_KEY, "stacking", _stacking_option.get_selected_id())
	settings.set_project_metadata(SETTINGS_KEY, "samples", int(_samples_spin.value))
	settings.set_project_metadata(SETTINGS_KEY, "config_open", _config_panel.visible)


func _restore_settings() -> void:
	var settings := EditorInterface.get_editor_settings()
	_engine_edit.text = settings.get_project_metadata(SETTINGS_KEY, "engine_path", _engine_edit.text)
	_table_edit.text = settings.get_project_metadata(SETTINGS_KEY, "table_path", "")
	_dict_edit.text = settings.get_project_metadata(SETTINGS_KEY, "dict_name", "packs_table")
	_prefix_edit.text = settings.get_project_metadata(SETTINGS_KEY, "prefix", SamplerIO.DEFAULT_PREFIX)
	_start_edit.text = str(settings.get_project_metadata(SETTINGS_KEY, "start_items", ""))
	var stacking_index := _stacking_option.get_item_index(
		int(settings.get_project_metadata(SETTINGS_KEY, "stacking", 1))
	)
	_stacking_option.select(stacking_index if stacking_index >= 0 else 1)
	_samples_spin.value = settings.get_project_metadata(SETTINGS_KEY, "samples", 100)
	_set_config_open(bool(settings.get_project_metadata(SETTINGS_KEY, "config_open", true)))
	_update_dict_field()