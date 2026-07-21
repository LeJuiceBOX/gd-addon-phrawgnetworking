@abstract class_name NetworkInterface

var active : bool = false

const MAX_EVENTS_PER_TICK = 64

@abstract func _event_connect(peer: ENetPacketPeer, data: int, channel: int)
@abstract func _event_disconnect(peer: ENetPacketPeer, data: int, channel: int)
@abstract func _event_receive(packet: Packet)
@abstract func _event_error(peer: ENetPacketPeer, data: int, channel: int)

## Every send in the addon funnels through here, so this is the one place
## outbound payload bytes need to be counted. The type name is recovered from
## the leading type-id byte written by PacketHandler.serialize().
func send_raw(peer : ENetPacketPeer, channel: int, flag: Network.TransportType, bytes: PackedByteArray):
	# serialize() returns an empty array when the local side isn't permitted to
	# send this type. Sending it would put a 0-byte packet on the wire.
	if bytes.is_empty():
		return

	# Transport is chosen by which send_* method the caller used, so it isn't
	# visible to serialize(). This is the first point that knows both the
	# packet and the flag it's going out with.
	var def := PacketHandler.definition_from_bytes(bytes)
	if def != null and not PacketHandler.transport_allowed(def, flag):
		Network.log("NetworkInterface", "'" + def.name + "' is not allowed to be sent as " + PacketHandler.transport_name(flag) + ". Not sent.", Color.ORANGE)
		return

	peer.send(channel,bytes,flag)
	Network.statistics.record_out_typed(def.name if def != null else "UNKNOWN", bytes.size())
	# on_packet_sent was declared but never emitted, so the UI packet log only
	# ever showed inbound traffic. Deserializing our own bytes back into a
	# Packet is the cheapest way to give the log the same shape it expects.
	if not Network.on_packet_sent.get_connections().is_empty():
		var sent_packet = PacketHandler.deserialize(peer, channel, bytes, false)
		if sent_packet != null:
			Network.on_packet_sent.emit(sent_packet)


## Maps the first byte of a serialized packet back to its declared name.
## Returns "UNKNOWN" if the id isn't in the registry, so stats never assert
## on malformed data the way deserialize() would.
static func _type_name_of(bytes: PackedByteArray) -> String:
	var def := PacketHandler.definition_from_bytes(bytes)
	if def == null:
		return "UNKNOWN"
	return def.name
