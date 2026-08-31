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


const CandyLootGraphEdit = preload("res://addons/Candy_Tools/tools/candy_loot/candy_loot_graph_edit.gd")
const CandyLootTableIO = preload("res://addons/Candy_Tools/tools/candy_loot/candy_loot_table_io.gd")

var undo_redo: EditorUndoRedoManager = null

var _graph: Control
var _path_label: Label
var _save_button: Button
var _prefix_edit: LineEdit
var _levels_spin: SpinBox

var _table_path: String = ""
var _has_table: bool = false
var _dirty: bool = false


func _init() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_chrome()


func _build_chrome() -> void:
	var header := HBoxContainer.new()

	var new_button := Button.new()
	new_button.text = "New Table"
	new_button.pressed.connect(_on_new_pressed)
	header.add_child(new_button)

	var open_button := Button.new()
	open_button.text = "Open"
	open_button.pressed.connect(_on_open_pressed)
	header.add_child(open_button)

	_save_button = Button.new()
	_save_button.text = "Save"
	_save_button.disabled = true
	_save_button.pressed.connect(_on_save_pressed)
	header.add_child(_save_button)

	var save_as_button := Button.new()
	save_as_button.text = "Save As"
	save_as_button.pressed.connect(_on_save_as_pressed)
	header.add_child(save_as_button)

	header.add_child(VSeparator.new())

	var prefix_label := Label.new()
	prefix_label.text = "Pack prefix"
	header.add_child(prefix_label)

	_prefix_edit = LineEdit.new()
	_prefix_edit.text = CandyLootTableIO.DEFAULT_PREFIX
	_prefix_edit.custom_minimum_size = Vector2(48, 0)
	_prefix_edit.tooltip_text = "Must match Candy Loot's pack_prefix, or Packs\nwon't be recognised as Packs at runtime."
	_prefix_edit.caret_blink = true
	_prefix_edit.text_submitted.connect(func(t): _on_prefix_changed(t))
	_prefix_edit.focus_exited.connect(func(): _on_prefix_changed(_prefix_edit.text))
	header.add_child(_prefix_edit)

	header.add_child(VSeparator.new())

	var levels_label := Label.new()
	levels_label.text = "Highlight levels"
	header.add_child(levels_label)

	_levels_spin = SpinBox.new()
	_levels_spin.min_value = 1
	_levels_spin.max_value = 20
	_levels_spin.step = 1
	_levels_spin.value = 3
	_levels_spin.tooltip_text = "How many levels of nested packs get highlighted.\nBrightness is divided across the levels."
	_levels_spin.value_changed.connect(_on_levels_changed)
	header.add_child(_levels_spin)

	header.add_child(VSeparator.new())

	_path_label = Label.new()
	_path_label.text = "No table loaded"
	_path_label.modulate = Color(1, 1, 1, 0.6)
	header.add_child(_path_label)

	add_child(header)

	_graph = CandyLootGraphEdit.new()
	_graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_graph.model_changed.connect(_on_model_changed)
	add_child(_graph)


func _ready() -> void:
	_graph.undo_redo = undo_redo
	_graph.highlight_levels = int(_levels_spin.value)


func _on_levels_changed(value: float) -> void:
	_graph.highlight_levels = int(value)


func _on_model_changed() -> void:
	_dirty = true
	_refresh_path_label()


func _on_prefix_changed(value: String) -> void:
	if value == "" or value == _graph.prefix:
		return
	_graph.set_prefix(value)
	_dirty = true
	_refresh_path_label()


func _refresh_path_label() -> void:
	var base := _table_path if _table_path != "" else "New table (unsaved)"
	_path_label.text = "%s%s" % [base, " *" if _dirty else ""]


func _on_new_pressed() -> void:
	_table_path = ""
	_has_table = true
	_dirty = false
	_prefix_edit.text = CandyLootTableIO.DEFAULT_PREFIX
	_graph.set_model([], CandyLootTableIO.DEFAULT_PREFIX, true)
	_save_button.disabled = true
	_refresh_path_label()


func _on_open_pressed() -> void:
	var dialog := _make_dialog(EditorFileDialog.FILE_MODE_OPEN_FILE)
	dialog.file_selected.connect(_on_open_selected)
	dialog.popup_centered_ratio(0.6)


func _on_open_selected(path: String) -> void:
	var result := CandyLootTableIO.load_table(path)
	if result.is_empty():
		push_error("Candy Tools: %s is not a Candy Loot table file." % path)
		return
	_table_path = path
	_has_table = true
	_dirty = false
	_prefix_edit.text = result["prefix"]
	_graph.set_model(result["model"], result["prefix"], true)
	_save_button.disabled = false
	_refresh_path_label()


func _on_save_pressed() -> void:
	if _table_path == "":
		_on_save_as_pressed()
		return
	_write(_table_path)


func _on_save_as_pressed() -> void:
	if not _has_table:
		push_warning("Candy Tools: create or open a table first.")
		return
	var dialog := _make_dialog(EditorFileDialog.FILE_MODE_SAVE_FILE)
	dialog.current_file = "loot_table.tres"
	dialog.file_selected.connect(_write)
	dialog.popup_centered_ratio(0.6)


func _make_dialog(mode: int) -> EditorFileDialog:
	var dialog := EditorFileDialog.new()
	dialog.file_mode = mode
	dialog.access = EditorFileDialog.ACCESS_RESOURCES
	dialog.add_filter("*.tres", "Text Resource")
	dialog.add_filter("*.res", "Binary Resource")
	dialog.close_requested.connect(dialog.queue_free)
	EditorInterface.get_base_control().add_child(dialog)
	return dialog


func _write(path: String) -> void:
	var result := CandyLootTableIO.save_table(_graph.model, _graph.prefix, path)
	if result != OK:
		push_error("Candy Tools: failed to save %s (error %d)" % [path, result])
		return
	_table_path = path
	_dirty = false
	_save_button.disabled = false
	_refresh_path_label()
	EditorInterface.get_resource_filesystem().scan()