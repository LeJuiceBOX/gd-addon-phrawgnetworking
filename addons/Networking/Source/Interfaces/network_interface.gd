@abstract class_name BaseNetworkInterface

signal packet_recieved(packet : Packet)

var active : bool = false

const MAX_EVENTS_PER_TICK = 64

@abstract func _event_connect(peer: ENetPacketPeer, data: int, channel: int)
@abstract func _event_disconnect(peer: ENetPacketPeer, data: int, channel: int)
@abstract func _event_receive(packet: Packet)
@abstract func _event_error(peer: ENetPacketPeer, data: int, channel: int)

func _send_packet_raw(peer : ENetPacketPeer, channel : int, bytes : PackedByteArray, flag : Network.TransportType):
	peer.send(channel,bytes,flag)

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
				var bytes := peer.get_packet()
				if bytes.size() < 1: continue
				var p : Packet = PacketHandler.deserialize(peer,channel,bytes) 
				packet_recieved.emit(p)
				_event_receive(p)
			ENetConnection.EVENT_ERROR:
				push_error("ENet service error")
				_event_error(peer,data,channel)
				active = false
				break
