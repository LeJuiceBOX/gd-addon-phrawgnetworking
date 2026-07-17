class_name PacketHandler

enum DataType { U8, U16, U32, FLOAT, DOUBLE, STRING_UTF8, STRING, VEC2_FLOAT, VEC3_FLOAT}
const DataTypeMap : Dictionary = {
	"U8"=DataType.U8,
	"U16"=DataType.U16,
	"U32"=DataType.U32,
	"FLOAT"=DataType.FLOAT,
	"DOUBLE"=DataType.DOUBLE,
	"STRING"=DataType.STRING,
	"STRING_UTF8"=DataType.STRING_UTF8
}

class PacketDataChunk:
	var name: String
	var type: DataType
	## Holds the length in bytes, needs to be set on STRING types.
	var length: int

class PacketDefinition:
	var type_id : int
	var name : String
	var max_bytes : int
	var schema : Array[PacketDataChunk]

static var packet_defs : Array[PacketDefinition]

static var _raw_packet_defs : Array

static var def_name_map : Dictionary[String,PacketDefinition]

func _init() -> void:
	print("Hello!")
	var file = FileAccess.open("res://Networking/packet_types.json",FileAccess.ModeFlags.READ)
	_raw_packet_defs = JSON.parse_string(file.get_as_text())
	file.close()
	
	var index = 0
	for def in _raw_packet_defs:
		var d_name = def.get("Name")
		var d_max_bytes = def.get("MaxBytes")
		var d_schema : Array[PacketDataChunk] = []
		assert(d_name,"In packet definition "+str(index)+", the field 'Name' is missing.")
		assert(d_max_bytes,"In packet definition "+str(index)+", the field 'MaxBytes' is missing.")
		assert(def.get("Schema"),"In packet definition "+str(index)+", the field 'Schema' is missing.")
		var sub_index = 0
		for chunk in def.get("Schema"):
			var dc_name = chunk.get("Name")
			var dc_type = chunk.get("Type")
			assert(dc_name, "In packet definition '"+d_name+"' in schema index "+str(sub_index)+" the 'Name' field is missing.")
			assert(dc_type, "In packet definition '"+d_name+"' in schema index "+str(sub_index)+" the 'Type' field is missing.")
			var t = DataTypeMap.get(dc_type)
			assert(t != null, "In packet definition '"+d_name+"' in schema index "+str(sub_index)+" the type of '"+str(dc_type)+"' doesnt exist.")
			if t in [DataType.STRING, DataType.STRING_UTF8]:
				assert(chunk.get("Length"),"In packet definition '"+d_name+"' in schema index "+str(sub_index)+" the 'Length' fields is missing. This is required for STRING types.")
			var dc = PacketDataChunk.new()
			dc.name = chunk.get("Name")
			dc.type = t as DataType
			dc.length = chunk.get("Length", 0)
			d_schema.append(dc)
			sub_index += 1
		var d = PacketDefinition.new()
		d.name = d_name
		d.max_bytes = d_max_bytes
		d.schema = d_schema
		d.type_id = index
		def_name_map.set(d_name,d)
		packet_defs.append(d)
		index += 1

static func serialize(type : String, data_to_encode : Array):
	var def : PacketDefinition = def_name_map.get(type)
	var buffer = StreamPeerBuffer.new()
	buffer.put_u8(def.type_id)
	# Walk the schema so each value is written by its declared type. String-only
	# for now (testing): STRING -> put_string, STRING_UTF8 -> put_utf8_string.
	# Both write a 4-byte length prefix + bytes, matching the get_string()/
	# get_utf8_string() reads in deserialize().
	for i in def.schema.size():
		var chunk : PacketDataChunk = def.schema[i]
		var data = data_to_encode[i]
		match chunk.type:
			DataType.STRING:
				buffer.put_string(str(data))
			DataType.STRING_UTF8:
				buffer.put_utf8_string(str(data))
	return buffer.data_array
	

static func deserialize(from_peer : ENetPacketPeer, channel : int, bytes : PackedByteArray) -> Packet:
	var buffer : StreamPeerBuffer = StreamPeerBuffer.new()
	buffer.data_array = bytes
	var type = buffer.get_u8()
	
	if type < 0 or type > packet_defs.size()-1:
		Network.log("PacketHandler","Unrecognized packet id '"+str(type)+"'. Dropped.",Color.ORANGE)
	# type is in range.
	var def = packet_defs[type]
	
	var packet_data : Dictionary
	for chunk : PacketDataChunk in def.schema:
		var res 
		match chunk.type:
			DataType.U8:
				res = buffer.get_8()
			DataType.U16:
				res = buffer.get_u16()
			DataType.U32:
				res = buffer.get_u32()
			DataType.FLOAT:
				res = buffer.get_float()
			DataType.DOUBLE:
				res = buffer.get_double()
			DataType.STRING:
				# put_string() writes a 4-byte length prefix + bytes, so read it
				# back the same way: no length arg = read the prefix, then that
				# many bytes. Passing chunk.length here mis-reads the prefix as text.
				res = buffer.get_string()
			DataType.STRING_UTF8:
				res = buffer.get_utf8_string()
		packet_data.set(chunk.name,res)
	return Packet.new(from_peer,channel,def.name,packet_data)
