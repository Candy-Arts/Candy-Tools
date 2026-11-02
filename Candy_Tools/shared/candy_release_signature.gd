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

#? Checks that a release or documentation zip is signed by Candy Arts.
#! A copy of Candy Wizard's Release_Signature.gd: new or changed release keys go to release_keys.json too.

const Utils = preload("candy_release_utils.gd")

#^ Candy Arts' public keys - {"keys" = [{"name", "fingerprint", "public" (PEM)}]}:
const KEYS_PATH := "res://addons/Candy_Tools/shared/release_keys.json"
#^ The signature's file in a zip - the manifest's name, then this:
const SIGNATURE_SUFFIX := ".sig"

static var _hex_regex := RegEx.create_from_string(r"^([0-9a-f]{2})+\z")


#* Why a zip can't be taken for Candy Arts', or "":
#? signature - its .sig file's text ("" if none). title - what it is, for messages.
static func problem(manifest_bytes: PackedByteArray, signature: String, title: String) -> String:
	var keys := public_keys()
	if keys.is_empty():
		return "Candy Tools has no release keys (%s), so it can't tell whether a download is Candy Arts'. Get Candy Tools again from Candy Arts." % KEYS_PATH
	var text := signature.strip_edges().to_lower()
	if text == "":
		return "The %s isn't signed by Candy Arts. It was refused." % title
	if _hex_regex.search(text) != null:
		var signature_bytes := text.hex_decode()
		var digest := Utils.sha256(manifest_bytes)
		var crypto := Crypto.new()
		for key in keys:
			if crypto.verify(HashingContext.HASH_SHA256, digest, signature_bytes, key):
				return ""
	return "The %s's signature isn't Candy Arts': it isn't official, or it was changed. It was refused." % title


#* Candy Arts' public keys, empty when the file is missing or holds none:
static func public_keys() -> Array[CryptoKey]:
	var keys: Array[CryptoKey] = []
	if not FileAccess.file_exists(KEYS_PATH):
		return keys
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(KEYS_PATH))
	if not parsed is Dictionary or not parsed.get("keys") is Array:
		return keys
	for entry in parsed["keys"]:
		if not entry is Dictionary or not entry.get("public") is String:
			continue
		var key := CryptoKey.new()
		if key.load_from_string(entry["public"], true) == OK:
			keys.append(key)
	return keys


#* A key's short name - the start of its public PEM's SHA-256 (blanks removed):
static func fingerprint(public_pem: String) -> String:
	var text := public_pem
	for blank in ["\r", "\n", "\t", " "]:
		text = text.replace(blank, "")
	return Utils.sha256(text.to_utf8_buffer()).hex_encode().substr(0, 16)
