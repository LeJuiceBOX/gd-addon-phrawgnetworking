# CLIENT INTERFACE
class_name ClientNetworkInterface extends _NetworkInterface

var server_peer: ENetPacketPeer
var local_cid: int

####################################################################################################################
## Fires when the server acknowledges the peers connection.
signal on_connection_attempt()
signal on_connection_established()

####################################################################################################################

func send_reliable(packet_type : String, data_to_encode : Array = []):
	send_raw(server_peer,0,Network.TransportType.RELIABLE,PacketHandler.serialize(packet_type,data_to_encode))

func send_unreliable(packet_type: String, data_to_encode: Array = []):
	send_raw(server_peer,0,Network.TransportType.UNRELIABLE,PacketHandler.serialize(packet_type,data_to_encode))

func send_unsequenced(packet_type: String, data_to_encode: Array = []):
	send_raw(server_peer,0,Network.TransportType.UNSEQUENCED,PacketHandler.serialize(packet_type,data_to_encode))

####################################################################################################################

func _init(server_peer : ENetPacketPeer) -> void:
	self.server_peer = server_peer

func _event_connect(peer: ENetPacketPeer, data: int, channel: int):
	pass

func _event_disconnect(peer: ENetPacketPeer, data: int, channel: int):
	pass

func _event_receive(packet : Packet):
	pass
	
	#print("Recieved packet: "+str(packet.type))
	
func _event_error(peer: ENetPacketPeer, data: int, channel: int):
	print("Error")
