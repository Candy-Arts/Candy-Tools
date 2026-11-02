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

#? The Candy Database tool's panel: installs and updates Candy Database from its latest GitHub release,
#? and downloads every database of Candy Arts' documentation into it.
#? A port of Candy Wizard's Docs tool, listing every database in one card.

const Utils = preload("candy_database_utils.gd")
const Style = preload("res://addons/Candy_Tools/shared/candy_tools_style.gd")
const DatabaseInstaller = preload("candy_database_installer.gd")
const DocsFiles = preload("candy_docs_files.gd")

#^ Something to update was found or done - the host updates the tool's drop-down entry:
signal attention_changed

#^ Locally changed files the confirmation lists by name:
const LISTED_FILES := 8

var undo_redo: EditorUndoRedoManager = null	#/ Set by the descriptor, unused

var database_icon: TextureRect
var database_label: Label
var database_button: Button
var progress_bar: ProgressBar
var result_text: RichTextLabel
var docs_note: Label
var docs_grid: GridContainer
var docs_rows: Dictionary = {}		#/ Set id -> {"icon", "label", "button"}
var listed_sets: PackedStringArray = []	#/ What docs_grid shows - "id\ntitle" each

var busy := false
var checking := false
var database_button_checks := false


func _ready() -> void:
	add_theme_constant_override("separation", Style.px(8))
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", Style.px(8))
	cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(cards)

	#@ Candy Database:
	var box := Style.card(cards, "Help", "Candy Database", "The documentation browser, from its GitHub releases.")
	box.get_parent().custom_minimum_size.x = Style.px(300)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Style.px(6))
	box.add_child(row)
	database_icon = Style.icon_rect()
	row.add_child(database_icon)
	database_label = Label.new()
	database_label.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(database_label)
	progress_bar = ProgressBar.new()
	progress_bar.max_value = 1.0
	progress_bar.step = 0.001
	progress_bar.visible = false
	box.add_child(progress_bar)
	result_text = RichTextLabel.new()
	result_text.bbcode_enabled = true
	result_text.fit_content = true
	result_text.scroll_active = false
	result_text.selection_enabled = true
	result_text.custom_minimum_size.x = Style.px(280)
	result_text.visible = false
	result_text.meta_clicked.connect(_on_meta_clicked)
	box.add_child(result_text)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	database_button = Button.new()
	database_button.pressed.connect(_on_database_button)
	box.add_child(database_button)

	#@ Documentation:
	var docs_box := Style.card(cards, "HelpSearch", "Documentation", "Candy Arts' databases on GitHub, downloaded into Candy Database.")
	docs_box.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	docs_note = Label.new()
	docs_note.modulate = Color(1, 1, 1, 0.6)
	docs_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	docs_box.add_child(docs_note)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	docs_box.add_child(scroll)
	docs_grid = GridContainer.new()
	docs_grid.columns = 4	#/ Title, status icon, status, button
	docs_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	docs_grid.add_theme_constant_override("h_separation", Style.px(8))
	docs_grid.add_theme_constant_override("v_separation", Style.px(4))
	scroll.add_child(docs_grid)

	refresh()


func _enter_tree() -> void:
	var file_system := EditorInterface.get_resource_filesystem()
	if not file_system.filesystem_changed.is_connected(refresh):
		file_system.filesystem_changed.connect(refresh)
	#? The host adds the view each time the tool is chosen: look on GitHub if it's been a day.
	_auto_check.call_deferred()


func _exit_tree() -> void:
	var file_system := EditorInterface.get_resource_filesystem()
	if file_system.filesystem_changed.is_connected(refresh):
		file_system.filesystem_changed.disconnect(refresh)


func _auto_check() -> void:
	if is_inside_tree():
		refresh()
		check(false)


#==============================================================================
#  STATUS
#==============================================================================

#* Show what's installed and downloaded, and what GitHub had at the last look:
func refresh() -> void:
	if result_text == null:
		return
	var installed := Utils.installed_database_version()
	_refresh_database(installed)
	var record := Utils.read_database_record()
	var zips = Utils.last_check(Utils.SETTING_DOCS).get("zips", null)
	var sets := Utils.docs_sets()
	_sync_rows(sets)
	if installed == "":
		docs_note.text = "Install Candy Database first: the documentation goes in its folder."
	elif sets.is_empty():
		docs_note.text = "None found yet. Press Check for Updates to look on GitHub."
	else:
		docs_note.text = ""
	docs_note.visible = docs_note.text != ""
	for docs in sets:
		_refresh_docs(docs, record, zips, installed != "")


func _refresh_database(installed: String) -> void:
	database_button.disabled = busy or checking
	database_button.icon = Style.icon("AssetLib")
	database_button_checks = false
	database_label.tooltip_text = ""
	if Utils.is_database_dev_project():
		_set_status(database_icon, database_label, Style.icon("NodeInfo"), "Development project.", Style.dim())
		database_label.tooltip_text = "This is Candy Database's development project: its folder is the source, so it's never installed or updated here."
		_show_check_button()
		return
	var latest := String(Utils.last_check(Utils.SETTING_RELEASE).get("version", ""))
	if installed == "":
		_set_status(database_icon, database_label, Style.icon("StatusError"), "Not installed.", Style.color("font_color"))
		database_button.text = "Install Candy Database"
		database_button.tooltip_text = "Download Candy Database's latest release from GitHub, and install it in %s." % Utils.DATABASE_FOLDER
	elif latest != "" and Utils.compare_versions(latest, installed) > 0:
		_set_status(database_icon, database_label, Style.icon("StatusWarning"), "%s is out (%s here)." % [latest, installed], Style.color("warning_color"))
		database_button.text = "Update to %s" % latest
		database_button.icon = Style.icon("Reload")
		database_button.tooltip_text = "Update Candy Database to %s. The documentation and files of your own in its folder are kept." % latest
	else:
		if EditorInterface.is_plugin_enabled(Utils.DATABASE_FOLDER.get_file()):
			_set_status(database_icon, database_label, Style.icon("StatusSuccess"), "%s is installed." % installed, Style.color("font_color"))
		else:
			_set_status(database_icon, database_label, Style.icon("StatusWarning"), "%s is installed, but off." % installed, Style.color("warning_color"))
			database_label.tooltip_text = "Turn it on in Project > Project Settings > Plugins."
		_show_check_button()


func _show_check_button() -> void:
	database_button_checks = true
	database_button.text = "Check for Updates"
	database_button.icon = Style.icon("Reload")
	database_button.tooltip_text = "Look on GitHub now for a newer Candy Database and newer documentation."


func _on_database_button() -> void:
	if database_button_checks:
		check(true)
	else:
		_install_database()


#* Give each database a row, if the list changed:
func _sync_rows(sets: Array) -> void:
	var listed: PackedStringArray = []
	for docs in sets:
		listed.append("%s\n%s" % [docs["id"], docs["title"]])	#/ A new title remakes the rows too
	if listed == listed_sets:
		return
	listed_sets = listed
	docs_rows.clear()
	for child in docs_grid.get_children():
		docs_grid.remove_child(child)
		child.queue_free()
	for docs in sets:
		var title := Label.new()
		title.text = docs["title"]
		title.add_theme_font_override("font", Style.bold_font())
		title.custom_minimum_size.x = Style.px(170)
		docs_grid.add_child(title)
		var icon := Style.icon_rect()
		docs_grid.add_child(icon)
		var label := Label.new()
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		docs_grid.add_child(label)
		var button := Button.new()
		button.pressed.connect(_download_docs.bind(docs))
		docs_grid.add_child(button)
		docs_rows[docs["id"]] = {"icon": icon, "label": label, "button": button}


#? zips - the last look's {folder name: zip hash}, or null when GitHub wasn't looked at yet.
func _refresh_docs(docs: Dictionary, record: Dictionary, zips: Variant, installed: bool) -> void:
	var row: Dictionary = docs_rows[docs["id"]]
	var button: Button = row["button"]
	var label: Label = row["label"]
	button.disabled = busy or not installed
	button.icon = Style.icon("AssetLib")
	label.tooltip_text = ""
	var downloaded := Utils.docs_entry(docs, record)
	var on_github := "?"
	if zips is Dictionary:
		on_github = String(zips.get(docs["name"], ""))
	if downloaded.is_empty():
		_set_status(row["icon"], label, Style.icon("StatusError"), "Not downloaded.", Style.color("font_color"))
		button.text = "Download"
		button.tooltip_text = "Download this documentation from GitHub into %s." % Utils.DOCS_DATABASES_FOLDER
		return
	var date := Utils.readable_date(String(downloaded.get("date", "")))
	label.tooltip_text = "Downloaded %s." % date
	if on_github == "":
		_set_status(row["icon"], label, Style.icon("NodeInfo"), "No longer on GitHub.", Style.dim())
		button.text = "Download Again"
		button.disabled = true
		button.tooltip_text = "GitHub doesn't have this documentation anymore. What was downloaded stays."
	elif on_github != "?" and on_github != String(downloaded.get("zip_hash", "")):
		_set_status(row["icon"], label, Style.icon("StatusWarning"), "Updated on GitHub.", Style.color("warning_color"))
		button.text = "Update"
		button.icon = Style.icon("Reload")
		button.tooltip_text = "Download what changed on GitHub since %s." % date
	else:
		_set_status(row["icon"], label, Style.icon("StatusSuccess"), "Downloaded.", Style.color("font_color"))
		button.text = "Download Again"
		button.tooltip_text = "Download the files that are missing here or differ from GitHub's."


func _set_status(icon_rect: TextureRect, label: Label, icon: Texture2D, text: String, text_color: Color) -> void:
	icon_rect.texture = icon
	label.text = text
	label.add_theme_color_override("font_color", text_color)


#==============================================================================
#  LOOKING ON GITHUB
#==============================================================================


#* Look up Candy Database's latest release and the documentation's databases:
#? forced: now, showing the result; else at most once a day, quietly. Returns whether GitHub was asked.
func check(forced: bool) -> bool:
	if busy or checking or Utils.looking:
		return false
	checking = true
	refresh()
	if forced:
		_show_working("Looking on GitHub…")
	var problems = await Utils.look_on_github(self, forced)
	checking = false
	refresh()
	if problems == null:
		return false
	attention_changed.emit()
	if forced:
		_hide_progress()
		if problems.is_empty():
			_show("", [["StatusSuccess", "Checked GitHub.", Style.color("success_color")]])
		else:
			var lines := []
			for problem in problems:
				lines.append(["StatusWarning", Style.escaped(problem), Style.color("warning_color")])
			_show("", lines)
	return true


#==============================================================================
#  CANDY DATABASE
#==============================================================================

func _install_database() -> void:
	if busy:
		return
	_set_busy(true)
	_show_working("Looking for Candy Database's latest release…")
	var error: String = await _run_database_install()
	_set_busy(false)
	_hide_progress()
	if error != "":
		_show("Candy Database", [["StatusWarning", Style.escaped(error), Style.color("warning_color")]])


#* Download, check and install the latest release (asking before an update). Returns an error, or "":
func _run_database_install() -> String:
	var source := Utils.new_source(self)
	var latest: Dictionary = await Utils.fetch_latest_release(source)
	if latest.has("error"):
		source.queue_free()
		return latest["error"]
	var zip_path := Utils.TEMP_FOLDER.path_join(String(latest["asset_name"]))
	source.download_progress.connect(func(done: int, total: int) -> void:
		if total > 0:
			_show_progress(float(done) / total * 0.5, "Downloading Candy Database %s… %s / %s" % [latest["version"], Utils.readable_size(done), Utils.readable_size(total)]))
	var error: String = await source.download(String(latest["asset_url"]), zip_path)
	source.queue_free()
	if error != "":
		return error

	var package := Utils.database_package()
	error = package.open(zip_path)
	if error == "":
		error = package.verify()
	var installer := DatabaseInstaller.new()
	if error == "":
		installer.package = package
		installer.plan()
		error = installer.problem
	if error == "" and installer.installed_version != "":
		var question := "Update Candy Database %s to %s?\n\n%d of its files change, %d are added and %d removed. The documentation and the files of your own in its folder are kept.\n\nIts tab closes and opens again: save the page you're editing first." % [installer.installed_version, package.version(), installer.changed.size(), installer.added.size(), installer.removed.size()]
		if installer.unrecorded:
			question += "\n\nIt wasn't installed by Candy Tools or Candy Wizard, so files it no longer has can't be told apart from yours: none are removed."
		if not await Style.confirm(get_tree(), question, "Update"):
			package.close()
			DirAccess.remove_absolute(zip_path)
			_show("Candy Database", [["NodeInfo", "Update canceled.", Style.dim()]])
			return ""
	if error != "":
		package.close()
		DirAccess.remove_absolute(zip_path)
		return error

	installer.progress.connect(func(fraction: float, message: String) -> void: _show_progress(0.5 + fraction * 0.5, message))
	var updating := installer.installed_version != ""
	var version := package.version()
	error = await installer.install(get_tree())
	package.close()
	DirAccess.remove_absolute(zip_path)
	if error != "":
		return error
	var lines := []
	if updating:
		lines.append(["StatusSuccess", "Updated from %s." % installer.installed_version, Style.color("success_color")])
		if not installer.changed.is_empty() or not installer.removed.is_empty():
			lines.append(["Folder", "Previous files: %s." % _folder_link(installer.backup_folder), Style.dim()])
	else:
		lines.append(["StatusSuccess", "Installed: see the Candy DB tab.", Style.color("success_color")])
		lines.append(["Help", "Download its documentation on the right.", Style.dim()])
	_show("Candy Database %s" % version, lines)
	return ""


#==============================================================================
#  DOCUMENTATION
#==============================================================================

func _download_docs(docs: Dictionary) -> void:
	if busy:
		return
	var docs_name := "%s documentation" % docs["title"]
	_set_busy(true)
	_show_working("Looking at the %s on GitHub…" % docs_name)
	var error: String = await _run_docs_download(docs, docs_name)
	_set_busy(false)
	_hide_progress()
	if error != "":
		_show(docs_name, [["StatusWarning", Style.escaped(error), Style.color("warning_color")]])


#* Download a database (asking before replacing locally changed files). Returns an error, or "":
func _run_docs_download(docs: Dictionary, docs_name: String) -> String:
	var source := Utils.new_source(self)
	var tree: Dictionary = await Utils.fetch_docs_tree(source)
	if tree.has("error"):
		source.queue_free()
		return tree["error"]
	var files := DocsFiles.new()
	files.docs_set = docs
	files.tree = tree
	if files.is_current():
		source.queue_free()
		_show(docs_name, [["StatusSuccess", "Up to date.", Style.color("success_color")]])
		return ""
	_show_working("Downloading the %s…" % docs_name)
	await files.fetch(source)
	source.queue_free()
	if files.problem != "":
		return files.problem
	if not files.changed_here.is_empty():
		var question := "These files of the %s were changed in this project, and the download replaces or removes them:\n\n%s" % [docs_name, "\n".join(files.changed_here.slice(0, LISTED_FILES))]
		if files.changed_here.size() > LISTED_FILES:
			question += "\n…and %d more." % (files.changed_here.size() - LISTED_FILES)
		question += "\n\nA copy of each is kept first."
		if not await Style.confirm(get_tree(), question, "Replace Them"):
			_show(docs_name, [["NodeInfo", "Download canceled.", Style.dim()]])
			return ""

	_show_working("Writing the %s…" % docs_name)
	var error := files.apply()
	if not files.to_download.is_empty() or not files.to_remove.is_empty():
		_show_progress(1.0, "Loading the files…")
		await Utils.scan_filesystem(get_tree())
	if error != "":
		return error

	var lines := []
	if files.to_download.is_empty() and files.to_remove.is_empty():
		lines.append(["StatusSuccess", "Up to date.", Style.color("success_color")])
	else:
		var text := "Downloaded %d files" % files.to_download.size()
		if not files.to_remove.is_empty():
			text += ", removed %d" % files.to_remove.size()
		lines.append(["StatusSuccess", text + ".", Style.color("success_color")])
		lines.append(["Help", "Candy DB tab open? Choose Database > Refresh there.", Style.dim()])
	if files.backup_folder != "":
		lines.append(["Folder", "Your replaced files: %s." % _folder_link(files.backup_folder), Style.dim()])
	if not files.left_out.is_empty():
		lines.append(["NodeInfo", "Skipped: [code]%s[/code]." % Style.escaped(", ".join(files.left_out)), Style.dim()])
	_show(docs_name, lines)
	return ""


#==============================================================================
#  RESULT
#==============================================================================

func _set_busy(value: bool) -> void:
	busy = value
	refresh()
	if not busy:
		attention_changed.emit()


func _show_working(message: String) -> void:
	_show_progress(0.0, message)


func _show_progress(fraction: float, message: String) -> void:
	progress_bar.visible = true
	progress_bar.value = fraction
	result_text.visible = true
	result_text.clear()
	result_text.push_color(Style.dim())
	result_text.add_text(message)
	result_text.pop()


func _hide_progress() -> void:
	progress_bar.visible = false


#* Show a result. title - what it's about, or "". lines - [icon name, BBCode, color] each:
func _show(title: String, lines: Array) -> void:
	result_text.visible = true
	result_text.clear()
	if title != "":
		result_text.push_font(Style.bold_font())
		result_text.add_text(title)
		result_text.pop()
		result_text.newline()
	for line in lines:
		var icon := Style.icon(line[0])
		if icon != null:
			result_text.add_image(icon, Style.px(16), Style.px(16), line[2])
			result_text.add_text(" ")
		result_text.append_text(line[1])
		result_text.newline()


func _folder_link(path: String) -> String:
	return "[url=%s][code]%s[/code][/url]" % [path, Style.escaped(ProjectSettings.globalize_path(path))]


func _on_meta_clicked(meta: Variant) -> void:
	OS.shell_open(ProjectSettings.globalize_path(str(meta)))
