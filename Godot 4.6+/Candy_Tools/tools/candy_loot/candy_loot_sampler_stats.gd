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


static func new_aggregate() -> Dictionary:
	return {
		"samples": 0,
		"empty_samples": 0,
		"pooled_entry": {},
		"pooled_unit": {},
		"samples_containing": {},
		"grand_entry": 0,
		"grand_unit": 0,
		"aar_sum": {},
		"aar_count": {},
		"aaar_sum": {},
		"aaar_count": {},
		"entry_hist": {},
		"unit_hist": {},
		"size_entry_hist": {},
		"size_unit_hist": {},
	}


static func accumulate(agg: Dictionary, samples: Array) -> void:
	for loot_items in samples:
		var pairs := normalize_sample(loot_items)

		var entry_counts := {}
		var unit_totals := {}
		var entry_total := 0
		var unit_total := 0

		for pair in pairs:
			var key = pair[0]
			var amount: int = pair[1]
			entry_counts[key] = entry_counts.get(key, 0) + 1
			unit_totals[key] = unit_totals.get(key, 0) + amount
			entry_total += 1
			unit_total += amount

		agg["samples"] += 1
		agg["grand_entry"] += entry_total
		agg["grand_unit"] += unit_total
		if pairs.is_empty():
			agg["empty_samples"] += 1

		_bump(agg["size_entry_hist"], entry_total)
		_bump(agg["size_unit_hist"], unit_total)

		for key in entry_counts.keys():
			var draws: int = entry_counts[key]
			var units: int = unit_totals[key]

			agg["pooled_entry"][key] = agg["pooled_entry"].get(key, 0) + draws
			agg["pooled_unit"][key] = agg["pooled_unit"].get(key, 0) + units
			agg["samples_containing"][key] = agg["samples_containing"].get(key, 0) + 1

			if entry_total > 0:
				agg["aar_sum"][key] = agg["aar_sum"].get(key, 0.0) + float(draws) / entry_total
				agg["aar_count"][key] = agg["aar_count"].get(key, 0) + 1
			if unit_total > 0:
				agg["aaar_sum"][key] = agg["aaar_sum"].get(key, 0.0) + float(units) / unit_total
				agg["aaar_count"][key] = agg["aaar_count"].get(key, 0) + 1

			if not agg["entry_hist"].has(key):
				agg["entry_hist"][key] = {}
			if not agg["unit_hist"].has(key):
				agg["unit_hist"][key] = {}
			_bump(agg["entry_hist"][key], draws)
			_bump(agg["unit_hist"][key], units)


static func _bump(dict: Dictionary, key) -> void:
	dict[key] = dict.get(key, 0) + 1


static func normalize_sample(loot_items) -> Array:
	var pairs := []
	if typeof(loot_items) != TYPE_ARRAY:
		return pairs
	for entry in loot_items:
		if typeof(entry) == TYPE_ARRAY and entry.size() >= 2:
			pairs.append([entry[0], int(entry[1])])
		else:
			pairs.append([entry, 1])
	return pairs



static func item_rows(agg: Dictionary) -> Array:
	var samples: int = agg.get("samples", 0)
	var grand_entry: int = agg.get("grand_entry", 0)
	var grand_unit: int = agg.get("grand_unit", 0)
	var containing: Dictionary = agg.get("samples_containing", {})

	var rows := []
	for key in containing.keys():
		var in_samples: int = containing[key]
		var draws: int = agg["pooled_entry"].get(key, 0)
		var units: int = agg["pooled_unit"].get(key, 0)
		var aar_count: int = agg["aar_count"].get(key, 0)
		var aaar_count: int = agg["aaar_count"].get(key, 0)

		rows.append({
			"item": key,
			"in_samples": in_samples,
			"draws": draws,
			"units": units,
			"sar": _pct(in_samples, samples),
			"tar": _pct(draws, grand_entry),
			"aar": 100.0 * agg["aar_sum"].get(key, 0.0) / aar_count if aar_count > 0 else 0.0,
			"taar": _pct(units, grand_unit),
			"aaar": 100.0 * agg["aaar_sum"].get(key, 0.0) / aaar_count if aaar_count > 0 else 0.0,
			"avg_draws": float(draws) / samples if samples > 0 else 0.0,
			"avg_units": float(units) / samples if samples > 0 else 0.0,
			"avg_units_present": float(units) / in_samples if in_samples > 0 else 0.0,
		})

	rows.sort_custom(func(a, b): return a["sar"] > b["sar"])
	return rows


static func _pct(part: int, whole: int) -> float:
	return 100.0 * part / whole if whole > 0 else 0.0


static func mean_mode_median(counts: Dictionary) -> Dictionary:
	if counts.is_empty():
		return {
			"mean": [], "mean_count": 0,
			"mode": [], "mode_count": 0,
			"median_down": [], "median_down_count": 0,
			"median_up": [], "median_up_count": 0,
			"median_tied": true,
		}

	var items := counts.keys()

	var mode_count = counts[items[0]]
	for key in items:
		if counts[key] > mode_count:
			mode_count = counts[key]
	var mode_items := []
	for key in items:
		if counts[key] == mode_count:
			mode_items.append(key)

	var total := 0
	for key in items:
		total += counts[key]
	var avg := float(total) / items.size()

	var mean_diff: float = abs(counts[items[0]] - avg)
	for key in items:
		var diff: float = abs(counts[key] - avg)
		if diff < mean_diff:
			mean_diff = diff
	var mean_items := []
	var mean_count := 0
	for key in items:
		if abs(counts[key] - avg) == mean_diff:
			mean_items.append(key)
			mean_count = counts[key]

	var sorted_items := items.duplicate()
	sorted_items.sort_custom(func(a, b): return counts[a] < counts[b])

	var down_index := int(floor((sorted_items.size() - 1) / 2.0))
	var up_index := int(ceil((sorted_items.size() - 1) / 2.0))
	var median_down_count = counts[sorted_items[down_index]]
	var median_up_count = counts[sorted_items[up_index]]

	var median_down_items := []
	var median_up_items := []
	for key in sorted_items:
		if counts[key] == median_down_count:
			median_down_items.append(key)
		if counts[key] == median_up_count:
			median_up_items.append(key)

	return {
		"mean": mean_items, "mean_count": mean_count,
		"mode": mode_items, "mode_count": mode_count,
		"median_down": median_down_items, "median_down_count": median_down_count,
		"median_up": median_up_items, "median_up_count": median_up_count,
		"median_tied": median_down_count == median_up_count,
	}


static func range_and_stddev(counts: Dictionary) -> Dictionary:
	if counts.is_empty():
		return {"min": 0, "max": 0, "spread": 0, "stddev": 0.0}

	var values := counts.values()
	var min_val = values[0]
	var max_val = values[0]
	var total := 0
	for v in values:
		if v < min_val:
			min_val = v
		if v > max_val:
			max_val = v
		total += v

	var avg := float(total) / values.size()
	var squared_diff_sum := 0.0
	for v in values:
		squared_diff_sum += pow(v - avg, 2)

	var stddev := 0.0
	if values.size() > 1:
		stddev = sqrt(squared_diff_sum / (values.size() - 1))

	return {"min": min_val, "max": max_val, "spread": max_val - min_val, "stddev": stddev}


static func aggregate_counts(agg: Dictionary) -> Dictionary:
	return {
		"Per-Sample Presence": agg.get("samples_containing", {}),
		"Draw Count": agg.get("pooled_entry", {}),
		"Amount": agg.get("pooled_unit", {}),
	}


static func sample_averages(agg: Dictionary) -> Dictionary:
	var samples: int = agg.get("samples", 0)
	if samples == 0:
		return {"entries": 0.0, "units": 0.0}
	return {
		"entries": float(agg.get("grand_entry", 0)) / samples,
		"units": float(agg.get("grand_unit", 0)) / samples,
	}


static func histogram_pairs(hist: Dictionary) -> Array:
	var pairs := []
	for key in hist.keys():
		pairs.append([int(key), int(hist[key])])
	pairs.sort_custom(func(a, b): return a[0] < b[0])
	return pairs


static func histogram_stats(hist: Dictionary) -> Dictionary:
	var n := 0
	var total := 0
	var min_val := -1
	var max_val := 0
	for key in hist.keys():
		var value := int(key)
		var count := int(hist[key])
		n += count
		total += value * count
		if min_val < 0 or value < min_val:
			min_val = value
		if value > max_val:
			max_val = value
	if n == 0:
		return {"mean": 0.0, "stddev": 0.0, "min": 0, "max": 0}

	var mean := float(total) / n
	var squared := 0.0
	for key in hist.keys():
		squared += pow(int(key) - mean, 2) * int(hist[key])
	var stddev := sqrt(squared / (n - 1)) if n > 1 else 0.0
	return {"mean": mean, "stddev": stddev, "min": max(min_val, 0), "max": max_val}


static func export_csv(dir: String, test_name: String, header: Dictionary, raw_samples: Array) -> String:
	if not DirAccess.dir_exists_absolute(dir):
		var err := DirAccess.make_dir_recursive_absolute(dir)
		if err != OK:
			return "Could not create %s (error %d)." % [dir, err]

	var agg: Dictionary = header.get("aggregate", new_aggregate())

	_ensure_gdignore(dir)

	_write_item_stats(dir.path_join("%s_item_stats.csv" % test_name), test_name, agg)
	_write_general_aggregate(dir.path_join("%s_general_aggregate.csv" % test_name), test_name, agg)
	_write_summary(dir.path_join("%s_summary.csv" % test_name), test_name, header, agg)
	if not raw_samples.is_empty():
		_write_raw(dir.path_join("%s_raw_loot.csv" % test_name), test_name, raw_samples)
	return ""


static func _ensure_gdignore(dir: String) -> void:
	if not _is_inside_project(dir):
		return
	var path := dir.path_join(".gdignore")
	if FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("Candy Loot Sampler: could not write %s. Godot will try to import the exported CSV files as translations." % path)
		return
	file.close()


static func _is_inside_project(dir: String) -> bool:
	if dir.begins_with("res://"):
		return true
	var project := ProjectSettings.globalize_path("res://").simplify_path().trim_suffix("/") + "/"
	var target := ProjectSettings.globalize_path(dir).simplify_path().trim_suffix("/") + "/"
	return project != "/" and target.begins_with(project)


static func _write_csv(path: String, header: Array, rows: Array) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Candy Loot Sampler: failed to write %s" % path)
		return
	file.store_string("\uFEFF")
	file.store_csv_line(header)
	for row in rows:
		file.store_csv_line(row)
	file.close()


static func _write_item_stats(path: String, test_name: String, agg: Dictionary) -> void:
	var header := [
		"Test", "Item",
		"Sample Appearance Rate %", "Sample Appearance Rate Raw",
		"Total Item Appearance Rate %", "Total Item Appearance Rate Raw",
		"Average Appearance Rate %",
		"Total Amount Appearance Rate %", "Total Amount Appearance Rate Raw",
		"Average Amount Appearance Rate %",
		"Avg Draws / Sample", "Avg Amount / Sample",
	]
	var rows := []
	var samples: int = agg.get("samples", 0)
	for row in item_rows(agg):
		rows.append([
			test_name, row["item"],
			"%.2f" % row["sar"], "%d/%d" % [row["in_samples"], samples],
			"%.2f" % row["tar"], "%d/%d" % [row["draws"], agg.get("grand_entry", 0)],
			"%.2f" % row["aar"],
			"%.2f" % row["taar"], "%d/%d" % [row["units"], agg.get("grand_unit", 0)],
			"%.2f" % row["aaar"],
			"%.3f" % row["avg_draws"], "%.3f" % row["avg_units"],
		])
	_write_csv(path, header, rows)


static func _write_general_aggregate(path: String, test_name: String, agg: Dictionary) -> void:
	var header := [
		"Test", "Metric",
		"Mean Item(s)", "Mean Count",
		"Mode Item(s)", "Mode Count",
		"Median Down Item(s)", "Median Down Count",
		"Median Up Item(s)", "Median Up Count",
		"Range", "StdDev",
	]
	var rows := []
	var counts := aggregate_counts(agg)
	for label in counts.keys():
		var mmm := mean_mode_median(counts[label])
		var rs := range_and_stddev(counts[label])
		rows.append([
			test_name, label,
			" | ".join(mmm["mean"]), str(mmm["mean_count"]),
			" | ".join(mmm["mode"]), str(mmm["mode_count"]),
			" | ".join(mmm["median_down"]), str(mmm["median_down_count"]),
			" | ".join(mmm["median_up"]), str(mmm["median_up_count"]),
			str(rs["spread"]), "%.2f" % rs["stddev"],
		])
	_write_csv(path, header, rows)


static func _write_summary(path: String, test_name: String, header_data: Dictionary, agg: Dictionary) -> void:
	var header := ["Test", "Field", "Value"]
	var averages := sample_averages(agg)
	var entry_stats := histogram_stats(agg.get("size_entry_hist", {}))
	var unit_stats := histogram_stats(agg.get("size_unit_hist", {}))
	var samples: int = agg.get("samples", 0)

	var rows := [
		[test_name, "Samples", str(samples)],
		[test_name, "Runs", " + ".join(_run_strings(header_data.get("runs", [])))],
		[test_name, "Table", header_data.get("table_path", "")],
		[test_name, "Dictionary", header_data.get("dict_name", "")],
		[test_name, "Pack Prefix", header_data.get("prefix", "")],
		[test_name, "Start Items", " | ".join(header_data.get("start_items", []))],
		[test_name, "Stacking", str(header_data.get("stacking", 0))],
		[test_name, "Distinct Items", str(agg.get("samples_containing", {}).size())],
		[test_name, "Empty Samples", "%d (%.2f%%)" % [agg.get("empty_samples", 0), _pct(agg.get("empty_samples", 0), samples)]],
		[test_name, "Avg Items / Sample", "%.3f" % averages["entries"]],
		[test_name, "Avg Amount / Sample", "%.3f" % averages["units"]],
		[test_name, "Items / Sample Range", "%d-%d" % [entry_stats["min"], entry_stats["max"]]],
		[test_name, "Items / Sample StdDev", "%.3f" % entry_stats["stddev"]],
		[test_name, "Amount / Sample Range", "%d-%d" % [unit_stats["min"], unit_stats["max"]]],
		[test_name, "Amount / Sample StdDev", "%.3f" % unit_stats["stddev"]],
	]
	_write_csv(path, header, rows)


static func _run_strings(runs: Array) -> Array:
	var out := []
	for run in runs:
		out.append(str(run))
	return out


static func _write_raw(path: String, test_name: String, samples: Array) -> void:
	var header := ["Test", "Sample", "Item", "Amount"]
	var rows := []
	for i in range(samples.size()):
		for pair in normalize_sample(samples[i]):
			rows.append([test_name, "Sample %d" % (i + 1), pair[0], str(pair[1])])
	_write_csv(path, header, rows)
