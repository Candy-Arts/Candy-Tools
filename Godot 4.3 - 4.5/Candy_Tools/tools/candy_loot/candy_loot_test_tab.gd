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

const PAGE_SIZE := 10
const PAGE_MENU_LIMIT := 1000
const RANKED_LIMIT := 60
const DRAGGER_SCALE := 4

const C_SECTION := Color(0.50, 0.85, 0.55)
const C_TITLE := Color(0.96, 0.56, 0.76)
const C_LABEL := Color(0.95, 0.96, 0.98)
const C_VALUE := Color(0.90, 0.93, 0.97)
const C_DIM := Color(0.72, 0.76, 0.84)
const C_ITEM := Color(0.97, 0.84, 0.45)
const C_COUNT := Color(0.44, 0.84, 0.95)
const C_RATE := Color(0.52, 0.89, 0.58)
const C_FRACTION := Color(0.55, 0.72, 0.96)
const C_MUTED := Color(0.58, 0.61, 0.68)
const C_WARN := Color(1.0, 0.68, 0.33)

signal test_renamed(old_name: String, new_name: String)
signal test_deleted(test_name: String)
signal test_more_requested(test_name: String, extra_samples: int)
signal item_clicked(test_name: String, item: String)

var test_name: String = ""

var _header: Dictionary = {}
var _loaded: bool = false
var _table_changed: bool = false
var _view: String = "overview"
var _page: int = 0
var _page_size: int = PAGE_SIZE
var _item_filter: String = ""
var _metric: String = "sar"
var _detail_item: String = ""
var _collapsed: Dictionary = {}
var _graph: Dictionary = {}
var _ranked_sort: String = "value_desc"
var _item_sort: String = "value_desc"

var _name_edit: LineEdit
var _samples_label: Label
var _more_spin: SpinBox
var _more_button: Button
var _warning: Label
var _view_bar: HBoxContainer
var _split: HSplitContainer
var _scaling_dragger: bool = false
var _content: VBoxContainer
var _graph_pane: VBoxContainer
var _graph_title: Label
var _graph_subtitle: Label
var _graph_body: VBoxContainer
var _status: Label


const METRICS := [
	{"key": "sar", "name": "Sample Rate", "pct": true},
	{"key": "tar", "name": "Total Item Rate", "pct": true},
	{"key": "aar", "name": "Avg. Rate", "pct": true},
	{"key": "taar", "name": "Total Amount Rate", "pct": true},
	{"key": "aaar", "name": "Avg. Amount Rate", "pct": true},
	{"key": "avg_draws", "name": "Avg. Sample Draws", "pct": false},
	{"key": "avg_units", "name": "Avg. Sample Amount", "pct": false},
]

const SORT_MODES := [
	{"key": "value_desc", "name": "Highest"},
	{"key": "value_asc", "name": "Lowest"},
	{"key": "name_asc", "name": "A-Z"},
	{"key": "name_desc", "name": "Z-A"},
]

const VIEWS := [
	{"key": "overview", "name": "Overview"},
	{"key": "items", "name": "Items"},
	{"key": "distribution", "name": "Distribution"},
	{"key": "samples", "name": "Per-Sample"},
	{"key": "raw", "name": "Raw"},
]


static func _tint(control: Control, color: Color) -> Control:
	control.add_theme_color_override("font_color", color)
	if control is Button:
		control.add_theme_color_override("font_hover_color", color.lightened(0.25))
		control.add_theme_color_override("font_pressed_color", color)
		control.add_theme_color_override("font_focus_color", color)
		control.add_theme_color_override("font_hover_pressed_color", color.lightened(0.25))
	return control


func _init() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 6)
	_build_chrome()


func _build_chrome() -> void:
	var bar := HBoxContainer.new()

	var name_label := Label.new()
	name_label.text = "Name"
	bar.add_child(name_label)

	_name_edit = LineEdit.new()
	_name_edit.custom_minimum_size = Vector2(160, 0)
	_name_edit.tooltip_text = "Renaming a test renames its save files."
	_name_edit.text_submitted.connect(func(t): _commit_rename(t))
	_name_edit.focus_exited.connect(func(): _commit_rename(_name_edit.text))
	bar.add_child(_name_edit)

	_samples_label = Label.new()
	_tint(_samples_label, C_COUNT)
	bar.add_child(_samples_label)

	bar.add_child(VSeparator.new())

	var more_label := Label.new()
	more_label.text = "Test More"
	bar.add_child(more_label)

	_more_spin = SpinBox.new()
	_more_spin.min_value = 1
	_more_spin.max_value = 1000000
	_more_spin.value = 100
	_more_spin.tooltip_text = "Extra samples to add to this test.\nThey're merged in as if the test had always been that size."
	bar.add_child(_more_spin)

	_more_button = Button.new()
	_more_button.text = "Add Samples"
	_more_button.pressed.connect(func(): test_more_requested.emit(test_name, int(_more_spin.value)))
	bar.add_child(_more_button)

	bar.add_child(VSeparator.new())

	var export_button := Button.new()
	export_button.text = "Export CSV"
	export_button.pressed.connect(_on_export_pressed)
	bar.add_child(export_button)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(4, 0)
	bar.add_child(gap)

	var delete_button := Button.new()
	delete_button.text = "Delete"
	delete_button.tooltip_text = "Delete this test and its save files."
	delete_button.pressed.connect(_on_delete_pressed)
	bar.add_child(delete_button)

	add_child(bar)

	_warning = Label.new()
	_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_warning.visible = false
	_tint(_warning, C_WARN)
	add_child(_warning)

	_view_bar = HBoxContainer.new()
	for view in VIEWS:
		var button := Button.new()
		button.text = view["name"]
		button.toggle_mode = true
		button.button_pressed = view["key"] == _view
		button.pressed.connect(_on_view_pressed.bind(view["key"]))
		_view_bar.add_child(button)
	add_child(_view_bar)

	add_child(HSeparator.new())

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.split_offset = 0
	split.dragger_visibility = SplitContainer.DRAGGER_VISIBLE
	_split = split
	add_child(split)

	_content = VBoxContainer.new()
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.size_flags_stretch_ratio = 1.0
	_content.custom_minimum_size = Vector2(240, 0)
	split.add_child(_content)

	split.add_child(_build_graph_pane())
	_widen_dragger()

	_status = Label.new()
	_status.visible = false
	_tint(_status, C_WARN)
	add_child(_status)


func _widen_dragger() -> void:
	if _split == null or _scaling_dragger:
		return
	_scaling_dragger = true

	if _split.has_theme_icon_override("grabber"):
		_split.remove_theme_icon_override("grabber")

	if _split.has_theme_icon("grabber", "HSplitContainer"):
		var icon: Texture2D = _split.get_theme_icon("grabber", "HSplitContainer")
		var image: Image = icon.get_image()
		if image != null:
			image = image.duplicate()
			if image.is_compressed():
				image.decompress()
			image.resize(image.get_width() * DRAGGER_SCALE, image.get_height(), Image.INTERPOLATE_LANCZOS)
			_split.add_theme_icon_override("grabber", ImageTexture.create_from_image(image))
			_split.add_theme_constant_override("minimum_grab_thickness", image.get_width() + 2)

	_scaling_dragger = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		_widen_dragger()


func _build_graph_pane() -> Control:
	_graph_pane = VBoxContainer.new()
	_graph_pane.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_graph_pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_graph_pane.size_flags_stretch_ratio = 1.0
	_graph_pane.custom_minimum_size = Vector2(180, 0)
	_graph_pane.add_theme_constant_override("separation", 2)

	var header := HBoxContainer.new()

	_graph_title = Label.new()
	_graph_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_graph_title.add_theme_font_size_override("font_size", 15)
	_graph_title.text = "Graph"
	_tint(_graph_title, C_TITLE)
	header.add_child(_graph_title)

	var clear := Button.new()
	clear.text = "✕"
	clear.flat = true
	clear.tooltip_text = "Clear the graph."
	clear.pressed.connect(func():
		_graph = {}
		_refresh_graph()
	)
	header.add_child(clear)
	_graph_pane.add_child(header)

	_graph_subtitle = Label.new()
	_tint(_graph_subtitle, C_MUTED)
	_graph_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_graph_pane.add_child(_graph_subtitle)

	_graph_pane.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_graph_body = VBoxContainer.new()
	_graph_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_graph_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(_graph_body)
	_graph_pane.add_child(scroll)

	return _graph_pane


func ensure_loaded() -> void:
	if _loaded:
		return
	_header = SamplerIO.load_header(test_name)
	_loaded = not _header.is_empty()
	if not _loaded:
		_show_message("Could not read the save file for '%s'." % test_name)
		return
	_check_table_changed()
	_refresh_toolbar()
	_rebuild_content()
	_refresh_graph()


func unload() -> void:
	_header = {}
	_loaded = false
	_detail_item = ""
	_page = 0
	_graph = {}
	for child in _content.get_children():
		child.queue_free()
	_refresh_graph()


func reload() -> void:
	_loaded = false
	ensure_loaded()


func set_test_name(new_name: String) -> void:
	test_name = new_name
	if _name_edit != null:
		_name_edit.text = new_name


func _check_table_changed() -> void:
	_table_changed = false
	var path: String = _header.get("table_path", "")
	if path.is_empty():
		return

	var result: Dictionary = SamplerIO.load_table(path, _header.get("dict_name", ""))
	if not result["ok"]:
		_table_changed = true
		_warning.text = "⚠  The table file can no longer be read (%s). Test More is disabled; the results below are unaffected." % result["error"]
		_warning.visible = true
		_more_button.disabled = true
		_more_spin.editable = false
		return

	if SamplerIO.table_hash(result["table"]) != int(_header.get("table_hash", 0)):
		_table_changed = true
		_warning.text = "⚠  '%s' has changed since this test ran. Test More is disabled: new samples would come from a different table. The results below still reflect the table as it was." % path
		_warning.visible = true
		_more_button.disabled = true
		_more_spin.editable = false
	else:
		_warning.visible = false
		_more_button.disabled = false
		_more_spin.editable = true


func _refresh_toolbar() -> void:
	_name_edit.text = test_name
	var agg: Dictionary = _header.get("aggregate", {})
	_samples_label.text = "%d samples" % agg.get("samples", 0)


func _commit_rename(text: String) -> void:
	var clean := SamplerIO.sanitize_name(text)
	if clean.is_empty() or clean == test_name:
		_name_edit.text = test_name
		return

	var error := SamplerIO.rename_test(test_name, clean)
	if not error.is_empty():
		_show_message(error)
		_name_edit.text = test_name
		return

	var old := test_name
	test_name = clean
	_name_edit.text = clean
	if _loaded:
		_header["name"] = clean
	test_renamed.emit(old, clean)


func _on_delete_pressed() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = "Delete '%s' and its save files?" % test_name
	dialog.title = "Delete Test"
	dialog.confirmed.connect(func():
		SamplerIO.delete_test(test_name)
		test_deleted.emit(test_name)
	)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.close_requested.connect(func(): dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()


func _on_export_pressed() -> void:
	ensure_loaded()
	if not _loaded:
		return

	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.title = "Export CSV to folder"
	dialog.dir_selected.connect(func(dir: String):
		var raw: Array = SamplerIO.load_raw(test_name)
		var error: String = SamplerStats.export_csv(dir, test_name, _header, raw)
		if error.is_empty():
			_show_message("Exported '%s' CSV files to %s" % [test_name, dir])
		else:
			_show_message(error)
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered_ratio(0.6)


func _on_view_pressed(key: String) -> void:
	_view = key
	_page = 0
	for i in range(_view_bar.get_child_count()):
		var button: Button = _view_bar.get_child(i)
		button.button_pressed = VIEWS[i]["key"] == key
	_rebuild_content()


func _show_message(text: String) -> void:
	_status.text = text
	_status.visible = true


func _show_graph(graph: Dictionary, data: Array) -> void:
	_graph = graph.duplicate()
	_graph["values"] = data
	_refresh_graph()


func _refresh_graph() -> void:
	if _graph_body == null:
		return
	for child in _graph_body.get_children():
		_graph_body.remove_child(child)
		child.queue_free()

	if _graph.is_empty():
		_graph_title.text = "Graph"
		_graph_subtitle.text = "Pick a statistic's graph button to plot it here."
		return

	_graph_title.text = _graph["title"]
	_graph_subtitle.text = _graph["subtitle"]

	var data: Array = _graph["values"]
	if data.is_empty():
		var empty := Label.new()
		empty.text = "(no data)"
		_tint(empty, C_MUTED)
		_graph_body.add_child(empty)
		return

	if _graph["kind"] == "histogram":
		var chart := Histogram.new()
		chart.pairs = data
		chart.label_color = C_LABEL
		chart.peak_color = C_ITEM
		chart.axis_color = C_DIM
		chart.y_axis_color = C_LABEL
		chart.x_label = _graph.get("x_label", "value")
		chart.y_label = _graph.get("y_label", "Samples")
		chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
		chart.custom_minimum_size = Vector2(0, 220)
		_graph_body.add_child(chart)
	else:
		_graph_body.add_child(_build_sort_row())
		var ranked := RankedChart.new()
		ranked.entries = _sort_ranked(data)
		ranked.label_color = C_ITEM
		ranked.value_color = C_COUNT
		ranked.axis_color = C_DIM
		ranked.y_axis_color = C_LABEL
		ranked.x_label = _graph.get("x_label", "value")
		ranked.y_label = _graph.get("y_label", "Items")
		ranked.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ranked.custom_minimum_size = Vector2(0, data.size() * RankedChart.ROW_HEIGHT + RankedChart.HEADER_HEIGHT)
		_graph_body.add_child(ranked)


func _build_sort_row() -> Control:
	var row := HBoxContainer.new()

	var label := Label.new()
	label.text = "Order"
	_tint(label, C_LABEL)
	row.add_child(label)

	var option := OptionButton.new()
	for i in range(SORT_MODES.size()):
		option.add_item(SORT_MODES[i]["name"], i)
		if SORT_MODES[i]["key"] == _ranked_sort:
			option.select(i)
	option.item_selected.connect(func(index):
		_ranked_sort = SORT_MODES[index]["key"]
		_refresh_graph()
	)
	row.add_child(option)

	return row


func _sort_ranked(entries: Array) -> Array:
	var sorted := entries.duplicate()
	match _ranked_sort:
		"value_asc":
			sorted.sort_custom(func(a, b): return float(a[1]) < float(b[1]))
		"name_asc":
			sorted.sort_custom(func(a, b): return String(a[0]).naturalnocasecmp_to(String(b[0])) < 0)
		"name_desc":
			sorted.sort_custom(func(a, b): return String(a[0]).naturalnocasecmp_to(String(b[0])) > 0)
		_:
			sorted.sort_custom(func(a, b): return float(a[1]) > float(b[1]))
	return sorted


func _graph_button(graph: Dictionary) -> Button:
	var button := Button.new()
	button.text = "▤"
	button.flat = true
	_tint(button, C_COUNT)
	button.tooltip_text = "Graph: %s" % graph["title"]
	var data: Callable = graph["data"]
	button.pressed.connect(func(): _show_graph(graph, data.call()))
	return button


func _ranked_from_counts(counts: Dictionary) -> Array:
	var entries := []
	for key in counts.keys():
		entries.append([str(key), float(counts[key])])
	entries.sort_custom(func(a, b): return a[1] > b[1])
	if entries.size() > RANKED_LIMIT:
		entries = entries.slice(0, RANKED_LIMIT)
	return entries


func _rebuild_content() -> void:
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()

	if not _loaded:
		return

	match _view:
		"overview":
			_build_overview()
		"items":
			_build_items()
		"distribution":
			_build_distribution()
		"samples":
			_build_per_sample()
		"raw":
			_build_raw()


func _scroll_body() -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 4)
	scroll.add_child(body)
	_content.add_child(scroll)
	return body


func _heading(parent: Node, text: String) -> void:
	var label := Label.new()
	label.text = text
	_tint(label, C_LABEL)
	parent.add_child(label)


func _field(parent: Node, key: String, value: String, graph: Dictionary = {}, color: Color = C_VALUE) -> void:
	var row := HBoxContainer.new()

	var key_label := Label.new()
	key_label.text = key
	key_label.custom_minimum_size = Vector2(190, 0)
	_tint(key_label, C_LABEL)
	row.add_child(key_label)

	var value_label := Label.new()
	value_label.text = value
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tint(value_label, color)
	row.add_child(value_label)

	if not graph.is_empty():
		row.add_child(_graph_button(graph))

	parent.add_child(row)


func _section(parent: Node, title: String, key: String, graph: Dictionary = {}) -> VBoxContainer:
	var open: bool = not _collapsed.get(key, false)

	var header_row := HBoxContainer.new()

	var header := Button.new()
	header.flat = true
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_font_size_override("font_size", 15)
	header.text = ("▾  " if open else "▸  ") + title
	_tint(header, C_SECTION)
	header_row.add_child(header)

	if not graph.is_empty():
		header_row.add_child(_graph_button(graph))

	parent.add_child(header_row)

	var indent := MarginContainer.new()
	indent.add_theme_constant_override("margin_left", 10)
	indent.visible = open
	parent.add_child(indent)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 2)
	indent.add_child(body)

	header.pressed.connect(func():
		var now_open := not indent.visible
		indent.visible = now_open
		_collapsed[key] = not now_open
		header.text = ("▾  " if now_open else "▸  ") + title
	)
	return body


func _build_overview() -> void:
	var body := _scroll_body()
	var agg: Dictionary = _header.get("aggregate", {})
	var samples: int = agg.get("samples", 0)
	var averages: Dictionary = SamplerStats.sample_averages(agg)
	var entry_stats: Dictionary = SamplerStats.histogram_stats(agg.get("size_entry_hist", {}))
	var unit_stats: Dictionary = SamplerStats.histogram_stats(agg.get("size_unit_hist", {}))

	var config := _section(body, "Configuration", "overview/config")
	_field(config, "Table", _header.get("table_path", ""), {}, C_DIM)
	if not String(_header.get("dict_name", "")).is_empty():
		_field(config, "Dictionary", _header.get("dict_name", ""), {}, C_DIM)
	_field(config, "Pack prefix", _header.get("prefix", ""), {}, C_ITEM)
	_field(config, "Start items", " → ".join(_header.get("start_items", [])), {}, C_ITEM)
	_field(config, "Stacking", _stacking_name(int(_header.get("stacking", 0))), {}, C_DIM)
	_field(config, "Samples", str(samples), {}, C_COUNT)
	_field(config, "Ran", _header.get("created", ""), {}, C_DIM)

	var shape := _section(body, "Sample Shape", "overview/shape")
	_field(shape, "Distinct items seen", str(agg.get("samples_containing", {}).size()), {}, C_COUNT)
	_field(shape, "Empty samples", "%d  (%.2f%%)" % [
		agg.get("empty_samples", 0),
		100.0 * agg.get("empty_samples", 0) / samples if samples > 0 else 0.0,
	], {}, C_RATE)
	_field(shape, "Items per sample", "avg %.2f    range %d-%d    σ %.2f" % [
		averages["entries"], entry_stats["min"], entry_stats["max"], entry_stats["stddev"],
	], {
		"title": "Items per Sample",
		"subtitle": "How many item entries a sample contained, across %d samples." % samples,
		"kind": "histogram",
		"x_label": "Items in a sample",
		"data": func(): return SamplerStats.histogram_pairs(agg.get("size_entry_hist", {})),
	}, C_COUNT)
	_field(shape, "Amount per sample", "avg %.2f    range %d-%d    σ %.2f" % [
		averages["units"], unit_stats["min"], unit_stats["max"], unit_stats["stddev"],
	], {
		"title": "Amount per Sample",
		"subtitle": "Total units a sample contained, across %d samples." % samples,
		"kind": "histogram",
		"x_label": "Units in a sample",
		"data": func(): return SamplerStats.histogram_pairs(agg.get("size_unit_hist", {})),
	}, C_COUNT)

	var counts: Dictionary = SamplerStats.aggregate_counts(agg)
	for label in counts.keys():
		var category_counts: Dictionary = counts[label]
		var block := _section(body, label, "overview/stats/%s" % label, {
			"title": label,
			"subtitle": "%s per item, ranked. Mean, mode and median below all read off this." % label,
			"kind": "ranked",
			"x_label": label,
			"data": func(): return _ranked_from_counts(category_counts),
		})
		_add_stat_block(block, category_counts)


func _stacking_name(mode: int) -> String:
	match mode:
		0: return "0 - No stacking"
		1: return "1 - Drop stacking"
		2: return "2 - Pack stacking"
		3: return "3 - Full stacking"
	return str(mode)


func _add_stat_block(parent: Node, counts: Dictionary) -> void:
	var mmm: Dictionary = SamplerStats.mean_mode_median(counts)
	var rs: Dictionary = SamplerStats.range_and_stddev(counts)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)

	_stat_field(box, "    Mean", mmm["mean_count"], mmm["mean"])
	_stat_field(box, "    Mode", mmm["mode_count"], mmm["mode"])
	if mmm["median_tied"]:
		_stat_field(box, "    Median", mmm["median_down_count"], mmm["median_down"])
	else:
		_stat_field(box, "    Median ↓", mmm["median_down_count"], mmm["median_down"])
		_stat_field(box, "    Median ↑", mmm["median_up_count"], mmm["median_up"])
	_field(box, "    Std Dev", "%.2f" % rs["stddev"], {}, C_COUNT)
	_field(box, "    Range", "%d-%d  (%d)" % [rs["min"], rs["max"], rs["spread"]], {}, C_COUNT)
	parent.add_child(box)


func _stat_field(parent: Node, key: String, count: int, items: Array) -> void:
	var row := HBoxContainer.new()

	var key_label := Label.new()
	key_label.text = key
	key_label.custom_minimum_size = Vector2(190, 0)
	_tint(key_label, C_LABEL)
	row.add_child(key_label)

	var count_label := Label.new()
	count_label.text = str(count)
	count_label.custom_minimum_size = Vector2(46, 0)
	_tint(count_label, C_COUNT)
	row.add_child(count_label)

	var items_label := Label.new()
	items_label.text = " | ".join(items)
	items_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tint(items_label, C_ITEM)
	row.add_child(items_label)

	parent.add_child(row)


func _build_items() -> void:
	var controls := HBoxContainer.new()

	var filter_label := Label.new()
	filter_label.text = "Filter"
	controls.add_child(filter_label)

	var filter_edit := LineEdit.new()
	filter_edit.text = _item_filter
	filter_edit.placeholder_text = "item name"
	filter_edit.custom_minimum_size = Vector2(140, 0)
	filter_edit.text_changed.connect(func(t):
		_item_filter = t
		_refresh_item_rows()
	)
	controls.add_child(filter_edit)

	controls.add_child(VSeparator.new())

	var metric_label := Label.new()
	metric_label.text = ""
	controls.add_child(metric_label)

	var metric_option := OptionButton.new()
	for i in range(METRICS.size()):
		metric_option.add_item(METRICS[i]["name"], i)
		if METRICS[i]["key"] == _metric:
			metric_option.select(i)
	metric_option.item_selected.connect(func(index):
		_metric = METRICS[index]["key"]
		_refresh_item_rows()
	)
	controls.add_child(metric_option)

	controls.add_child(VSeparator.new())

	var sort_label := Label.new()
	sort_label.text = "Order"
	controls.add_child(sort_label)

	var sort_option := OptionButton.new()
	for i in range(SORT_MODES.size()):
		sort_option.add_item(SORT_MODES[i]["name"], i)
		if SORT_MODES[i]["key"] == _item_sort:
			sort_option.select(i)
	sort_option.item_selected.connect(func(index):
		_item_sort = SORT_MODES[index]["key"]
		_refresh_item_rows()
	)
	controls.add_child(sort_option)

	controls.add_child(_graph_button({
		"title": "Item Ranking",
		"subtitle": "Every item currently listed, by the chosen metric.",
		"kind": "ranked",
		"x_label": _metric_name(_metric),
		"data": func(): return _ranked_items(),
	}))

	_content.add_child(controls)
	_refresh_item_rows()


func _metric_name(key: String) -> String:
	for metric in METRICS:
		if metric["key"] == key:
			return metric["name"]
	return key


func _ranked_items() -> Array:
	var entries := []
	for row in _visible_item_rows():
		entries.append([row["item"], float(row[_metric])])
	if entries.size() > RANKED_LIMIT:
		entries = entries.slice(0, RANKED_LIMIT)
	return entries


func _visible_item_rows() -> Array:
	var rows: Array = SamplerStats.item_rows(_header.get("aggregate", {}))
	var metric := _metric
	match _item_sort:
		"value_asc":
			rows.sort_custom(func(a, b): return a[metric] < b[metric])
		"name_asc":
			rows.sort_custom(func(a, b): return String(a["item"]).naturalnocasecmp_to(String(b["item"])) < 0)
		"name_desc":
			rows.sort_custom(func(a, b): return String(a["item"]).naturalnocasecmp_to(String(b["item"])) > 0)
		_:
			rows.sort_custom(func(a, b): return a[metric] > b[metric])

	var needle := _item_filter.to_lower()
	if needle.is_empty():
		return rows

	var shown := []
	for row in rows:
		if String(row["item"]).to_lower().contains(needle):
			shown.append(row)
	return shown


func _refresh_item_rows() -> void:
	while _content.get_child_count() > 1:
		var child := _content.get_child(1)
		_content.remove_child(child)
		child.queue_free()

	var body := _scroll_body()
	var shown := _visible_item_rows()

	if shown.is_empty():
		var empty := Label.new()
		empty.text = "(no items match)" if not _item_filter.is_empty() else "(no items were drawn)"
		_tint(empty, C_MUTED)
		body.add_child(empty)
		return

	var max_value := 0.0
	for row in shown:
		max_value = max(max_value, float(row[_metric]))

	var is_pct := true
	for metric_data in METRICS:
		if metric_data["key"] == _metric:
			is_pct = metric_data["pct"]

	for row in shown:
		body.add_child(_build_item_row(row, _metric, is_pct, max_value))


func _build_item_row(row: Dictionary, metric: String, is_pct: bool, max_value: float) -> Control:
	var panel := HBoxContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var name_button := Button.new()
	name_button.text = row["item"]
	name_button.flat = true
	name_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_button.custom_minimum_size = Vector2(170, 0)
	name_button.tooltip_text = "Drawn in %d samples  |  %d draws  |  %d total amount" % [
		row["in_samples"], row["draws"], row["units"],
	]
	name_button.pressed.connect(func(): item_clicked.emit(test_name, row["item"]))
	_tint(name_button, C_ITEM)
	panel.add_child(name_button)

	var bar := Bar.new()
	bar.ratio = float(row[metric]) / max_value if max_value > 0.0 else 0.0
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.custom_minimum_size = Vector2(60, 18)
	panel.add_child(bar)

	var value_label := Label.new()
	value_label.text = ("%6.2f%%" % row[metric]) if is_pct else ("%7.3f" % row[metric])
	value_label.custom_minimum_size = Vector2(76, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_tint(value_label, C_RATE if is_pct else C_COUNT)
	panel.add_child(value_label)

	var agg: Dictionary = _header.get("aggregate", {})
	var samples: int = agg.get("samples", 0)
	var item: String = row["item"]
	var in_samples: int = row["in_samples"]

	panel.add_child(_graph_button({
		"title": "%s — Amount per sample" % item,
		"subtitle": "How much of this item a sample held, zero included.",
		"kind": "histogram",
		"x_label": "Amount in a sample",
		"data": func(): return SamplerStats.histogram_pairs(
			_with_zero_bucket(agg.get("unit_hist", {}).get(item, {}), samples, in_samples)
		),
	}))

	return panel


func _build_distribution() -> void:
	var agg: Dictionary = _header.get("aggregate", {})
	var items: Array = agg.get("samples_containing", {}).keys()
	items.sort()

	if items.is_empty():
		var empty := Label.new()
		empty.text = "(no items were drawn)"
		_tint(empty, C_MUTED)
		_content.add_child(empty)
		return

	if _detail_item.is_empty() or not items.has(_detail_item):
		_detail_item = items[0]

	var controls := HBoxContainer.new()
	var label := Label.new()
	label.text = "Item"
	controls.add_child(label)

	var option := OptionButton.new()
	for i in range(items.size()):
		option.add_item(items[i], i)
		if items[i] == _detail_item:
			option.select(i)
	option.item_selected.connect(func(index):
		_detail_item = items[index]
		_rebuild_content()
	)
	controls.add_child(option)
	_content.add_child(controls)

	var body := _scroll_body()
	var samples: int = agg.get("samples", 0)
	var in_samples: int = agg["samples_containing"].get(_detail_item, 0)
	var item: String = _detail_item

	var totals := _section(body, "Totals", "distribution/totals")
	_field(totals, "Appears in", "%d of %d samples  (%.2f%%)" % [
		in_samples, samples, 100.0 * in_samples / samples if samples > 0 else 0.0,
	], {}, C_RATE)
	_field(totals, "Total draws", str(agg["pooled_entry"].get(item, 0)), {}, C_COUNT)
	_field(totals, "Total amount", str(agg["pooled_unit"].get(item, 0)), {}, C_COUNT)
	_field(totals, "Avg amount when present", "%.2f" % (
		float(agg["pooled_unit"].get(item, 0)) / in_samples if in_samples > 0 else 0.0
	), {}, C_COUNT)

	var draw_stats: Dictionary = SamplerStats.histogram_stats(
		_with_zero_bucket(agg.get("entry_hist", {}).get(item, {}), samples, in_samples)
	)
	var amount_stats: Dictionary = SamplerStats.histogram_stats(
		_with_zero_bucket(agg.get("unit_hist", {}).get(item, {}), samples, in_samples)
	)

	var spread := _section(body, "Spread", "distribution/spread")
	_field(spread, "Draws per sample", "avg %.2f    range %d-%d    σ %.2f" % [
		draw_stats["mean"], draw_stats["min"], draw_stats["max"], draw_stats["stddev"],
	], {
		"title": "%s — Draws per sample" % item,
		"subtitle": "How many times this item was drawn in a sample, zero included.",
		"kind": "histogram",
		"x_label": "Draws in a sample",
		"data": func(): return SamplerStats.histogram_pairs(
			_with_zero_bucket(agg.get("entry_hist", {}).get(item, {}), samples, in_samples)
		),
	}, C_COUNT)
	_field(spread, "Amount per sample", "avg %.2f    range %d-%d    σ %.2f" % [
		amount_stats["mean"], amount_stats["min"], amount_stats["max"], amount_stats["stddev"],
	], {
		"title": "%s — Amount per sample" % item,
		"subtitle": "How much of this item a sample held, zero included.",
		"kind": "histogram",
		"x_label": "Amount in a sample",
		"data": func(): return SamplerStats.histogram_pairs(
			_with_zero_bucket(agg.get("unit_hist", {}).get(item, {}), samples, in_samples)
		),
	}, C_COUNT)


func _with_zero_bucket(hist: Dictionary, samples: int, in_samples: int) -> Dictionary:
	var out := hist.duplicate()
	var absent := samples - in_samples
	if absent > 0:
		out[0] = out.get(0, 0) + absent
	return out


func _build_per_sample() -> void:
	var agg: Dictionary = _header.get("aggregate", {})
	var samples: int = agg.get("samples", 0)
	_content.add_child(_build_pager(samples))

	var page: Array = SamplerIO.load_raw_page(test_name, _page * _page_size, _page_size)
	var body := _scroll_body()

	if page.is_empty():
		var empty := Label.new()
		empty.text = "(no raw samples stored for this test)"
		_tint(empty, C_MUTED)
		body.add_child(empty)
		return

	for i in range(page.size()):
		var pairs: Array = SamplerStats.normalize_sample(page[i])
		var entry_counts := {}
		var unit_counts := {}
		for pair in pairs:
			entry_counts[pair[0]] = entry_counts.get(pair[0], 0) + 1
			unit_counts[pair[0]] = unit_counts.get(pair[0], 0) + pair[1]

		var index := _page * _page_size + i + 1
		var sample_body := _section(body, "Sample %d" % index, "samples/%d" % index, {
			"title": "Sample %d" % index,
			"subtitle": "Amount of each item in this one sample.",
			"kind": "ranked",
			"x_label": "Amount",
			"data": func(): return _ranked_from_counts(unit_counts),
		})
		_heading(sample_body, "Appearance")
		_add_stat_block(sample_body, entry_counts)
		_heading(sample_body, "Amount")
		_add_stat_block(sample_body, unit_counts)


func _build_raw() -> void:
	var agg: Dictionary = _header.get("aggregate", {})
	var samples: int = agg.get("samples", 0)
	_content.add_child(_build_pager(samples))

	var page: Array = SamplerIO.load_raw_page(test_name, _page * _page_size, _page_size)
	var body := _scroll_body()

	if page.is_empty():
		var empty := Label.new()
		empty.text = "(no raw samples stored for this test)"
		_tint(empty, C_MUTED)
		body.add_child(empty)
		return

	for i in range(page.size()):
		var pairs: Array = SamplerStats.normalize_sample(page[i])
		var total := 0
		for pair in pairs:
			total += pair[1]

		var title_row := HBoxContainer.new()
		var title := Label.new()
		title.text = "Sample %d" % [_page * _page_size + i + 1]
		_tint(title, C_TITLE)
		title_row.add_child(title)

		var title_count := Label.new()
		title_count.text = "%d items  (%d total)" % [pairs.size(), total]
		_tint(title_count, C_COUNT)
		title_row.add_child(title_count)
		body.add_child(title_row)

		if pairs.is_empty():
			var none := Label.new()
			none.text = "    (no items)"
			_tint(none, C_MUTED)
			body.add_child(none)
			continue

		for pair in pairs:
			var line := HBoxContainer.new()

			var item_label := Label.new()
			item_label.text = "    %s" % pair[0]
			item_label.custom_minimum_size = Vector2(220, 0)
			_tint(item_label, C_ITEM)
			line.add_child(item_label)

			var amount_label := Label.new()
			amount_label.text = "x%d" % pair[1]
			_tint(amount_label, C_COUNT)
			line.add_child(amount_label)

			body.add_child(line)


func _build_pager(total_samples: int) -> Control:
	var pages: int = max(1, int(ceil(float(total_samples) / _page_size)))
	_page = clampi(_page, 0, pages - 1)

	var bar := HBoxContainer.new()

	var prev := Button.new()
	prev.text = "◀"
	prev.tooltip_text = "Previous page. Wraps round to the last."
	prev.pressed.connect(func():
		_page = posmod(_page - 1, pages)
		_rebuild_content()
	)
	bar.add_child(prev)

	bar.add_child(_build_page_picker(pages, total_samples))

	var next := Button.new()
	next.text = "▶"
	next.tooltip_text = "Next page. Wraps round to the first."
	next.pressed.connect(func():
		_page = posmod(_page + 1, pages)
		_rebuild_content()
	)
	bar.add_child(next)

	bar.add_child(VSeparator.new())

	var size_label := Label.new()
	size_label.text = "Per page"
	_tint(size_label, C_LABEL)
	bar.add_child(size_label)

	var size_spin := SpinBox.new()
	size_spin.min_value = 1
	size_spin.max_value = 1000
	size_spin.value = _page_size
	size_spin.tooltip_text = "How many samples to show on one page."
	size_spin.value_changed.connect(func(value):
		var first: int = _page * _page_size
		_page_size = max(1, int(value))
		_page = int(floor(float(first) / _page_size))
		call_deferred("_rebuild_content")
	)
	bar.add_child(size_spin)

	return bar


func _build_page_picker(pages: int, total_samples: int) -> Control:
	if pages > PAGE_MENU_LIMIT:
		var box := HBoxContainer.new()

		var jump := SpinBox.new()
		jump.min_value = 1
		jump.max_value = pages
		jump.value = _page + 1
		jump.prefix = "Page"
		jump.tooltip_text = "Jump to a page."
		jump.value_changed.connect(func(value):
			_page = clampi(int(value) - 1, 0, pages - 1)
			call_deferred("_rebuild_content")
		)
		box.add_child(jump)

		var label := Label.new()
		label.text = _page_range_text(_page, total_samples)
		_tint(label, C_COUNT)
		box.add_child(label)
		return box

	var option := OptionButton.new()
	option.tooltip_text = "Jump to a page."
	for i in range(pages):
		option.add_item(_page_range_text(i, total_samples), i)
	option.select(_page)
	_tint(option, C_COUNT)
	option.item_selected.connect(func(index):
		_page = index
		call_deferred("_rebuild_content")
	)
	return option


func _page_range_text(page: int, total_samples: int) -> String:
	return "Samples %d-%d of %d" % [
		page * _page_size + 1,
		min((page + 1) * _page_size, total_samples),
		total_samples,
	]


class Bar extends Control:
	var ratio: float = 0.0

	func _draw() -> void:
		var fill := Color(0.4, 0.72, 1.0)
		if has_theme_color("accent_color", "Editor"):
			fill = get_theme_color("accent_color", "Editor")
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.07))
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * clampf(ratio, 0.0, 1.0), size.y)), fill)


class Histogram extends Control:
	const TICKS := 4

	var pairs: Array = []
	var x_label: String = ""
	var y_label: String = "samples"
	var label_color: Color = Color(0.72, 0.76, 0.84)
	var peak_color: Color = Color(0.97, 0.84, 0.45)
	var axis_color: Color = Color(0.72, 0.76, 0.84)
	var y_axis_color: Color = Color(0.95, 0.96, 0.98)

	func _draw() -> void:
		if pairs.is_empty():
			return

		var font := get_theme_font("font", "Label")
		var font_size := get_theme_font_size("font_size", "Label")
		var fill := Color(0.4, 0.72, 1.0)
		if has_theme_color("accent_color", "Editor"):
			fill = get_theme_color("accent_color", "Editor")

		var max_count := 0
		for pair in pairs:
			max_count = max(max_count, pair[1])
		if max_count <= 0:
			return

		var gutter := 0.0
		for i in range(TICKS + 1):
			var tick_text := str(int(round(max_count * float(i) / TICKS)))
			gutter = max(gutter, font.get_string_size(tick_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
		gutter += 6.0

		var header := font_size + 4.0
		var footer := (font_size + 4.0) * 2.0
		var plot_top := header
		var plot_bottom: float = max(plot_top + 10.0, size.y - footer)
		var plot_height := plot_bottom - plot_top - 16
		var plot_width: float = max(10.0, size.x - gutter)

		draw_string(font, Vector2(0, font_size), y_label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, y_axis_color)

		for i in range(TICKS + 1):
			var fraction := float(i) / TICKS
			var y := plot_bottom - plot_height * fraction
			var value := int(round(max_count * fraction))
			draw_line(Vector2(gutter, y), Vector2(size.x, y), Color(1, 1, 1, 0.12 if i > 0 else 0.25), 1.0)
			draw_string(font, Vector2(0, y + font_size * 0.35), str(value), HORIZONTAL_ALIGNMENT_RIGHT,
					gutter - 4.0, font_size, y_axis_color)

		var slot: float = plot_width / pairs.size()
		var bar_width: float = max(1.0, slot - 2.0)
		var peak_index := 0
		for i in range(pairs.size()):
			var height: float = plot_height * pairs[i][1] / max_count
			draw_rect(Rect2(Vector2(gutter + i * slot, plot_bottom - height), Vector2(bar_width, height)), fill)
			if pairs[i][1] > pairs[peak_index][1]:
				peak_index = i

		var baseline := plot_bottom + font_size + 2.0
		for i in {0: true, pairs.size() - 1: true, peak_index: true}.keys():
			var text := str(pairs[i][0])
			var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			var x: float = clampf(gutter + i * slot + bar_width * 0.5 - width * 0.5, gutter, size.x - width)
			draw_string(font, Vector2(x, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, label_color)

		if not x_label.is_empty():
			draw_string(font, Vector2(gutter, baseline + font_size + 2.0), x_label,
					HORIZONTAL_ALIGNMENT_CENTER, plot_width, font_size, axis_color)

		var peak_text := "Peak: %d at %d" % [pairs[peak_index][1], pairs[peak_index][0]]
		draw_string(font, Vector2(gutter + 4.0, font_size), peak_text, HORIZONTAL_ALIGNMENT_RIGHT,
				plot_width - 4.0, font_size, peak_color)


class RankedChart extends Control:
	const ROW_HEIGHT := 18.0
	const LABEL_WIDTH := 130.0
	const HEADER_HEIGHT := 20.0

	var entries: Array = []
	var x_label: String = ""
	var y_label: String = "item"
	var label_color: Color = Color(0.97, 0.84, 0.45)
	var value_color: Color = Color(0.44, 0.84, 0.95)
	var axis_color: Color = Color(0.72, 0.76, 0.84)
	var y_axis_color: Color = Color(0.95, 0.96, 0.98)

	static func _sig(value: float, digits: int = 4) -> String:
		if value == 0.0:
			return "0"
		var magnitude: int = int(floor(log(absf(value)) / log(10.0)))
		var decimals: int = clampi(digits - 1 - magnitude, 0, 12)
		var text := String.num(value, decimals)
		if text.contains("."):
			text = text.rstrip("0").rstrip(".")
		return text

	func _draw() -> void:
		if entries.is_empty():
			return

		var font := get_theme_font("font", "Label")
		var font_size := get_theme_font_size("font_size", "Label")
		var fill := Color(0.4, 0.72, 1.0)
		if has_theme_color("accent_color", "Editor"):
			fill = get_theme_color("accent_color", "Editor")

		var max_value := 0.0
		for entry in entries:
			max_value = max(max_value, float(entry[1]))
		if max_value <= 0.0:
			return

		var label_width: float = min(LABEL_WIDTH, size.x * 0.45)
		var value_width := 56.0
		var track_width: float = max(10.0, size.x - label_width - value_width - 8.0)
		var baseline_offset := (ROW_HEIGHT + font_size) * 0.5 - 2.0

		draw_string(font, Vector2(0, font_size), y_label, HORIZONTAL_ALIGNMENT_LEFT,
				label_width - 4.0, font_size, y_axis_color)
		if not x_label.is_empty():
			draw_string(font, Vector2(label_width, font_size), x_label, HORIZONTAL_ALIGNMENT_LEFT,
					track_width, font_size, axis_color)
		draw_string(font, Vector2(label_width + track_width + 4.0, font_size), _sig(max_value),
				HORIZONTAL_ALIGNMENT_RIGHT, value_width, font_size, axis_color)
		draw_line(Vector2(label_width, HEADER_HEIGHT - 3.0),
				Vector2(label_width + track_width, HEADER_HEIGHT - 3.0), Color(1, 1, 1, 0.25), 1.0)

		for i in range(entries.size()):
			var y: float = HEADER_HEIGHT + i * ROW_HEIGHT
			var value := float(entries[i][1])

			draw_string(font, Vector2(0, y + baseline_offset), str(entries[i][0]), HORIZONTAL_ALIGNMENT_LEFT,
					label_width - 4.0, font_size, label_color)

			var track := Rect2(Vector2(label_width, y + 3), Vector2(track_width, ROW_HEIGHT - 6))
			draw_rect(track, Color(1, 1, 1, 0.07))
			draw_rect(Rect2(track.position, Vector2(track_width * value / max_value, track.size.y)), fill)

			var value_text := ("%.2f" % value) if value != floor(value) else str(int(value))
			draw_string(font, Vector2(label_width + track_width + 4.0, y + baseline_offset), value_text,
					HORIZONTAL_ALIGNMENT_RIGHT, value_width, font_size, value_color)