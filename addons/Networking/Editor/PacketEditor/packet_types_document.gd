@tool
extends RefCounted
class_name PacketTypesDocument

## Loads, validates and writes res://addons/Networking/packet_types.json.
##
## The list of legal 'Type' strings is not hard-coded here. It is parsed out of
## the DataTypeMap constant in packet_handler.gd at runtime, so adding a type to
## that map makes it appear in the editor without touching this file.

const JSON_PATH := "res://addons/Networking/packet_types.json"
const HANDLER_PATH := "res://addons/Networking/Library/packet_handler.gd"

## Only these types read a fixed 'Length' out of the schema. Everything else is
## either length-prefixed on the wire or a fixed-width primitive, so Length is
## ignored by packet_handler and is not shown in the inspector.
const LENGTH_REQUIRED_TYPES : PackedStringArray = ["BYTES"]

## Only these types carry a 'Bits' array naming the flags packed into them.
const BITS_REQUIRED_TYPES : PackedStringArray = ["BITMASK"]

## A bitmask is one byte, so it can name at most eight flags.
const MAX_BITS := 8

## Fallback used only if packet_handler.gd cannot be read or parsed.
const FALLBACK_TYPES : PackedStringArray = [
	"INT_8", "INT_16", "INT_32", "INT_64", "U_8", "U_16", "U_32", "U_64",
	"HALF", "FLOAT", "DOUBLE", "STRING", "STRING_UTF8", "BYTES", "VARIANT",
	"BITMASK",
]

## Wire cost of each type, used for the labels in the schema type dropdown.
## A negative value marks a variable-size type whose stored number is the
## size of its length prefix, so the real cost is that prefix plus the payload.
const TYPE_BYTE_COSTS : Dictionary = {
	"INT_8": 1, "U_8": 1,
	"INT_16": 2, "U_16": 2,
	"INT_32": 4, "U_32": 4,
	"INT_64": 8, "U_64": 8,
	"HALF": 2, "FLOAT": 4, "DOUBLE": 8,
	"STRING": -4, "STRING_UTF8": -4, "VARIANT": -4,
	# BYTES writes no prefix at all, so its cost is exactly the Length field.
	"BYTES": 0,
	# Eight flags folded into a single byte.
	"BITMASK": 1,
}


## Short precision note for the float types, shown beside their byte cost.
## Digit counts are decimal significant digits, derived from the IEEE 754
## significand width: 11, 24 and 53 bits including the implicit leading one.
const TYPE_PRECISION : Dictionary = {
	"HALF": "~3 digits, max 65504",
	"FLOAT": "~7 digits",
	"DOUBLE": "~16 digits",
}

## Longer precision explanation, used for the dropdown tooltip.
const TYPE_PRECISION_DETAIL : Dictionary = {
	"HALF": "11-bit significand: about 3 decimal digits. Range is only +/-65504, and integers stay exact just to 2048. Suited to normalized or small bounded values, not world coordinates.",
	"FLOAT": "24-bit significand: about 7 decimal digits. Integers stay exact to 16777216. This is the precision Godot uses for Vector2 and Vector3 in a standard build.",
	"DOUBLE": "53-bit significand: about 16 decimal digits. Integers stay exact to 2^53. Matches GDScript's native float, so this is the only type that round-trips one without loss.",
	"BITMASK": "Up to 8 booleans packed into a single byte. Name each bit below; the first name is bit 0 (value 1). Deserializes into a Dictionary of those names to true/false, so eight separate U_8 fields become one byte.",
}


## Human-readable wire cost for a type, e.g. "1 byte", "4 + n bytes".
## Returns an empty string for a type not in the table, so an unrecognized
## entry is labelled with its bare name rather than a wrong number.
func describe_type_cost(type_name: String) -> String:
	if not TYPE_BYTE_COSTS.has(type_name):
		return ""
	if type_name == "BYTES":
		return "length bytes"
	var cost : int = TYPE_BYTE_COSTS[type_name]
	if cost < 0:
		return "%d + n bytes" % absi(cost)
	if cost == 1:
		return "1 byte"
	return "%d bytes" % cost


## Type name with its cost appended, for the dropdown. Falls back to the bare
## name when the cost is unknown.
func type_dropdown_label(type_name: String) -> String:
	var cost := describe_type_cost(type_name)
	if cost == "":
		return type_name
	# Float types carry their precision alongside the size, since the two
	# together are what the choice actually turns on.
	if TYPE_PRECISION.has(type_name):
		return "%s  (%s, %s)" % [type_name, cost, TYPE_PRECISION[type_name]]
	return "%s  (%s)" % [type_name, cost]


## Tooltip text for a type in the schema dropdown, or "" when there's nothing
## worth adding beyond the label.
func type_tooltip(type_name: String) -> String:
	if TYPE_PRECISION_DETAIL.has(type_name):
		return TYPE_PRECISION_DETAIL[type_name]
	return ""

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


## True for types that carry a 'Bits' array of flag names in the schema.
func type_requires_bits(type_name: String) -> bool:
	return BITS_REQUIRED_TYPES.has(type_name)


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
			# Kept for every type, not just BITMASK, so switching a field's type
			# back and forth in one session doesn't discard the names already
			# entered. Only written to disk for types that read it.
			var bits : Array = []
			var raw_bits = chunk.get("Bits", [])
			if raw_bits is Array:
				for b in raw_bits:
					if bits.size() >= MAX_BITS:
						break
					bits.append(str(b))
			schema.append({
				"Name": str(chunk.get("Name", "")),
				"Type": str(chunk.get("Type", data_types[0] if data_types.size() > 0 else "")),
				"Length": int(chunk.get("Length", 0)),
				"Bits": bits,
			})
	return {
		"Name": str(entry.get("Name", "")),
		"_description": str(entry.get("_description", "")),
		# Absent means unrestricted, so a hand-written file that predates these
		# flags keeps working and no existing packet is silently blocked.
		"SentByServer": bool(entry.get("SentByServer", true)),
		"SentByClient": bool(entry.get("SentByClient", true)),
		# Absent means allowed, matching the direction flags, so an older file
		# keeps every transport available rather than losing all of them.
		"AllowReliable": bool(entry.get("AllowReliable", true)),
		"AllowUnreliable": bool(entry.get("AllowUnreliable", true)),
		"AllowUnsequenced": bool(entry.get("AllowUnsequenced", true)),
		"MaxBytes": int(entry.get("MaxBytes", 0)),
		"Schema": schema,
	}


func new_packet(name_hint: String = "NEW_PACKET") -> Dictionary:
	return {
		"Name": _unique_name(name_hint),
		"_description": "",
		"SentByServer": true,
		"SentByClient": true,
		"AllowReliable": true,
		"AllowUnreliable": true,
		"AllowUnsequenced": true,
		"MaxBytes": 0,
		"Schema": [],
	}


func new_schema_entry() -> Dictionary:
	var default_type := data_types[0] if data_types.size() > 0 else ""
	return {"Name": "field", "Type": default_type, "Length": 0, "Bits": []}


## A unique placeholder name for a newly added bit, so two fresh bits never
## collide and trip the duplicate check before they've been renamed.
func new_bit_name(existing: Array) -> String:
	var i := existing.size()
	while true:
		var candidate := "bit_%d" % i
		if not existing.has(candidate):
			return candidate
		i += 1
	return "bit"


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

		if not bool(p.get("SentByServer", true)) and not bool(p.get("SentByClient", true)):
			problems.append("%s has both direction toggles off, so nothing can send it." % label)

		if not bool(p.get("AllowReliable", true)) and not bool(p.get("AllowUnreliable", true)) and not bool(p.get("AllowUnsequenced", true)):
			problems.append("%s has every transport toggle off, so no send method can deliver it." % label)

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
			elif type_requires_bits(ctype):
				var bits : Array = c.get("Bits", [])
				if bits.is_empty():
					problems.append("%s, field '%s' is a %s and needs at least one named bit." % [label, cname, ctype])
				elif bits.size() > MAX_BITS:
					problems.append("%s, field '%s' names %d bits. A %s holds at most %d." % [label, cname, bits.size(), ctype, MAX_BITS])
				var seen_bits : Array = []
				for k in bits.size():
					var bname := str(bits[k]).strip_edges()
					if bname == "":
						problems.append("%s, field '%s', bit %d has no name." % [label, cname, k])
					elif seen_bits.has(bname):
						problems.append("%s, field '%s' has two bits named '%s'." % [label, cname, bname])
					else:
						seen_bits.append(bname)

	return problems


## Writes packet_types.json using tab indentation, matching the hand-written
## file's formatting. 'Length' is only emitted for types that read it.
func save_to_disk() -> bool:
	var out := "[\n"
	for i in packets.size():
		var p : Dictionary = packets[i]
		out += "\t{\n"
		out += "\t\t\"Name\": %s,\n" % JSON.stringify(str(p.get("Name", "")))
		# Written straight after Name so it reads as a header for the definition.
		# Omitted entirely when blank, to keep untouched packets tidy.
		var pdesc := str(p.get("_description", ""))
		if pdesc != "":
			out += "\t\t\"_description\": %s,\n" % JSON.stringify(pdesc)
		# Always written, including when true, so the direction of a packet is
		# readable straight from the file rather than inferred from an absence.
		out += "\t\t\"SentByServer\": %s,\n" % ("true" if bool(p.get("SentByServer", true)) else "false")
		out += "\t\t\"SentByClient\": %s,\n" % ("true" if bool(p.get("SentByClient", true)) else "false")
		out += "\t\t\"AllowReliable\": %s,\n" % ("true" if bool(p.get("AllowReliable", true)) else "false")
		out += "\t\t\"AllowUnreliable\": %s,\n" % ("true" if bool(p.get("AllowUnreliable", true)) else "false")
		out += "\t\t\"AllowUnsequenced\": %s,\n" % ("true" if bool(p.get("AllowUnsequenced", true)) else "false")
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
				var cbits : Array = c.get("Bits", [])
				# Length is written for types that read it, and also kept for any
				# type that already carried a non-zero value, so hand-authored
				# numbers aren't silently dropped by an edit session.
				var write_length := type_requires_length(ctype) or clength > 0
				# Bits only mean anything to a BITMASK. Names left behind by a
				# type change are dropped here rather than written as dead keys.
				var write_bits := type_requires_bits(ctype) and not cbits.is_empty()
				# Lines are collected first so the trailing comma can be decided
				# by position rather than by which optional keys are present.
				var lines : PackedStringArray = []
				lines.append("\t\t\t\t\"Name\": %s" % JSON.stringify(str(c.get("Name", ""))))
				lines.append("\t\t\t\t\"Type\": %s" % JSON.stringify(ctype))
				if write_length:
					lines.append("\t\t\t\t\"Length\": %d" % clength)
				if write_bits:
					# One name per line: a bitmask's names are read far more often
					# than its other fields, and this keeps them diffable.
					var bit_lines : PackedStringArray = []
					for k in cbits.size():
						bit_lines.append("\t\t\t\t\t%s" % JSON.stringify(str(cbits[k])))
					lines.append("\t\t\t\t\"Bits\": [\n%s\n\t\t\t\t]" % ",\n".join(bit_lines))
				out += "\t\t\t{\n"
				for k in lines.size():
					out += "%s%s\n" % [lines[k], "," if k < lines.size() - 1 else ""]
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
