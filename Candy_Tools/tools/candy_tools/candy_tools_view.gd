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
extends HBoxContainer

#? The Candy Tools tool's panel: updates Candy Tools from its latest GitHub release, and shows Candy Arts' news.
#? Ports of Candy Wizard's self-update and News tool.

const Updates = preload("candy_tools_updates.gd")
const Updater = preload("candy_tools_updater.gd")
const News = preload("candy_news.gd")
const Style = preload("res://addons/Candy_Tools/shared/candy_tools_style.gd")

#^ An update was found or done, or news was read or downloaded - the host updates the drop-down entry:
signal attention_changed

const REFRESH_TEXT := "Refresh"
const CHECKING_TEXT := "Checking…"
const RESULT_SECONDS := 2.5
const RESULT_TEXTS := {
	News.Result.UPDATED: "Updated",
	News.Result.UNCHANGED: "Up to date",
	News.Result.FAILED: "Couldn't refresh",
}
const PARTLY_TEXT := "Partly refreshed"
const REFRESH_TOOLTIP := "Look for news now, on Candy Arts' GitHub repository: Candy Tools' news and Candy Arts'. Nothing is sent but the requests for the news itself."
const NEW_ITEM_TOOLTIP := "You're reading this news for the first time."
const UNREAD_AHEAD_TOOLTIP := "There's news you haven't read further on."

var undo_redo: EditorUndoRedoManager = null	#/ Set by the descriptor, unused
#^ Tests only - leave the editor running after an update:
var restart_after_update := true

#@ Update card:
var version_icon: TextureRect
var version_label: Label
var update_button: Button
var progress_bar: ProgressBar
var result_text: RichTextLabel
var update_button_checks := false
var busy := false

#@ News card:
var auto_box: CheckBox
var refresh_button: Button
var previous_button: Button
var next_button: Button
var news_text: RichTextLabel
var new_item_mark: TextureRect
var unread_ahead_mark: TextureRect
var items: Array = []		#/ [{id, text}]
var index := 0
var showing_new := false	#/ The item shown was unread when it appeared
var check_count := 0


func _ready() -> void:
	add_theme_constant_override("separation", Style.px(8))
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	#@ Candy Tools:
	var box := Style.card(self, "Reload", "Candy Tools", "Updates, from Candy Tools' GitHub releases.")
	box.get_parent().custom_minimum_size.x = Style.px(300)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Style.px(6))
	box.add_child(row)
	version_icon = Style.icon_rect()
	row.add_child(version_icon)
	version_label = Label.new()
	version_label.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(version_label)
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
	result_text.meta_clicked.connect(func(meta: Variant) -> void: OS.shell_open(ProjectSettings.globalize_path(str(meta))))
	box.add_child(result_text)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	update_button = Button.new()
	update_button.pressed.connect(_on_update_button)
	box.add_child(update_button)

	#@ News:
	var news_box := Style.card(self, "Notification", "News", "")
	news_box.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title_row := Style.title_row(news_box)
	new_item_mark = _unread_mark()
	title_row.add_child(new_item_mark)
	var title_spacer := Control.new()
	title_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title_spacer)
	previous_button = _button("Previous", "Back", _show_item.bind(-1))
	title_row.add_child(previous_button)
	next_button = _button("Next", "Forward", _show_item.bind(1))
	next_button.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	title_row.add_child(next_button)
	unread_ahead_mark = _unread_mark()
	title_row.add_child(unread_ahead_mark)
	var divider := VSeparator.new()
	divider.custom_minimum_size.x = Style.px(8)
	title_row.add_child(divider)
	auto_box = CheckBox.new()
	auto_box.text = "Auto"
	auto_box.tooltip_text = "Look for news when the editor opens, at most once a day."
	auto_box.set_pressed_no_signal(News.auto())
	auto_box.toggled.connect(func(pressed: bool) -> void: News.set_auto(pressed))
	title_row.add_child(auto_box)
	refresh_button = _button(REFRESH_TEXT, "Reload", check_news.bind(true))
	refresh_button.tooltip_text = REFRESH_TOOLTIP
	refresh_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	title_row.add_child(refresh_button)
	_fit_refresh_button()
	news_text = RichTextLabel.new()
	news_text.bbcode_enabled = true
	news_text.selection_enabled = true
	news_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	news_text.custom_minimum_size.y = Style.px(96)
	news_text.meta_clicked.connect(func(meta: Variant) -> void: Updates.open_web_link(str(meta)))
	news_box.add_child(news_text)

	#? An item counts as read once it's on screen, not while another tool hides it.
	visibility_changed.connect(_mark_shown_item)
	refresh()
	_load_items()


func _enter_tree() -> void:
	#? The host adds the view each time the tool is chosen: look on GitHub if it's been a day.
	_auto_check.call_deferred()


func _auto_check() -> void:
	if not is_inside_tree():
		return
	refresh()
	_load_items()
	check_updates(false)
	check_news(false)


#==============================================================================
#  CANDY TOOLS UPDATES
#==============================================================================

func refresh() -> void:
	if update_button == null:
		return
	var installed := Updates.installed_version()
	update_button.disabled = busy or Updates.looking
	update_button.icon = Style.icon("Reload")
	update_button_checks = true
	update_button.text = "Check for Updates"
	update_button.tooltip_text = "Look on GitHub now for a newer Candy Tools."
	version_label.tooltip_text = ""
	if Updates.is_dev_project():
		_set_status(Style.icon("NodeInfo"), "%s, development project." % installed, Style.dim())
		version_label.tooltip_text = "This is Candy Tools' development project: its folder is the source, so Candy Tools never updates itself here."
		update_button.disabled = true
		return
	var newer := Updates.newer_version()
	if newer != "":
		_set_status(Style.icon("StatusWarning"), "%s is out (%s here)." % [newer, installed], Style.color("warning_color"))
		update_button_checks = false
		update_button.text = "Update to %s" % newer
		update_button.icon = Style.icon("AssetLib")
		update_button.tooltip_text = "Download Candy Tools %s from GitHub and install it. The editor restarts after." % newer
	else:
		_set_status(Style.icon("StatusSuccess"), "%s is installed." % installed, Style.color("font_color"))


func _set_status(texture: Texture2D, text: String, text_color: Color) -> void:
	version_icon.texture = texture
	version_label.text = text
	version_label.add_theme_color_override("font_color", text_color)


func _on_update_button() -> void:
	if update_button_checks:
		check_updates(true)
	else:
		_update()


#* Look for a newer Candy Tools. forced: now, showing the result; else at most once a day, quietly:
func check_updates(forced: bool) -> bool:
	if busy or Updates.looking:
		return false
	if forced:
		_show_working("Looking on GitHub…")
	update_button.disabled = true
	var latest: Dictionary = await Updates.look_on_github(self, forced)
	refresh()
	if latest.is_empty():
		return false
	attention_changed.emit()
	if forced:
		progress_bar.visible = false
		if latest.has("error") and Updates.newer_version() == "":
			_show([["StatusWarning", Style.escaped(String(latest["error"])), Style.color("warning_color")]])
		elif Updates.newer_version() != "":
			_show([["StatusWarning", "Candy Tools %s is out." % Updates.newer_version(), Style.color("warning_color")]])
		else:
			_show([["StatusSuccess", "Candy Tools is up to date.", Style.color("success_color")]])
	return true


func _update() -> void:
	if busy:
		return
	busy = true
	refresh()
	_show_working("Looking for Candy Tools' latest release…")
	var error: String = await _run_update()
	busy = false
	refresh()
	progress_bar.visible = false
	attention_changed.emit()
	if error != "":
		_show([["StatusWarning", Style.escaped(error), Style.color("warning_color")]])


#* Download, check and install the latest release, then restart the editor. Returns an error, or "":
func _run_update() -> String:
	var source := Updates.new_source(self)
	var latest: Dictionary = await Updates.fetch_latest_release(source)
	if latest.has("error"):
		source.queue_free()
		return latest["error"]
	var zip_path := Updates.TEMP_FOLDER.path_join(String(latest["asset_name"]))
	source.download_progress.connect(func(done: int, total: int) -> void:
		if total > 0:
			_show_progress(float(done) / total * 0.5, "Downloading Candy Tools %s… %s / %s" % [latest["version"], Updates.readable_size(done), Updates.readable_size(total)]))
	var error: String = await source.download(String(latest["asset_url"]), zip_path)
	source.queue_free()
	if error != "":
		return error

	var package := Updates.package()
	error = package.open(zip_path)
	if error == "":
		error = package.verify()
	var updater := Updater.new()
	if error == "":
		updater.package = package
		updater.plan()
		error = updater.problem
	if error == "":
		var question := "Update Candy Tools %s to %s?\n\n%d of its files change, %d are added and %d removed. Tools that other add-ons installed in Candy Tools' folder are left as they are.\n\nThe editor restarts after the update, saving the open scenes." % [updater.installed_version, package.version(), updater.changed.size(), updater.added.size(), updater.removed.size()]
		if not await Style.confirm(get_tree(), question, "Update and Restart"):
			package.close()
			DirAccess.remove_absolute(zip_path)
			_show([["NodeInfo", "Update canceled.", Style.dim()]])
			return ""
	if error != "":
		package.close()
		DirAccess.remove_absolute(zip_path)
		return error

	updater.progress.connect(func(fraction: float, message: String) -> void: _show_progress(0.5 + fraction * 0.5, message))
	var version := package.version()
	error = await updater.update(get_tree())
	package.close()
	DirAccess.remove_absolute(zip_path)
	if error != "":
		return error
	_show([["StatusSuccess", "Updated to %s. Restarting the editor…" % version, Style.color("success_color")],
		["Folder", "Previous version: [url=%s][code]%s[/code][/url]." % [updater.backup_folder, Style.escaped(ProjectSettings.globalize_path(updater.backup_folder))], Style.dim()]])
	#? The old Candy Tools is still the one in memory: restart before Godot reloads its scripts.
	if restart_after_update:
		EditorInterface.restart_editor(true)
	return ""


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


#* lines - [icon name, BBCode, color] each:
func _show(lines: Array) -> void:
	result_text.visible = true
	result_text.clear()
	for line in lines:
		var texture := Style.icon(line[0])
		if texture != null:
			result_text.add_image(texture, Style.px(16), Style.px(16), line[2])
			result_text.add_text(" ")
		result_text.append_text(line[1])
		result_text.newline()


#==============================================================================
#  NEWS
#==============================================================================

#* Download and show the news. forced: now; else only with Auto on, at most once a day:
func check_news(forced: bool) -> bool:
	if News.busy:
		return false
	check_count += 1
	var count := check_count
	if forced:
		refresh_button.text = CHECKING_TEXT
		refresh_button.disabled = true
	var result: int = await News.refresh(self, forced)
	refresh_button.disabled = false
	if result == -1:
		refresh_button.text = REFRESH_TEXT
		return false
	refresh_button.text = RESULT_TEXTS[result]
	refresh_button.tooltip_text = REFRESH_TOOLTIP
	if News.problem != "":
		refresh_button.tooltip_text += "\n\n" + News.problem
		if result != News.Result.FAILED:
			refresh_button.text = PARTLY_TEXT
	get_tree().create_timer(RESULT_SECONDS).timeout.connect(func() -> void:
		if count == check_count and not News.busy:
			refresh_button.text = REFRESH_TEXT)
	if result == News.Result.UPDATED:
		_load_items()
	elif items.is_empty():
		_show_placeholder(result)
	attention_changed.emit()
	return true


func _load_items() -> void:
	items = News.items()
	index = 0
	if items.is_empty():
		_show_placeholder(-1)
	else:
		_show_item(0)


#* step - -1 = Previous, 1 = Next, 0 = the current item:
func _show_item(step: int) -> void:
	if items.is_empty():
		return
	var new_index := clampi(index + step, 0, items.size() - 1)
	if new_index != index or step == 0:
		showing_new = false
	index = new_index
	news_text.text = items[index]["text"]
	news_text.scroll_to_line(0)
	previous_button.disabled = index == 0
	next_button.disabled = index >= items.size() - 1
	_mark_shown_item()


#* The message with no news. result - the last look's, or -1 before any:
func _show_placeholder(result: int) -> void:
	showing_new = false
	_update_marks()
	previous_button.disabled = true
	next_button.disabled = true
	var message := "No news yet."
	if result == News.Result.FAILED:
		message = News.problem
	elif News.problem != "":
		message += "\n" + News.problem
	elif result == -1 and (not News.auto() or News.last_look() == 0.0):
		message = "Press Refresh to download the news."
	news_text.clear()
	news_text.push_color(Style.dim())
	news_text.add_text(message)
	news_text.pop()


#* Remember the item shown as read, if the panel is on screen:
func _mark_shown_item() -> void:
	if is_visible_in_tree() and index < items.size():
		if News.mark_read(items[index]["id"]):
			showing_new = true
			attention_changed.emit()
	_update_marks()


func _update_marks() -> void:
	_set_mark(new_item_mark, showing_new, NEW_ITEM_TOOLTIP)
	var ahead := false
	var ids := News.read_ids()
	for later in range(index + 1, items.size()):
		if not ids.has(items[later]["id"]):
			ahead = true
			break
	_set_mark(unread_ahead_mark, ahead, UNREAD_AHEAD_TOOLTIP)


#* A hidden mark stays transparent rather than invisible, so the row doesn't shift:
func _set_mark(mark: TextureRect, shown: bool, tooltip: String) -> void:
	mark.modulate.a = 1.0 if shown else 0.0
	mark.tooltip_text = tooltip if shown else ""


func _unread_mark() -> TextureRect:
	var mark := Style.icon_rect()
	mark.texture = Style.icon("StatusWarning")
	mark.modulate.a = 0.0
	return mark


func _button(text: String, icon_name: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.icon = Style.icon(icon_name)
	button.pressed.connect(action)
	return button


#* Size the Refresh button for its widest text, so the row doesn't shift:
func _fit_refresh_button() -> void:
	var widest := 0.0
	for shown in [CHECKING_TEXT, PARTLY_TEXT] + RESULT_TEXTS.values() + [REFRESH_TEXT]:
		refresh_button.text = shown
		widest = maxf(widest, refresh_button.get_minimum_size().x)
	refresh_button.custom_minimum_size.x = widest
