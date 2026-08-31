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


const META_TABLE := "candy_loot_table"
const META_PREFIX := "candy_loot_prefix"
const META_TEST := "candy_loot_test"

const TESTS_DIR := "res://addons/Candy_Tools/tools/candy_loot/tests"
const DEFAULT_PREFIX := "§"


static func load_table(path: String, dict_name: String = "") -> Dictionary:
	var fail := func(msg: String) -> Dictionary:
		return {"ok": false, "error": msg, "table": {}, "prefix": ""}

	if path.strip_edges().is_empty():
		return fail.call("No table path set.")

	var ext := path.get_extension().to_lower()

	if ext in ["tres", "res"]:
		if not ResourceLoader.exists(path):
			return fail.call("File not found: %s" % path)
		var resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if resource == null or not resource.has_meta(META_TABLE):
			return fail.call("Not a Candy Tools table file: %s" % path)
		var prefix: String = resource.get_meta(META_PREFIX, DEFAULT_PREFIX)
		return {
			"ok": true,
			"error": "",
			"table": coerce_table(resource.get_meta(META_TABLE)),
			"prefix": prefix,
		}

	if ext == "txt":
		if not FileAccess.file_exists(path):
			return fail.call("File not found: %s" % path)
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			return fail.call("Could not open %s" % path)
		var text := file.get_as_text()
		file.close()

		var cleaned := []
		for line in text.split("\n"):
			if not line.strip_edges().begins_with("\u0023"):
				cleaned.append(line)
		text = "\n".join(cleaned)

		var trailing := RegEx.new()
		trailing.compile(",(\\s*[}\\]])")
		text = trailing.sub(text, "$1", true).strip_edges()

		var expr := Expression.new()
		if expr.parse(text) != OK:
			return fail.call("Failed to parse %s" % path)
		var result = expr.execute()
		if expr.has_execute_failed():
			return fail.call("Error while evaluating %s" % path)
		if typeof(result) != TYPE_DICTIONARY:
			return fail.call("Table root must be a Dictionary: %s" % path)
		return {"ok": true, "error": "", "table": result, "prefix": ""}

	if ext == "gd":
		if dict_name.strip_edges().is_empty():
			return fail.call("Set the dictionary name for .gd tables.")
		var script = load(path)
		if script == null:
			return fail.call("Could not load %s (does it compile?)" % path)

		var instance = script.new()
		if instance == null:
			return fail.call("Could not instantiate %s" % path)

		if not dict_name in instance:
			_release(instance)
			return fail.call("'%s' has no property '%s'" % [path, dict_name])

		var table = instance.get(dict_name)
		_release(instance)

		if typeof(table) != TYPE_DICTIONARY:
			return fail.call("'%s.%s' is not a Dictionary" % [path, dict_name])
		return {"ok": true, "error": "", "table": table, "prefix": ""}

	return fail.call("Unsupported table format: .%s" % ext)


static func coerce_table(raw: Dictionary) -> Dictionary:
	var out := {}
	for pack_key in raw.keys():
		var pack = raw[pack_key]
		if typeof(pack) != TYPE_DICTIONARY:
			out[pack_key] = pack
			continue

		var pack_data := {}
		for key in pack.keys():
			if key == "Drops":
				continue
			pack_data[key] = coerce_value(pack[key])

		var drops := []
		for entry in pack.get("Drops", []):
			if typeof(entry) != TYPE_DICTIONARY or entry.is_empty():
				continue
			var drop_key = entry.keys()[0]
			var drop = entry[drop_key]
			var drop_data := {}
			if typeof(drop) == TYPE_DICTIONARY:
				for key in drop.keys():
					drop_data[key] = coerce_value(drop[key])
			drops.append({drop_key: drop_data})

		pack_data["Drops"] = drops
		out[pack_key] = pack_data
	return out


static func coerce_value(value):
	if typeof(value) != TYPE_STRING:
		return value
	var parsed = str_to_var(value)
	if parsed == null:
		return value
	match typeof(parsed):
		TYPE_INT, TYPE_FLOAT, TYPE_BOOL, TYPE_ARRAY:
			return parsed
	return value


static func list_packs(table: Dictionary, prefix: String) -> Array:
	var packs := []
	if prefix.is_empty():
		return packs
	for key in table.keys():
		if typeof(key) == TYPE_STRING and key.begins_with(prefix):
			packs.append(key)
	return packs


static func table_hash(table: Dictionary) -> int:
	return table.hash()


static func _release(instance) -> void:
	if instance is Node:
		instance.free()


static func ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(TESTS_DIR):
		DirAccess.make_dir_recursive_absolute(TESTS_DIR)


static func header_path(test_name: String) -> String:
	return TESTS_DIR.path_join("%s.tres" % test_name)


static func raw_path(test_name: String) -> String:
	return TESTS_DIR.path_join("%s.raw" % test_name)


static func list_tests() -> Array:
	ensure_dir()
	var names := []
	var dir := DirAccess.open(TESTS_DIR)
	if dir == null:
		return names
	dir.list_dir_begin()
	var file := dir.get_next()
	while file != "":
		if not dir.current_is_dir() and file.get_extension().to_lower() == "tres":
			names.append(file.get_basename())
		file = dir.get_next()
	dir.list_dir_end()
	names.sort_custom(func(a, b): return _compare_test_names(a, b))
	return names


static func _compare_test_names(a: String, b: String) -> bool:
	var a_num := _trailing_number(a)
	var b_num := _trailing_number(b)
	if a_num >= 0 and b_num >= 0:
		var a_stem := a.substr(0, a.length() - str(a_num).length())
		var b_stem := b.substr(0, b.length() - str(b_num).length())
		if a_stem == b_stem:
			return a_num < b_num
	return a.naturalnocasecmp_to(b) < 0


static func _trailing_number(text: String) -> int:
	var digits := ""
	for i in range(text.length() - 1, -1, -1):
		var c := text[i]
		if c >= "0" and c <= "9":
			digits = c + digits
		else:
			break
	return int(digits) if digits != "" else -1


static func unique_test_name(base: String = "Test") -> String:
	var existing := list_tests()
	var n := 1
	while true:
		var candidate := "%s_%d" % [base, n]
		if not existing.has(candidate):
			return candidate
		n += 1
	return base


static func sanitize_name(text: String) -> String:
	const ILLEGAL := ["/", "\\\\", ":", "*", "?", "\"", "<", ">", "|", ".", "%"]
	var cleaned := ""
	for c in text.strip_edges():
		if not c in ILLEGAL:
			cleaned += c
	return cleaned.strip_edges().replace(" ", "_")


static func test_exists(test_name: String) -> bool:
	return FileAccess.file_exists(header_path(test_name))


static func save_header(header: Dictionary) -> int:
	ensure_dir()
	var resource := Resource.new()
	resource.set_meta(META_TEST, header)
	var err := ResourceSaver.save(resource, header_path(header.get("name", "Test")))
	if err != OK:
		push_error("Candy Loot Sampler: could not save test '%s' (error %d)" % [header.get("name", ""), err])
	return err


static func load_header(test_name: String) -> Dictionary:
	var path := header_path(test_name)
	if not ResourceLoader.exists(path):
		return {}
	var resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if resource == null or not resource.has_meta(META_TEST):
		return {}
	var header: Dictionary = resource.get_meta(META_TEST)
	header["name"] = test_name
	return header


static func append_raw(test_name: String, samples: Array) -> void:
	ensure_dir()
	var path := raw_path(test_name)
	var file: FileAccess
	if FileAccess.file_exists(path):
		file = FileAccess.open(path, FileAccess.READ_WRITE)
		if file != null:
			file.seek_end()
	else:
		file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Candy Loot Sampler: could not write %s" % path)
		return
	file.store_var(samples)
	file.close()


static func load_raw(test_name: String) -> Array:
	var path := raw_path(test_name)
	if not FileAccess.file_exists(path):
		return []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return []
	var samples := []
	while file.get_position() < file.get_length():
		var record = file.get_var()
		if typeof(record) == TYPE_ARRAY:
			samples.append_array(record)
	file.close()
	return samples


static func load_raw_page(test_name: String, offset: int, limit: int) -> Array:
	var path := raw_path(test_name)
	if not FileAccess.file_exists(path):
		return []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return []

	var page := []
	var seen := 0
	while file.get_position() < file.get_length() and page.size() < limit:
		var record = file.get_var()
		if typeof(record) != TYPE_ARRAY:
			continue
		if seen + record.size() <= offset:
			seen += record.size()
			continue
		for i in range(record.size()):
			if seen + i < offset:
				continue
			page.append(record[i])
			if page.size() >= limit:
				break
		seen += record.size()
	file.close()
	return page


static func delete_test(test_name: String) -> void:
	for path in [header_path(test_name), raw_path(test_name)]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


static func rename_test(old_name: String, new_name: String) -> String:
	if new_name.is_empty():
		return "Name can't be empty."
	if new_name == old_name:
		return ""
	if test_exists(new_name):
		return "A test named '%s' already exists." % new_name

	var err := DirAccess.rename_absolute(header_path(old_name), header_path(new_name))
	if err != OK:
		return "Could not rename test file (error %d)." % err

	if FileAccess.file_exists(raw_path(old_name)):
		var raw_err := DirAccess.rename_absolute(raw_path(old_name), raw_path(new_name))
		if raw_err != OK:
			DirAccess.rename_absolute(header_path(new_name), header_path(old_name))
			return "Could not rename raw file (error %d)." % raw_err

	var header := load_header(new_name)
	if not header.is_empty():
		header["name"] = new_name
		save_header(header)
	return ""
