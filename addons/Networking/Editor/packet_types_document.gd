@tool
extends RefCounted
class_name PacketTypesDocument

## Loads, validates and writes res://addons/Networking/packet_types.json.
##
## The list of legal 'Type' strings is not hard-coded here. It is parsed out of
## the DataTypeMap constant in packet_handler.gd at runtime, so adding a type to
## that map makes it appear in the editor without touching this file.

const JSON_PATH := "res://addons/Networking/packet_types.json"
const HANDLER_PATH := "res://addons/Networking/Source/packet_handler.gd"

## Only these types read a fixed 'Length' out of the schema. Everything else is
## either length-prefixed on the wire or a fixed-width primitive, so Length is
## ignored by packet_handler and is not shown in the inspector.
const LENGTH_REQUIRED_TYPES : PackedStringArray = ["DATA"]

## Fallback used only if packet_handler.gd cannot be read or parsed.
const FALLBACK_TYPES : PackedStringArray = [
	"8", "U8", "16", "U16", "32", "U32", "64", "U64",
	"HALF", "FLOAT", "DOUBLE", "STRING", "STRING_UTF8", "DATA", "VARIANT",
]

## Packet definitions, each a Dictionary of {Name:String, MaxBytes:int, Schema:Array}.
var packets : Array = []

## Legal values for a schema entry's 'Type' field, in declaration order.
var data_types : PackedStringArray = []

var backup_path : String = ""

var _load_error : String = ""


func get_load_error() -> String:
	return _load_error


## Reads the DataTypeMap block from packet_handler.gd and returns its keys in
## declaration order. The map uses GDScript's `"KEY" = value` dictionary form,
## so keys are matched as quoted strings on the left of an '='.
func parse_data_types() -> PackedStringArray:
	var result : PackedStringArray = []

	if not FileAccess.file_exists(HANDLER_PATH):
		push_warning("Packets: could not find %s, falling back to built-in type list." % HANDLER_PATH)
		return FALLBACK_TYPES.duplicate()

	var file := FileAccess.open(HANDLER_PATH, FileAccess.READ)
	if file == null:
		push_warning("Packets: could not open %s, falling back to built-in type list." % HANDLER_PATH)
		return FALLBACK_TYPES.duplicate()
	var source := file.get_as_text()
	file.close()

	# Isolate the DataTypeMap body so unrelated dictionaries can't leak in.
	var start := source.find("DataTypeMap")
	if start == -1:
		push_warning("Packets: no DataTypeMap found in packet_handler.gd, falling back to built-in type list.")
		return FALLBACK_TYPES.duplicate()
	var open_brace := source.find("{", start)
	var close_brace := source.find("}", open_brace)
	if open_brace == -1 or close_brace == -1:
		push_warning("Packets: DataTypeMap in packet_handler.gd is malformed, falling back to built-in type list.")
		return FALLBACK_TYPES.duplicate()
	var body := source.substr(open_brace + 1, close_brace - open_brace - 1)

	# Accept both `"KEY" = value` and `"KEY": value`, since either is valid GDScript.
	var regex := RegEx.new()
	regex.compile('"([^"]+)"\\s*[=:]')
	for m in regex.search_all(body):
		var key := m.get_string(1)
		if not result.has(key):
			result.append(key)

	if result.is_empty():
		push_warning("Packets: DataTypeMap parsed but empty, falling back to built-in type list.")
		return FALLBACK_TYPES.duplicate()

	return result


func type_requires_length(type_name: String) -> bool:
	return LENGTH_REQUIRED_TYPES.has(type_name)


func load_from_disk() -> bool:
	_load_error = ""
	data_types = parse_data_types()
	packets.clear()

	if not FileAccess.file_exists(JSON_PATH):
		_load_error = "No packet_types.json yet. Add a packet type to create one."
		return true

	var file := FileAccess.open(JSON_PATH, FileAccess.READ)
	if file == null:
		_load_error = "Can't read packet_types.json. Check file permissions."
		return false
	var text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(text)
	if parsed == null:
		_load_error = "packet_types.json isn't valid JSON. Fix it by hand, then reload."
		return false
	if not parsed is Array:
		_load_error = "packet_types.json must contain an array of packet types."
		return false

	for entry in parsed:
		if not entry is Dictionary:
			continue
		packets.append(_normalize_packet(entry))

	return true


## Fills in missing fields so the UI always has something well-formed to bind to.
## Unknown keys on the source dictionary are dropped on save.
func _normalize_packet(entry: Dictionary) -> Dictionary:
	var schema : Array = []
	var raw_schema = entry.get("Schema", [])
	if raw_schema is Array:
		for chunk in raw_schema:
			if not chunk is Dictionary:
				continue
			schema.append({
				"Name": str(chunk.get("Name", "")),
				"Type": str(chunk.get("Type", data_types[0] if data_types.size() > 0 else "")),
				"Length": int(chunk.get("Length", 0)),
			})
	return {
		"Name": str(entry.get("Name", "")),
		"MaxBytes": int(entry.get("MaxBytes", 0)),
		"Schema": schema,
	}


func new_packet(name_hint: String = "NEW_PACKET") -> Dictionary:
	return {"Name": _unique_name(name_hint), "MaxBytes": 0, "Schema": []}


func new_schema_entry() -> Dictionary:
	var default_type := data_types[0] if data_types.size() > 0 else ""
	return {"Name": "field", "Type": default_type, "Length": 0}


func _unique_name(base: String) -> String:
	var taken : Array = []
	for p in packets:
		taken.append(p.get("Name", ""))
	if not taken.has(base):
		return base
	var i := 2
	while taken.has("%s_%d" % [base, i]):
		i += 1
	return "%s_%d" % [base, i]


## Copies the current file to packet_types.json.bak. Called once when an edit
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


## Problems that would make packet_handler.gd assert at startup. Returned as
## human-readable lines; an empty result means the file is safe to run.
func validate() -> PackedStringArray:
	var problems : PackedStringArray = []
	var seen_names : Array = []

	for i in packets.size():
		var p : Dictionary = packets[i]
		var pname := str(p.get("Name", "")).strip_edges()
		var label := pname if pname != "" else "packet %d" % i

		if pname == "":
			problems.append("Packet %d has no name." % i)
		elif seen_names.has(pname):
			problems.append("Two packets are named '%s'. Names must be unique." % pname)
		else:
			seen_names.append(pname)

		var schema : Array = p.get("Schema", [])
		var seen_fields : Array = []
		for j in schema.size():
			var c : Dictionary = schema[j]
			var cname := str(c.get("Name", "")).strip_edges()
			var ctype := str(c.get("Type", ""))

			if cname == "":
				problems.append("%s, field %d has no name." % [label, j])
			elif seen_fields.has(cname):
				problems.append("%s has two fields named '%s'." % [label, cname])
			else:
				seen_fields.append(cname)

			if not data_types.has(ctype):
				problems.append("%s, field '%s' uses unknown type '%s'." % [label, cname, ctype])
			elif type_requires_length(ctype) and int(c.get("Length", 0)) <= 0:
				problems.append("%s, field '%s' is a %s and needs a length above zero." % [label, cname, ctype])

	return problems


## Writes packet_types.json using tab indentation, matching the hand-written
## file's formatting. 'Length' is only emitted for types that read it.
func save_to_disk() -> bool:
	var out := "[\n"
	for i in packets.size():
		var p : Dictionary = packets[i]
		out += "\t{\n"
		out += "\t\t\"Name\": %s,\n" % JSON.stringify(str(p.get("Name", "")))
		out += "\t\t\"MaxBytes\": %d,\n" % int(p.get("MaxBytes", 0))

		var schema : Array = p.get("Schema", [])
		if schema.is_empty():
			out += "\t\t\"Schema\": []\n"
		else:
			out += "\t\t\"Schema\": [\n"
			for j in schema.size():
				var c : Dictionary = schema[j]
				var ctype := str(c.get("Type", ""))
				var clength := int(c.get("Length", 0))
				# Length is written for types that read it, and also kept for any
				# type that already carried a non-zero value, so hand-authored
				# numbers aren't silently dropped by an edit session.
				var write_length := type_requires_length(ctype) or clength > 0
				out += "\t\t\t{\n"
				out += "\t\t\t\t\"Name\": %s,\n" % JSON.stringify(str(c.get("Name", "")))
				if write_length:
					out += "\t\t\t\t\"Type\": %s,\n" % JSON.stringify(ctype)
					out += "\t\t\t\t\"Length\": %d\n" % clength
				else:
					out += "\t\t\t\t\"Type\": %s\n" % JSON.stringify(ctype)
				out += "\t\t\t}%s\n" % ("," if j < schema.size() - 1 else "")
			out += "\t\t]\n"

		out += "\t}%s\n" % ("," if i < packets.size() - 1 else "")
	out += "]\n"

	var file := FileAccess.open(JSON_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(out)
	file.close()
	return true
