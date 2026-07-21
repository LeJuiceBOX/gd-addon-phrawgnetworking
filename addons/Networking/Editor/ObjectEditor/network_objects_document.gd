@tool
extends RefCounted
class_name NetworkObjectsDocument

## Loads, validates and writes res://addons/Networking/network_objects.json.
##
## object_id is positional, matching packet_types.json: an object's id is its
## index in the array, so reordering or removing an object renumbers every
## object below it. Nothing is stored for the id; it is always derived.

const JSON_PATH := "res://addons/Networking/network_objects.json"

## SceneMode values. Stored as these strings rather than an int so the file
## stays readable and a reordering of the enum can't silently repoint a mode.
const MODE_SINGLE := "SINGLE"
const MODE_SPLIT := "SPLIT"

const SCENE_MODES : PackedStringArray = [MODE_SINGLE, MODE_SPLIT]

## Human-readable label for each mode, used in the mode dropdown.
const MODE_LABELS : Dictionary = {
	MODE_SINGLE: "Single scene  (one scene for both peers)",
	MODE_SPLIT: "Two scenes  (separate client and server scenes)",
}

## Longer explanation, used for the dropdown tooltip.
const MODE_TOOLTIPS : Dictionary = {
	MODE_SINGLE: "One scene instanced on both the server and every client. Use when the object behaves the same on each peer and needs no authority-only logic.",
	MODE_SPLIT: "A separate scene per peer: the server scene holds the authoritative state, the client scene holds the replicated representation. Use when the two sides need different nodes or scripts.",
}

## Extensions accepted by the scene pickers. Godot writes scenes as .tscn and
## .scn, so anything else is a mistake worth surfacing rather than accepting.
const SCENE_EXTENSIONS : PackedStringArray = ["tscn", "scn"]

## Root node class each split-mode slot must use. The two peers run different
## code, so the scene each one instances has to be rooted in the matching type:
## ServerNode3D holds the authoritative state, RemoteNode3D the replicated copy.
##
## A single-scene object is deliberately absent from this map. One scene runs on
## both peers, so no one root type can be correct for it and any root is allowed.
const REQUIRED_ROOT_CLASSES : Dictionary = {
	"ClientScene": "RemoteNode3D",
	"ServerScene": "ServerNode3D",
}

## Object definitions, each a Dictionary of
## {Name:String, _description:String, SceneMode:String, Scene:String,
##  ClientScene:String, ServerScene:String}.
var objects : Array = []

var backup_path : String = ""

var _load_error : String = ""


func get_load_error() -> String:
	return _load_error


func mode_label(mode: String) -> String:
	return str(MODE_LABELS.get(mode, mode))


func mode_tooltip(mode: String) -> String:
	return str(MODE_TOOLTIPS.get(mode, ""))


## True when the mode uses a separate client and server scene.
func mode_is_split(mode: String) -> bool:
	return mode == MODE_SPLIT


func load_from_disk() -> bool:
	_load_error = ""
	objects.clear()

	if not FileAccess.file_exists(JSON_PATH):
		_load_error = "No network_objects.json yet. Add an object to create one."
		return true

	var file := FileAccess.open(JSON_PATH, FileAccess.READ)
	if file == null:
		_load_error = "Can't read network_objects.json. Check file permissions."
		return false
	var text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(text)
	if parsed == null:
		_load_error = "network_objects.json isn't valid JSON. Fix it by hand, then reload."
		return false
	if not parsed is Array:
		_load_error = "network_objects.json must contain an array of objects."
		return false

	for entry in parsed:
		if not entry is Dictionary:
			continue
		objects.append(_normalize_object(entry))

	return true


## Fills in missing fields so the UI always has something well-formed to bind to.
## Unknown keys on the source dictionary are dropped on save.
##
## All three scene paths are kept in memory regardless of mode, so flipping the
## mode back and forth in one session doesn't discard a path already picked.
## Only the paths the active mode reads are written to disk.
func _normalize_object(entry: Dictionary) -> Dictionary:
	var mode := str(entry.get("SceneMode", MODE_SINGLE))
	if not SCENE_MODES.has(mode):
		mode = MODE_SINGLE
	return {
		"Name": str(entry.get("Name", "")),
		"_description": str(entry.get("_description", "")),
		"SceneMode": mode,
		"Scene": str(entry.get("Scene", "")),
		"ClientScene": str(entry.get("ClientScene", "")),
		"ServerScene": str(entry.get("ServerScene", "")),
	}


func new_object(name_hint: String = "NEW_OBJECT") -> Dictionary:
	return {
		"Name": _unique_name(name_hint),
		"_description": "",
		"SceneMode": MODE_SINGLE,
		"Scene": "",
		"ClientScene": "",
		"ServerScene": "",
	}


func _unique_name(base: String) -> String:
	var taken : Array = []
	for o in objects:
		taken.append(o.get("Name", ""))
	if not taken.has(base):
		return base
	var i := 2
	while taken.has("%s_%d" % [base, i]):
		i += 1
	return "%s_%d" % [base, i]


## Copies the current file to network_objects.json.bak. Called once when an edit
## session begins, so the pre-session state is always recoverable.
func make_backup() -> bool:
	backup_path = ""
	if not FileAccess.file_exists(JSON_PATH):
		return true
	var src := FileAccess.open(JSON_PATH, FileAccess.READ)
	if src == null:
		return false
	var contents := src.get_as_text()
	src.close()

	var target := JSON_PATH + ".bak"
	var dst := FileAccess.open(target, FileAccess.WRITE)
	if dst == null:
		return false
	dst.store_string(contents)
	dst.close()
	backup_path = target
	return true


## Human-readable name for each scene slot, used in messages and tooltips.
const SLOT_LABELS : Dictionary = {
	"Scene": "scene",
	"ClientScene": "client scene",
	"ServerScene": "server scene",
}


func slot_label(key: String) -> String:
	return str(SLOT_LABELS.get(key, key))


## Scene paths an object actually uses, as {document key: path} in display order.
## Paths the current mode ignores are not included, so validation and saving
## both see exactly what the mode reads. Keyed by document key rather than by
## label so callers can look the slot's required root class up in
## REQUIRED_ROOT_CLASSES; use slot_label() for display.
func active_scene_slots(obj: Dictionary) -> Dictionary:
	if mode_is_split(str(obj.get("SceneMode", MODE_SINGLE))):
		return {
			"ClientScene": str(obj.get("ClientScene", "")),
			"ServerScene": str(obj.get("ServerScene", "")),
		}
	return {"Scene": str(obj.get("Scene", ""))}


## Class name the root of a scene in this slot must be, or "" when any root is
## allowed. Only the split-mode slots constrain their root.
func required_root_class(key: String) -> String:
	return str(REQUIRED_ROOT_CLASSES.get(key, ""))


## True when a scene rooted in `actual` satisfies a slot requiring `required`,
## either by being that class or by extending it.
func root_class_satisfies(actual: String, required: String) -> bool:
	if actual == "" or required == "":
		return false
	return _class_inherits(actual, required, _global_class_table())


## Maps every class_name in the project to its {base, path}, so an inheritance
## chain can be walked without loading a single script.
##
## Rebuilt on each validate() rather than cached: a script added or renamed
## while the editor is open must be picked up, and the list is small.
static func _global_class_table() -> Dictionary:
	var table : Dictionary = {}
	for entry in ProjectSettings.get_global_class_list():
		var cname := str(entry.get("class", ""))
		if cname == "":
			continue
		table[cname] = {
			"base": str(entry.get("base", "")),
			"path": str(entry.get("path", "")),
		}
	return table


## True when class_name `derived` is `target`, or inherits from it through any
## number of script classes.
##
## Only script classes are walked. Once the chain reaches a built-in type the
## answer is settled, because the targets here are all script classes and a
## built-in can never inherit from one.
static func _class_inherits(derived: String, target: String, table: Dictionary) -> bool:
	var current := derived
	# Guards against a cyclic `extends` chain, which the editor tolerates in a
	# half-saved state and which would otherwise spin here forever.
	var guard := 0
	while current != "" and table.has(current) and guard < 64:
		if current == target:
			return true
		current = str(table[current]["base"])
		guard += 1
	return current == target


## Reads the root node's script class from a scene without instancing it.
## Returns "" when the scene has no scripted root or can't be read.
##
## SceneState is used rather than parsing the .tscn text because it resolves
## inherited scenes, instanced roots and uid-only references the same way the
## editor does. A node with a class_name script is stored as its built-in type
## plus a script reference, never as the class_name itself, so the script is
## what has to be inspected.
static func scene_root_class(path: String) -> String:
	if path == "" or not ResourceLoader.exists(path):
		return ""
	var packed := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_REUSE)
	if packed == null or not packed is PackedScene:
		return ""
	var state : SceneState = (packed as PackedScene).get_state()
	if state == null or state.get_node_count() == 0:
		return ""

	# Node 0 is the root. Its script may be set as a property here, or inherited
	# from a base scene, in which case the property is absent and the base
	# scene's own root carries it.
	for i in state.get_node_property_count(0):
		if str(state.get_node_property_name(0, i)) == "script":
			var scr = state.get_node_property_value(0, i)
			if scr is Script:
				return _script_class_name(scr)
			return ""

	# No script property on this root: follow the inherited scene, if any.
	var base_scene = state.get_node_instance(0)
	if base_scene is PackedScene:
		return scene_root_class((base_scene as PackedScene).resource_path)
	return ""


## The class_name a script declares, walking up to its base script when the
## script itself is anonymous. Returns "" for a script with no class_name
## anywhere in its chain.
static func _script_class_name(scr: Script) -> String:
	var current := scr
	var guard := 0
	while current != null and guard < 64:
		var cname := str(current.get_global_name())
		if cname != "":
			return cname
		current = current.get_base_script()
		guard += 1
	return ""


## Problems that would make a spawn fail at runtime. Returned as human-readable
## lines; an empty result means the file is safe to run.
func validate() -> PackedStringArray:
	var problems : PackedStringArray = []
	var seen_names : Array = []
	# Built once for the whole pass rather than per object, since every root
	# check consults the same table.
	var class_table := _global_class_table()

	for i in objects.size():
		var o : Dictionary = objects[i]
		var oname := str(o.get("Name", "")).strip_edges()
		var label := oname if oname != "" else "object %d" % i

		if oname == "":
			problems.append("Object %d has no name." % i)
		elif seen_names.has(oname):
			problems.append("Two objects are named '%s'. Names must be unique." % oname)
		else:
			seen_names.append(oname)

		var slots := active_scene_slots(o)
		for key in slots:
			var slot_name := slot_label(key)
			var path := str(slots[key]).strip_edges()
			if path == "":
				problems.append("%s has no %s set." % [label, slot_name])
				continue
			if not FileAccess.file_exists(path):
				problems.append("%s's %s points at '%s', which doesn't exist." % [label, slot_name, path])
				continue
			if not SCENE_EXTENSIONS.has(path.get_extension().to_lower()):
				problems.append("%s's %s is '%s', which isn't a scene file." % [label, slot_name, path])
				continue

			# Root type is only constrained in split mode; a shared scene runs on
			# both peers, so any root is valid for it.
			var required := required_root_class(key)
			if required == "":
				continue
			var actual := scene_root_class(path)
			if actual == "":
				problems.append("%s's %s must have a %s root, but '%s' has no script on its root node." % [
					label, slot_name, required, path.get_file()
				])
			elif not _class_inherits(actual, required, class_table):
				problems.append("%s's %s must have a %s root, but '%s' is rooted in %s." % [
					label, slot_name, required, path.get_file(), actual
				])

		# A split object pointing both slots at one file is almost certainly a
		# half-finished edit rather than an intent, since it makes the mode moot.
		if mode_is_split(str(o.get("SceneMode", MODE_SINGLE))):
			var client_path := str(o.get("ClientScene", "")).strip_edges()
			var server_path := str(o.get("ServerScene", "")).strip_edges()
			if client_path != "" and client_path == server_path:
				problems.append("%s uses the same scene for both peers. Switch it to single scene instead." % label)

	return problems


## Writes network_objects.json using tab indentation, matching the formatting of
## packet_types.json. Only the scene keys the active mode reads are emitted.
func save_to_disk() -> bool:
	var out := "[\n"
	for i in objects.size():
		var o : Dictionary = objects[i]
		out += "\t{\n"
		out += "\t\t\"Name\": %s,\n" % JSON.stringify(str(o.get("Name", "")))
		# Written straight after Name so it reads as a header for the definition.
		# Omitted entirely when blank, to keep untouched objects tidy.
		var odesc := str(o.get("_description", ""))
		if odesc != "":
			out += "\t\t\"_description\": %s,\n" % JSON.stringify(odesc)

		var mode := str(o.get("SceneMode", MODE_SINGLE))
		out += "\t\t\"SceneMode\": %s,\n" % JSON.stringify(mode)

		# Lines are collected first so the trailing comma can be decided by
		# position rather than by which mode is active.
		var lines : PackedStringArray = []
		if mode_is_split(mode):
			lines.append("\t\t\"ClientScene\": %s" % JSON.stringify(str(o.get("ClientScene", ""))))
			lines.append("\t\t\"ServerScene\": %s" % JSON.stringify(str(o.get("ServerScene", ""))))
		else:
			lines.append("\t\t\"Scene\": %s" % JSON.stringify(str(o.get("Scene", ""))))
		for k in lines.size():
			out += "%s%s\n" % [lines[k], "," if k < lines.size() - 1 else ""]

		out += "\t}%s\n" % ("," if i < objects.size() - 1 else "")
	out += "]\n"

	var file := FileAccess.open(JSON_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(out)
	file.close()
	return true
