# CLIENT INTERFACE
class_name ClientNetworkInterface extends _NetworkInterface

var server_peer: ENetPacketPeer
var local_cid: int

####################################################################################################################
## Fires when the server acknowledges the peers connection.
signal on_connection_established()
signal on_player_added()
signal on_player_removed()

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
	print(str(peer)," connected!")

func _event_disconnect(peer: ENetPacketPeer, data: int, channel: int):
	print(str(peer)," disconnect!")

func _event_receive(packet : Packet):
	if packet.type == "CONNECTION_ESTABLISHED":
		local_cid = packet.data.get("cid")
		Network.log("ClientNetworkInterface","Successfully connected to the server with cid "+str(local_cid)+"!",Color.GREEN)
		on_connection_established.emit()
	#print("Recieved packet: "+str(packet.type))
	
func _event_error(peer: ENetPacketPeer, data: int, channel: int):
	print("Error")
