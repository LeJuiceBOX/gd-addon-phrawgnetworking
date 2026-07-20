class_name PacketHandler

## Identifies the primitive data type of a value written to or read from a
## [StreamPeerBuffer]. Use as a tag when building a custom serializer so each
## written value can be paired with the method needed to read it back.
enum DataType {
	## 8-bit signed integer. Range -128 to 127. Written with [method StreamPeer.put_8].
	INT_8,
	## 8-bit unsigned integer. Range 0 to 255. Written with [method StreamPeer.put_u8].
	U_8,
	## 16-bit signed integer. Range -32,768 to 32,767. Written with [method StreamPeer.put_16].
	INT_16,
	## 16-bit unsigned integer. Range 0 to 65,535. Written with [method StreamPeer.put_u16].
	U_16,
	## 32-bit signed integer. Written with [method StreamPeer.put_32].
	INT_32,
	## 32-bit unsigned integer. Written with [method StreamPeer.put_u32].
	U_32,
	## 64-bit signed integer. Written with [method StreamPeer.put_64].
	INT_64,
	## 64-bit unsigned integer. Values above 2^63-1 wrap, since GDScript ints are signed.
	## Written with [method StreamPeer.put_u64].
	U_64,
	## 16-bit half-precision float. Reduced range and precision. Written with [method StreamPeer.put_half].
	HALF,
	## 32-bit single-precision float. Written with [method StreamPeer.put_float].
	FLOAT,
	## 64-bit double-precision float. Matches GDScript's native float. Written with [method StreamPeer.put_double].
	DOUBLE,
	## ASCII/Latin-1 string, length-prefixed with a 32-bit int. Written with [method StreamPeer.put_string].
	STRING,
	## UTF-8 encoded string, length-prefixed with a 32-bit int. Written with [method StreamPeer.put_utf8_string].
	UTF8_STRING,
	## Raw byte block from a [PackedByteArray]. Written with [method StreamPeer.put_data].
	## No length prefix is written, so the schema must supply a fixed 'Length'.
	BYTES,
	## Arbitrary [Variant] serialized via [method @GlobalScope.var_to_bytes], then written as a byte block.
	VARIANT,
}

const DataTypeMap : Dictionary = {
	"U_8" = DataType.U_8,
	"U_16" = DataType.U_16,
	"U_32" = DataType.U_32,
	"U_64" = DataType.U_64,
	"INT_8" = DataType.INT_8,
	"INT_16" = DataType.INT_16,
	"INT_32" = DataType.INT_32,
	"INT_64" = DataType.INT_64,
	"HALF" = DataType.HALF,
	"FLOAT" = DataType.FLOAT,
	"DOUBLE" = DataType.DOUBLE,
	"STRING" = DataType.STRING,
	"STRING_UTF8" = DataType.UTF8_STRING,
	"BYTES" = DataType.BYTES,
	"VARIANT" = DataType.VARIANT,
}

class PacketDataChunk:
	var name: String
	var type: DataType
	## Holds the length in bytes. Required on DATA types, since raw byte blocks
	## are written without a length prefix and must be read back at a fixed size.
	var length: int

class PacketDefinition:
	var type_id : int
	var name : String
	var max_bytes : int
	## Whether each side is permitted to put this packet on the wire. Both
	## default to true, so a packet is unrestricted unless explicitly narrowed.
	var sent_by_server : bool
	var sent_by_client : bool
	var schema : Array[PacketDataChunk]

static var packet_defs : Array[PacketDefinition]

static var _raw_packet_defs : Array

static var def_name_map : Dictionary[String,PacketDefinition]

func _init() -> void:
	var file = FileAccess.open("res://addons/Networking/packet_types.json",FileAccess.ModeFlags.READ)
	_raw_packet_defs = JSON.parse_string(file.get_as_text())
	file.close()
	
	var index = 0
	for def in _raw_packet_defs:
		var d_name = def.get("Name")
		var d_max_bytes = def.get("MaxBytes")
		var d_schema : Array[PacketDataChunk] = []
		assert(def.has("Name"),"In packet definition "+str(index)+", the field 'Name' is missing.")
		assert(def.has("MaxBytes"),"In packet definition "+str(index)+", the field 'MaxBytes' is missing.")
		assert(def.has("Schema"),"In packet definition "+str(index)+", the field 'Schema' is missing.")
		var sub_index = 0
		for chunk in def.get("Schema"):
			var dc_name = chunk.get("Name")
			var dc_type = chunk.get("Type")
			assert(dc_name, "In packet definition '"+d_name+"' in schema index "+str(sub_index)+" the 'Name' field is missing.")
			assert(dc_type, "In packet definition '"+d_name+"' in schema index "+str(sub_index)+" the 'Type' field is missing.")
			var t = DataTypeMap.get(dc_type)
			assert(t != null, "In packet definition '"+d_name+"' in schema index "+str(sub_index)+" the type of '"+str(dc_type)+"' doesnt exist.")
			if t == DataType.BYTES:
				assert(chunk.get("Length"), "In packet definition '"+d_name+"' in schema index "+str(sub_index)+" the 'Length' field is missing. This is required for DATA types.")
			var dc = PacketDataChunk.new()
			dc.name = chunk.get("Name")
			dc.type = t as DataType
			dc.length = chunk.get("Length", 0)
			d_schema.append(dc)
			sub_index += 1
		var d_sent_by_server = def.get("SentByServer", true)
		var d_sent_by_client = def.get("SentByClient", true)
		assert(typeof(d_sent_by_server) == TYPE_BOOL, "In packet definition '"+d_name+"', the field 'SentByServer' must be true or false.")
		assert(typeof(d_sent_by_client) == TYPE_BOOL, "In packet definition '"+d_name+"', the field 'SentByClient' must be true or false.")
		assert(d_sent_by_server or d_sent_by_client, "In packet definition '"+d_name+"', both 'SentByServer' and 'SentByClient' are false, so no side can ever send it.")
		var d = PacketDefinition.new()
		d.name = d_name
		d.max_bytes = d_max_bytes
		d.sent_by_server = d_sent_by_server
		d.sent_by_client = d_sent_by_client
		d.schema = d_schema
		d.type_id = index
		def_name_map.set(d_name,d)
		packet_defs.append(d)
		index += 1

static func serialize(type : String, data_to_encode : Array):
	var def : PacketDefinition = def_name_map.get(type)
	assert(def, "Unknown packet type '" + str(type) + "'.")
	# Caught here rather than at the receiver, since a send from the wrong side
	# is a bug in local code and the stack trace is only useful at this end.
	if Network.is_server and not def.sent_by_server:
		Network.log("PacketHandler", "'" + def.name + "' is not marked as sent by the server. Not sent.", Color.ORANGE)
		return PackedByteArray()
	if not Network.is_server and not def.sent_by_client:
		Network.log("PacketHandler", "'" + def.name + "' is not marked as sent by the client. Not sent.", Color.ORANGE)
		return PackedByteArray()
	var buffer = StreamPeerBuffer.new()
	buffer.put_u8(def.type_id)
	# Walk the schema so each value is written by its declared type. If the
	# schema is empty this loop simply doesn't run, and the packet is just the
	# 1-byte type id.
	assert(data_to_encode.size() == def.schema.size(),"Missing or too many elements in data_to_encode.")
	for i in def.schema.size():
		var chunk : PacketDataChunk = def.schema[i]
		var data = data_to_encode[i]
		match chunk.type:
			DataType.INT_8:
				buffer.put_8(int(data))
			DataType.U_8:
				buffer.put_u8(int(data))
			DataType.INT_16:
				buffer.put_16(int(data))
			DataType.U_16:
				buffer.put_u16(int(data))
			DataType.INT_32:
				buffer.put_32(int(data))
			DataType.U_32:
				buffer.put_u32(int(data))
			DataType.INT_64:
				buffer.put_64(int(data))
			DataType.U_64:
				buffer.put_u64(int(data))
			DataType.HALF:
				buffer.put_half(float(data))
			DataType.FLOAT:
				buffer.put_float(float(data))
			DataType.DOUBLE:
				buffer.put_double(float(data))
			DataType.STRING:
				buffer.put_string(str(data))
			DataType.UTF8_STRING:
				buffer.put_utf8_string(str(data))
			DataType.BYTES:
				# Raw bytes, no length prefix. Reader pulls chunk.length bytes,
				# so the data written must be exactly that many.
				var pba : PackedByteArray = data
				buffer.put_data(pba)
			DataType.VARIANT:
				# var_to_bytes gives a self-describing blob, but its length isn't
				# recoverable on read without a prefix, so write one.
				var vb : PackedByteArray = var_to_bytes(data)
				buffer.put_u32(vb.size())
				buffer.put_data(vb)
	return buffer.data_array


## [param inbound] marks bytes that arrived over the wire, which are the only
## ones worth direction-checking. send_raw() re-deserializes its own outgoing
## bytes to populate on_packet_sent, and those must not be checked as if the
## local side had received them.
static func deserialize(from_peer : ENetPacketPeer, channel : int, bytes : PackedByteArray, inbound : bool = true) -> Packet:
	var buffer : StreamPeerBuffer = StreamPeerBuffer.new()
	buffer.data_array = bytes
	var type = buffer.get_u8()
	
	if type < 0 or type > packet_defs.size() - 1:
		Network.log("PacketHandler", "Unrecognized packet id '" + str(type) + "'. Dropped.", Color.ORANGE)
		return null
	# type is in range.
	var def = packet_defs[type]

	# A packet arriving on the server was sent by a client, and vice versa, so
	# the flag checked is the one describing the far side.
	if inbound:
		if Network.is_server and not def.sent_by_client:
			Network.log("PacketHandler", "Received '" + def.name + "' from a client, but it is not marked as sent by the client. Dropped.", Color.ORANGE)
			return null
		if not Network.is_server and not def.sent_by_server:
			Network.log("PacketHandler", "Received '" + def.name + "' from the server, but it is not marked as sent by the server. Dropped.", Color.ORANGE)
			return null
	
	var packet_data : Dictionary
	# Empty schema: loop doesn't run, packet_data stays empty, which is valid.
	for chunk : PacketDataChunk in def.schema:
		var res
		match chunk.type:
			DataType.INT_8:
				res = buffer.get_8()
			DataType.U_8:
				res = buffer.get_u8()
			DataType.INT_16:
				res = buffer.get_16()
			DataType.U_16:
				res = buffer.get_u16()
			DataType.INT_32:
				res = buffer.get_32()
			DataType.U_32:
				res = buffer.get_u32()
			DataType.INT_64:
				res = buffer.get_64()
			DataType.U_64:
				res = buffer.get_u64()
			DataType.HALF:
				res = buffer.get_half()
			DataType.FLOAT:
				res = buffer.get_float()
			DataType.DOUBLE:
				res = buffer.get_double()
			DataType.STRING:
				# Length-prefixed: no arg = read the 4-byte prefix, then that
				# many bytes. Don't pass chunk.length here.
				res = buffer.get_string()
			DataType.UTF8_STRING:
				res = buffer.get_utf8_string()
			DataType.BYTES:
				# Fixed-length raw bytes. get_data returns [error, PackedByteArray];
				# take element 1 for the bytes.
				var result : Array = buffer.get_data(chunk.length)
				res = result[1]
			DataType.VARIANT:
				# Read the length prefix written by serialize, then that many bytes.
				var vlen : int = buffer.get_u32()
				var vres : Array = buffer.get_data(vlen)
				res = bytes_to_var(vres[1])
		packet_data.set(chunk.name, res)
	return Packet.new(from_peer, channel, def.name, packet_data)
