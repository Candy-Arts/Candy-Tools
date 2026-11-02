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
extends Node

#? Reads releases and branch files of Candy Arts' repositories on GitHub.
#? A port of Candy Wizard's Release_Source.gd and Docs_Source.gd. GitHub is asked by repository ID,
#? never by name: an ID is never given to another repository, and a renamed one is still found.
#? GitHub allows 60 unauthenticated API requests an hour per address.

signal download_progress(downloaded: int, total: int)
signal files_progress(done: int, total: int)

const Utils = preload("candy_release_utils.gd")

const API_HEADERS := [
	"Accept: application/vnd.github+json",
	"X-GitHub-Api-Version: 2022-11-28",
	Utils.USER_AGENT,
]
const DOWNLOAD_HEADERS := [Utils.USER_AGENT]

#^ Releases read, newest first. Only the newest installable one is offered:
const RELEASES_READ := 30
#^ API_HEADERS asking for a file itself (fetch_file()):
const FILE_HEADERS := [
	"Accept: application/vnd.github.raw+json",
	"X-GitHub-Api-Version: 2022-11-28",
	Utils.USER_AGENT,
]
#^ Seconds GitHub's API gets to answer, and one documentation file's download:
const API_TIMEOUT := 20.0
const FILE_TIMEOUT := 60.0
#^ Files downloaded at once:
const PARALLEL_DOWNLOADS := 4

#^ Only tests change these (a local stand-in for GitHub):
var api_base := "https://api.github.com"
var raw_base := "https://raw.githubusercontent.com"

var http: HTTPRequest = null
var downloading := false
var workers: Array[HTTPRequest] = []


func _ready() -> void:
	http = HTTPRequest.new()
	http.use_threads = true
	add_child(http)
	set_process(false)


func _process(_delta: float) -> void:
	if downloading:
		download_progress.emit(http.get_downloaded_bytes(), http.get_body_size())


func repository_url(id: int) -> String:
	return "%s/repositories/%d" % [api_base, id]


#==============================================================================
#  RELEASES
#==============================================================================

#* A repository's newest published release with its zip (<package_name>_<version>.zip), or {"error"}:
#? {"version", "date", "page_url", "tag", "asset_name", "asset_url", "asset_size"}.
#? Without an installable one, the newest release's details are returned with "error".
func fetch_latest_release(repo_id: int, package_name: String, title: String) -> Dictionary:
	var url := "%s/releases?per_page=%d" % [repository_url(repo_id), RELEASES_READ]
	var parsed = await _get_json(url, "%s's repository isn't on GitHub, or isn't public." % title)
	if parsed is Dictionary and parsed.has("error"):
		return parsed
	if not parsed is Array:
		return {"error": "GitHub's answer couldn't be read."}

	#? GitHub lists by creation date (a fix to an older version can come later): compare versions.
	var newest := {}
	var installable := {}
	for entry in parsed:
		if not entry is Dictionary or bool(entry.get("draft", false)) or bool(entry.get("prerelease", false)):
			continue
		var found := _release_details(entry, package_name)
		if found["version"] == "":
			continue
		if newest.is_empty() or Utils.compare_versions(found["version"], newest["version"]) > 0:
			newest = found
		if found.has("asset_url") and (installable.is_empty() or Utils.compare_versions(found["version"], installable["version"]) > 0):
			installable = found
	if not installable.is_empty():
		return installable
	if newest.is_empty():
		return {"error": "There's no %s release on GitHub yet." % title}
	newest["error"] = "%s %s has no release zip (%s_%s.zip) to download." % [title, newest["version"], package_name, newest["version"]]
	return newest


func _release_details(entry: Dictionary, package_name: String) -> Dictionary:
	var tag := _text(entry, "tag_name")
	var details := {
		"version": tag.trim_prefix("v").trim_prefix("V"),
		"tag": tag,
		"date": _text(entry, "published_at").substr(0, 10),
		"page_url": _text(entry, "html_url"),
	}
	var assets = entry.get("assets")
	if not assets is Array:
		return details
	var prefix := package_name + "_"
	for asset in assets:
		if not asset is Dictionary or _text(asset, "state", "uploaded") != "uploaded":
			continue
		#? Candy_Database_<version>.zip, with a plain version matching the release's:
		var asset_name := _text(asset, "name")
		if not asset_name.begins_with(prefix) or not asset_name.to_lower().ends_with(".zip"):
			continue
		var asset_version := asset_name.substr(prefix.length(), asset_name.length() - prefix.length() - 4)
		if not Utils.is_plain_version(asset_version) or Utils.compare_versions(asset_version, details["version"]) != 0:
			continue
		details["asset_name"] = asset_name
		details["asset_url"] = _text(asset, "browser_download_url")
		details["asset_size"] = int(asset.get("size", 0))
		break
	return details


#* GitHub writes null for what a release lacks, which String() can't take:
static func _text(data: Dictionary, key: String, fallback: String = "") -> String:
	var value = data.get(key)
	return value if value is String else fallback


#* Downloads a file to target_path. Returns an error message, or "":
func download(url: String, target_path: String) -> String:
	DirAccess.make_dir_recursive_absolute(target_path.get_base_dir())
	http.download_file = target_path
	http.timeout = 0.0
	var error := http.request(url, DOWNLOAD_HEADERS)
	if error != OK:
		http.download_file = ""
		return "Couldn't start the download (%s)." % error_string(error)
	downloading = true
	set_process(true)
	var response: Array = await http.request_completed
	downloading = false
	set_process(false)
	http.download_file = ""
	var response_error := _response_error(response, "The download", "The release zip isn't on GitHub anymore: it may have been replaced. Try again.")
	if response_error != "":
		DirAccess.remove_absolute(target_path)
	return response_error


#==============================================================================
#  DOCUMENTATION
#==============================================================================

#* A branch's files - {"commit", "files" = {path = git hash}}, or {"error"}:
func fetch_tree(repo_id: int, branch: String) -> Dictionary:
	var repo_url := repository_url(repo_id)
	var ref = await _get_json("%s/git/ref/heads/%s" % [repo_url, branch.uri_encode()], "The repository (or its %s branch) isn't on GitHub, or isn't public." % branch)
	if ref is Dictionary and ref.has("error"):
		return ref
	if not ref is Dictionary or not ref.get("object") is Dictionary:
		return {"error": "GitHub's answer couldn't be read."}
	var commit := String(ref["object"].get("sha", ""))
	var listing = await _get_json("%s/git/trees/%s?recursive=1" % [repo_url, commit], "The repository's files weren't found on GitHub.")
	if listing is Dictionary and listing.has("error"):
		return listing
	if not listing is Dictionary or not listing.get("tree") is Array:
		return {"error": "GitHub's answer couldn't be read."}
	if bool(listing.get("truncated", false)):
		return {"error": "The repository has too many files for GitHub to list them all at once."}
	var files := {}
	for entry in listing["tree"]:
		if entry is Dictionary and String(entry.get("type", "")) == "blob":
			files[String(entry.get("path", ""))] = String(entry.get("sha", ""))
	return {"commit": commit, "files": files}


#* Download wanted ({path = git hash}) at a commit into memory - {"files" = {path = bytes}}, or {"error"}:
#? Raw files are fetched by the repository's name (the only way there), so each must match
#? the git hash fetch_tree() got by ID.
#? repo - "owner/name".
func download_files(repo: String, commit: String, wanted: Dictionary) -> Dictionary:
	var queue: Array = wanted.keys()
	var state := {"error": "", "next": 0, "done": 0, "running": 0, "files": {}}
	if queue.is_empty():
		return {"files": {}}
	files_progress.emit(0, queue.size())
	for index in mini(PARALLEL_DOWNLOADS, queue.size()):
		var request := HTTPRequest.new()
		#? Not threaded: cancelling a threaded request freezes the editor until the server answers.
		request.timeout = FILE_TIMEOUT
		add_child(request)
		workers.append(request)
		state["running"] += 1
		_download_next(request, repo, commit, queue, wanted, state)
	while state["running"] > 0 and state["error"] == "":
		await get_tree().process_frame
	for request in workers:
		request.cancel_request()
		request.queue_free()
	workers.clear()
	if state["error"] != "":
		return {"error": state["error"]}
	return {"files": state["files"]}


func _download_next(request: HTTPRequest, repo: String, commit: String, queue: Array, wanted: Dictionary, state: Dictionary) -> void:
	while state["error"] == "" and state["next"] < queue.size():
		var path := String(queue[state["next"]])
		state["next"] += 1
		var url := "%s/%s/%s/%s" % [raw_base, repo, commit, _encoded_path(path)]
		var error := request.request(url, DOWNLOAD_HEADERS)
		if error != OK:
			state["error"] = "Couldn't start downloading %s (%s)." % [path.get_file(), error_string(error)]
			break
		var response: Array = await request.request_completed
		if state["error"] != "":
			break
		var response_error := _response_error(response, "Downloading %s" % path.get_file(), "%s isn't on GitHub anymore: check again for updates." % path)
		if response_error != "":
			state["error"] = response_error
			break
		var bytes: PackedByteArray = response[3]
		if Utils.git_blob_hash(path, bytes, false) != String(wanted[path]):
			state["error"] = "%s didn't download right (it doesn't match GitHub's list). Try again." % path
			break
		state["files"][path] = bytes
		state["done"] += 1
		files_progress.emit(state["done"], queue.size())
	state["running"] -= 1


#* One file of a branch - {"bytes", "etag"}, {"unchanged" = true} when it matches etag, or {"error"}:
#? One API request. GitHub answers 304 when the file is unchanged since etag, without sending it.
func fetch_file(repo_id: int, branch: String, path: String, etag: String, max_bytes: int) -> Dictionary:
	var headers := PackedStringArray(FILE_HEADERS)
	if etag != "":
		headers.append("If-None-Match: " + etag)
	http.download_file = ""
	http.timeout = API_TIMEOUT
	http.body_size_limit = max_bytes
	var error := http.request("%s/contents/%s?ref=%s" % [repository_url(repo_id), _encoded_path(path), branch.uri_encode()], headers)
	if error != OK:
		http.body_size_limit = -1
		return {"error": "Couldn't contact GitHub (%s)." % error_string(error)}
	var response: Array = await http.request_completed
	http.body_size_limit = -1
	if int(response[0]) == HTTPRequest.RESULT_SUCCESS and int(response[1]) == 304:
		return {"unchanged": true}
	var response_error := _response_error(response, "Checking GitHub", "It isn't on GitHub, or isn't public.")
	if response_error != "":
		return {"error": response_error}
	var found_etag := ""
	for header in response[2]:
		if String(header).to_lower().begins_with("etag:"):
			found_etag = String(header).substr(5).strip_edges()
	return {"bytes": response[3], "etag": found_etag}


func _encoded_path(path: String) -> String:
	var encoded: PackedStringArray = []
	for part in path.split("/"):
		encoded.append(part.uri_encode())
	return "/".join(encoded)


#==============================================================================
#  REQUESTS
#==============================================================================

func cancel() -> void:
	if http != null:
		http.cancel_request()
	downloading = false
	set_process(false)


#* An API request's JSON answer, or {"error"}:
func _get_json(url: String, not_found: String) -> Variant:
	http.download_file = ""
	http.timeout = API_TIMEOUT
	var error := http.request(url, API_HEADERS)
	if error != OK:
		return {"error": "Couldn't contact GitHub (%s)." % error_string(error)}
	var response: Array = await http.request_completed
	var response_error := _response_error(response, "Checking GitHub", not_found)
	if response_error != "":
		return {"error": response_error}
	var parsed = JSON.parse_string((response[3] as PackedByteArray).get_string_from_utf8())
	if parsed == null:
		return {"error": "GitHub's answer couldn't be read."}
	return parsed


#* What went wrong with a request_completed response, or "":
func _response_error(response: Array, what: String, not_found: String) -> String:
	var result: int = response[0]
	var code: int = response[1]
	if result == HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
		return "%s failed: the file is larger than Candy Tools takes." % what
	if result != HTTPRequest.RESULT_SUCCESS:
		return "%s failed: couldn't reach the server. Check your internet connection. (%s)" % [what, _result_text(result)]
	if code == 404:
		return not_found
	if code == 403 or code == 429:
		return "GitHub refused the request: it limits how often it can be asked (60 times an hour). %s" % _retry_text(response[2])
	if code < 200 or code >= 300:
		return "%s failed: the server answered with error %d." % [what, code]
	return ""


func _retry_text(headers: PackedStringArray) -> String:
	for header in headers:
		if header.to_lower().begins_with("x-ratelimit-reset:"):
			var reset := header.get_slice(":", 1).strip_edges().to_int()
			var minutes := ceili((reset - Time.get_unix_time_from_system()) / 60.0)
			if minutes > 1:
				return "Try again in %d minutes." % minutes
			if minutes == 1:
				return "Try again in a minute."
	return "Try again in a while."


func _result_text(result: int) -> String:
	match result:
		HTTPRequest.RESULT_CANT_RESOLVE:
			return "host not found"
		HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_CONNECTION_ERROR:
			return "connection failed"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "secure connection failed"
		HTTPRequest.RESULT_TIMEOUT:
			return "timed out"
		HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN, HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR:
			return "couldn't save the file"
		HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED:
			return "too many redirects"
	return "error %d" % result
