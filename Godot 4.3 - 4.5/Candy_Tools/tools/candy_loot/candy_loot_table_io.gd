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


const META_TABLE = "candy_loot_table"

const META_EDITOR = "candy_loot_editor"

const META_PREFIX = "candy_loot_prefix"

const DEFAULT_PREFIX = "§"


static func save_table(model: Array, prefix: String, path: String) -> int:
	var resource := Resource.new()
	resource.set_meta(META_TABLE, build_runtime_table(model, prefix))
	resource.set_meta(META_EDITOR, build_editor_meta(model))
	resource.set_meta(META_PREFIX, prefix)
	return ResourceSaver.save(resource, path)


static func build_runtime_table(model: Array, prefix: String) -> Dictionary:
	var out := {}
	for pack in model:
		var pack_name: String = pack.get("name", "")
		if pack_name == "":
			continue

		var pack_data := {}
		_put(pack_data, "Number", pack.get("number", ""))
		_put_flag(pack_data, "Discard", pack.get("discard", false))

		var drops := []
		for drop in pack.get("drops", []):
			var key: String = drop.get("key", "")
			if key == "":
				continue
			var drop_data := {}
			_put(drop_data, "Chance", drop.get("chance", ""))
			_put(drop_data, "Amount", amount_to_stored(_text(drop.get("amount", ""))))
			_put(drop_data, "Max", drop.get("max", ""))
			_put_flag(drop_data, "MaxDiscard", drop.get("maxdiscard", false))
			_put(drop_data, "DiscardX", drop.get("discardx", ""))
			drops.append({key: drop_data})

		pack_data["Drops"] = drops
		out[prefix + pack_name] = pack_data
	return out


static func build_editor_meta(model: Array) -> Dictionary:
	var order := []
	var positions := {}
	var collapsed := {}
	var drop_collapsed := {}
	for pack in model:
		var pack_name: String = pack.get("name", "")
		order.append(pack_name)
		var pos: Vector2 = pack.get("pos", Vector2.ZERO)
		positions[pack_name] = [pos.x, pos.y]
		collapsed[pack_name] = pack.get("collapsed", false)
		var folds := []
		for drop in pack.get("drops", []):
			folds.append(bool(drop.get("collapsed", false)))
		drop_collapsed[pack_name] = folds
	return {
		"order": order,
		"positions": positions,
		"collapsed": collapsed,
		"drop_collapsed": drop_collapsed,
	}


static func load_table(path: String) -> Dictionary:
	var resource = ResourceLoader.load(path)
	if resource == null or not resource.has_meta(META_TABLE):
		return {}

	var packs: Dictionary = resource.get_meta(META_TABLE)
	var prefix: String = resource.get_meta(META_PREFIX) if resource.has_meta(META_PREFIX) else DEFAULT_PREFIX
	var extras: Dictionary = resource.get_meta(META_EDITOR) if resource.has_meta(META_EDITOR) else {}

	var positions: Dictionary = extras.get("positions", {})
	var collapsed: Dictionary = extras.get("collapsed", {})
	var drop_collapsed: Dictionary = extras.get("drop_collapsed", {})
	var order: Array = extras.get("order", [])

	var keys := []
	for key in packs.keys():
		keys.append(String(key).trim_prefix(prefix))
	var ordered := []
	for name in order:
		if keys.has(name):
			ordered.append(name)
	for name in keys:
		if not ordered.has(name):
			ordered.append(name)

	var model := []
	for i in ordered.size():
		var pack_name: String = ordered[i]
		var pack_data: Dictionary = packs.get(prefix + pack_name, {})

		var folds: Array = drop_collapsed.get(pack_name, [])
		var drops := []
		for entry in pack_data.get("Drops", []):
			if typeof(entry) != TYPE_DICTIONARY or entry.is_empty():
				continue
			var key = entry.keys()[0]
			var data: Dictionary = entry[key]
			var fold_index := drops.size()
			drops.append({
				"key": String(key),
				"chance": _text(data.get("Chance", "")),
				"amount": amount_to_field(data.get("Amount", "")),
				"max": _text(data.get("Max", "")),
				"maxdiscard": _read_flag(data.get("MaxDiscard", false)),
				"discardx": _text(data.get("DiscardX", "")),
				"collapsed": bool(folds[fold_index]) if fold_index < folds.size() else false,
			})

		var saved_pos = positions.get(pack_name, null)
		var pos := Vector2(i % 4 * 300, floor(i / 4.0) * 340)
		if saved_pos is Array and saved_pos.size() == 2:
			pos = Vector2(saved_pos[0], saved_pos[1])

		model.append({
			"name": pack_name,
			"number": _text(pack_data.get("Number", "")),
			"discard": _read_flag(pack_data.get("Discard", false)),
			"drops": drops,
			"pos": pos,
			"collapsed": bool(collapsed.get(pack_name, false)),
		})

	return {"model": model, "prefix": prefix}


static func _put(target: Dictionary, key: String, raw) -> void:
	var trimmed := String(raw).strip_edges()
	if trimmed == "":
		return
	target[key] = trimmed


static func amount_to_stored(text: String) -> String:
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		return ""
	return "[%s]" % trimmed


static func amount_to_field(value) -> String:
	var trimmed := _text(value).strip_edges()
	if trimmed.begins_with("[") and trimmed.ends_with("]"):
		return trimmed.substr(1, trimmed.length() - 2).strip_edges()
	return trimmed


static func _put_flag(target: Dictionary, key: String, value) -> void:
	if typeof(value) == TYPE_STRING:
		_put(target, key, value)
		return
	target[key] = to_bool(value)


static func _read_flag(value):
	if typeof(value) == TYPE_STRING:
		return String(value)
	return to_bool(value)


static func to_bool(value) -> bool:
	match typeof(value):
		TYPE_BOOL:
			return bool(value)
		TYPE_STRING, TYPE_STRING_NAME:
			return String(value).strip_edges().to_lower() == "true"
		TYPE_INT, TYPE_FLOAT:
			return value != 0
	return false


static func _text(value) -> String:
	if typeof(value) == TYPE_STRING:
		return value
	return var_to_str(value)