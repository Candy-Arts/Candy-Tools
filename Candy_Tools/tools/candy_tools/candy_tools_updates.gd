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
extends "res://addons/Candy_Tools/shared/candy_release_utils.gd"

#? Candy Tools' own releases: what's installed, the last look on GitHub.

const GitHubSource = preload("res://addons/Candy_Tools/shared/candy_github_source.gd")
const ReleasePackage = preload("res://addons/Candy_Tools/shared/candy_release_package.gd")

#^ Candy Tools' releases - Candy_Tools_<version>.zip on GitHub (Release_Tools/Build_Candy_Tools.gd):
#! The builder duplicates the package and manifest names: change them together.
const PACKAGE_NAME := "Candy_Tools"
const MANIFEST_NAME := "candy_tools_manifest.json"
const GITHUB_REPOSITORY := "Candy-Arts/Candy-Tools"
const GITHUB_REPOSITORY_ID := 1352337741
const FOLDER := "res://addons/Candy_Tools"
#^ Only in Candy Tools' development project, where Candy Tools never updates itself:
const BUILDER_PATH := "res://Release_Tools/Build_Candy_Tools.gd"

const TEMP_FOLDER := "user://candy_tools/updates"
const BACKUPS_FOLDER := "user://candy_tools/backups"

#^ The last look for a newer release, per machine - {"time", "version"}:
const SETTING_UPDATE_CHECK := "candy_tools/update_check"
#^ Seconds between automatic looks:
const CHECK_INTERVAL := 24 * 60 * 60

#^ Tests only - a local stand-in for GitHub's API:
static var test_api_base := ""
#^ Automatic look done this session (even a failed one):
static var _looked := false
static var looking := false


static func installed_version() -> String:
	return plugin_version(FOLDER)


static func is_dev_project() -> bool:
	return FileAccess.file_exists(BUILDER_PATH)


static func package() -> ReleasePackage:
	return ReleasePackage.new(PACKAGE_NAME, MANIFEST_NAME, FOLDER, "Candy Tools")


static func new_source(parent: Node) -> GitHubSource:
	var source := GitHubSource.new()
	if test_api_base != "":
		source.api_base = test_api_base
	parent.add_child(source)
	return source


#* The newest version on GitHub (as last looked) when it's newer than this one, else "":
static func newer_version() -> String:
	if is_dev_project():
		return ""
	var latest := String(editor_setting(SETTING_UPDATE_CHECK).get("version", ""))
	if latest != "" and compare_versions(latest, installed_version()) > 0:
		return latest
	return ""


#* Look up the latest release (forced: now; else at most once a day and once per session):
#? Returns the release (fetch_latest_release()'s answer), or {} when GitHub wasn't asked.
static func look_on_github(parent: Node, forced: bool) -> Dictionary:
	if looking or is_dev_project():
		return {}
	if not forced:
		var last := float(editor_setting(SETTING_UPDATE_CHECK).get("time", 0.0))
		if _looked or Time.get_unix_time_from_system() - last < CHECK_INTERVAL:
			return {}
		_looked = true
	looking = true
	var source := new_source(parent)
	var latest: Dictionary = await fetch_latest_release(source)
	source.queue_free()
	looking = false
	return latest


#* The latest release, kept as the last look (unless GitHub couldn't be reached):
static func fetch_latest_release(source: GitHubSource) -> Dictionary:
	var latest: Dictionary = await source.fetch_latest_release(GITHUB_REPOSITORY_ID, PACKAGE_NAME, "Candy Tools")
	var version := ""
	if latest.has("asset_url") and not latest.has("error"):
		version = String(latest["version"])
	if version != "" or latest.has("version"):
		set_editor_setting(SETTING_UPDATE_CHECK, {"time": Time.get_unix_time_from_system(), "version": version})
	return latest
