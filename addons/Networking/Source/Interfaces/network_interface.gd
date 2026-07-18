@abstract class_name _NetworkInterface

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
	peer.send(channel,bytes,flag)
	Network.statistics.record_out_typed(_type_name_of(bytes), bytes.size())
	# on_packet_sent was declared but never emitted, so the UI packet log only
	# ever showed inbound traffic. Deserializing our own bytes back into a
	# Packet is the cheapest way to give the log the same shape it expects.
	if not Network.on_packet_sent.get_connections().is_empty():
		var sent_packet = PacketHandler.deserialize(peer, channel, bytes)
		if sent_packet != null:
			Network.on_packet_sent.emit(sent_packet)


## Maps the first byte of a serialized packet back to its declared name.
## Returns "UNKNOWN" if the id isn't in the registry, so stats never assert
## on malformed data the way deserialize() would.
static func _type_name_of(bytes: PackedByteArray) -> String:
	if bytes.size() < 1:
		return "UNKNOWN"
	var id = bytes[0]
	if id < 0 or id > PacketHandler.packet_defs.size() - 1:
		return "UNKNOWN"
	return PacketHandler.packet_defs[id].name

## Call this on a fixed timestep, handles the recieved packets since last poll.
func poll():
	if not Network.is_active:
		return
	for _i in MAX_EVENTS_PER_TICK:
		var result: Array = Network.connection.service(0)
		var type: ENetConnection.EventType = result[0]
		var peer: ENetPacketPeer = result[1]
		var data: int = result[2]
		var channel: int = result[3]
		match type:
			ENetConnection.EVENT_NONE:
				break
			ENetConnection.EVENT_CONNECT:
				_event_connect(peer,data,channel)
			ENetConnection.EVENT_DISCONNECT:
				_event_disconnect(peer,data,channel)
				active = false
				break
			ENetConnection.EVENT_RECEIVE:
				var bytes = peer.get_packet()
				if bytes.size() < 1: continue
				# Counted before the id check so dropped packets still show up
				# as consumed bandwidth, which is the point of a diagnostic.
				Network.statistics.record_in_typed(_type_name_of(bytes), bytes.size())
				var p : Packet = PacketHandler.deserialize(peer,channel,bytes) 
				# deserialize() returns null on an unrecognized type id.
				if p == null: continue
				Network.on_packet_received.emit(p)
				_event_receive(p)
			ENetConnection.EVENT_ERROR:
				push_error("ENet service error")
				_event_error(peer,data,channel)
				active = false
				break
