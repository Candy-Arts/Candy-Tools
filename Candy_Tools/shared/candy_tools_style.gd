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
extends RefCounted

#? The look of Candy Tools' panels, from the editor's theme.


#* A card with a title and caption. Returns the box its content goes in:
static func card(parent: Node, icon_name: String, title: String, caption: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	var box_style := StyleBoxFlat.new()
	box_style.bg_color = color("dark_color_2", Color(0, 0, 0, 0.2))
	box_style.set_corner_radius_all(px(4))
	box_style.set_content_margin_all(px(10))
	panel.add_theme_stylebox_override("panel", box_style)
	parent.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", px(6))
	panel.add_child(box)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", px(6))
	box.add_child(title_row)
	var title_icon := icon_rect()
	title_icon.texture = icon(icon_name)
	title_row.add_child(title_icon)
	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_font_override("font", bold_font())
	title_row.add_child(title_label)
	if caption != "":
		var caption_label := Label.new()
		caption_label.text = caption
		caption_label.modulate = Color(1, 1, 1, 0.6)
		box.add_child(caption_label)
	return box


#* The row holding a card's icon and title, to add buttons to:
static func title_row(box: VBoxContainer) -> HBoxContainer:
	return box.get_child(0) as HBoxContainer


static func icon_rect() -> TextureRect:
	var rect := TextureRect.new()
	rect.custom_minimum_size = Vector2(px(16), px(16))
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return rect


static func icon(icon_name: String) -> Texture2D:
	var editor_theme := EditorInterface.get_editor_theme()
	if editor_theme != null and editor_theme.has_icon(icon_name, "EditorIcons"):
		return editor_theme.get_icon(icon_name, "EditorIcons")
	return null


static func color(color_name: String, fallback: Color = Color.WHITE) -> Color:
	var editor_theme := EditorInterface.get_editor_theme()
	if editor_theme != null and editor_theme.has_color(color_name, "Editor"):
		return editor_theme.get_color(color_name, "Editor")
	return fallback


static func dim() -> Color:
	var dimmed := color("font_color")
	dimmed.a = 0.6
	return dimmed


static func bold_font() -> Font:
	var editor_theme := EditorInterface.get_editor_theme()
	if editor_theme != null and editor_theme.has_font("bold", "EditorFonts"):
		return editor_theme.get_font("bold", "EditorFonts")
	return null


static func px(value: float) -> int:
	return int(value * EditorInterface.get_editor_scale())


#* Text from outside, shown as text in BBCode:
static func escaped(text: String) -> String:
	return text.replace("[", "[lb]")


#* Ask in a dialog. Returns whether ok_text's button was pressed:
static func confirm(tree: SceneTree, question: String, ok_text: String) -> bool:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Candy Tools"
	dialog.dialog_text = question
	dialog.dialog_autowrap = true
	dialog.ok_button_text = ok_text
	dialog.min_size = Vector2i(px(520), 0)
	var answer := {"value": -1}
	dialog.confirmed.connect(func() -> void: answer["value"] = 1)
	dialog.canceled.connect(func() -> void: answer["value"] = 0)
	EditorInterface.get_base_control().add_child(dialog)
	dialog.popup_centered()
	while answer["value"] == -1 and is_instance_valid(dialog):
		await tree.process_frame
	if is_instance_valid(dialog):
		dialog.queue_free()
	return answer["value"] == 1
