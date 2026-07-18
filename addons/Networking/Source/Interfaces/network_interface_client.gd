# CLIENT INTERFACE
class_name ClientNetworkInterface extends BaseNetworkInterface

var server_peer: ENetPacketPeer

####################################################################################################################
## Fires when the server acknowledges the peers connection.
signal on_connection_established()
signal on_player_added()
signal on_player_removed()

####################################################################################################################

func send_reliable(packet_type : String, data_to_encode : Array = []):
	_send_packet_raw(server_peer,0,PacketHandler.serialize(packet_type,data_to_encode),Network.TransportType.RELIABLE)

func send_unreliable(packet_type: String, data_to_encode: Array = []):
	_send_packet_raw(server_peer,0,PacketHandler.serialize(packet_type,data_to_encode),Network.TransportType.UNRELIABLE)

func send_unsequenced(packet_type: String, data_to_encode: Array = []):
	_send_packet_raw(server_peer,0,PacketHandler.serialize(packet_type,data_to_encode),Network.TransportType.UNSEQUENCED)

####################################################################################################################

func _init(server_peer : ENetPacketPeer) -> void:
	self.server_peer = server_peer

func _event_connect(peer: ENetPacketPeer, data: int, channel: int):
	print(str(peer)," connected!")

func _event_disconnect(peer: ENetPacketPeer, data: int, channel: int):
	print(str(peer)," disconnect!")

func _event_receive(packet : Packet):
	if packet.type == "CONNECTION_ESTABLISHED":
		print("Successfuly connected to the server!")
		on_connection_established.emit()
	print("Recieved packet: "+str(packet.type))
	
func _event_error(peer: ENetPacketPeer, data: int, channel: int):
	print("Error")
