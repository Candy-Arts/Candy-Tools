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
extends RefCounted


const TEMPLATES_PATH = "res://addons/Candy_Tools/tools/candy_loot/candy_pack_templates.tres"

const META_TEMPLATES = "candy_pack_templates"


static func load_all() -> Dictionary:
	if not ResourceLoader.exists(TEMPLATES_PATH):
		return {}
	var resource = ResourceLoader.load(TEMPLATES_PATH)
	if resource == null or not resource.has_meta(META_TEMPLATES):
		return {}
	return resource.get_meta(META_TEMPLATES)


static func has_template(template_name: String) -> bool:
	return load_all().has(template_name)


static func names() -> Array:
	var out: Array = load_all().keys()
	out.sort()
	return out

static func save_template(template_name: String, pack: Dictionary) -> int:
	if template_name == "":
		return ERR_INVALID_PARAMETER

	var templates := load_all()
	var stored: Dictionary = pack.duplicate(true)
	stored.erase("pos")
	stored.erase("collapsed")
	templates[template_name] = stored

	var resource := Resource.new()
	resource.set_meta(META_TEMPLATES, templates)
	var result := ResourceSaver.save(resource, TEMPLATES_PATH)
	if result == OK and Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()
	return result


static func instantiate(template_name: String, spawn_pos: Vector2) -> Dictionary:
	var templates := load_all()
	if not templates.has(template_name):
		return {}
	var pack: Dictionary = templates[template_name].duplicate(true)
	pack["pos"] = spawn_pos
	pack["collapsed"] = false
	if not pack.has("drops"):
		pack["drops"] = []
	return pack


static func delete_template(template_name: String) -> int:
	var templates := load_all()
	if not templates.erase(template_name):
		return ERR_DOES_NOT_EXIST
	var resource := Resource.new()
	resource.set_meta(META_TEMPLATES, templates)
	var result := ResourceSaver.save(resource, TEMPLATES_PATH)
	if result == OK and Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()
	return result