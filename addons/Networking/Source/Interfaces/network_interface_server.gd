## SERVER INTERFACE
class_name ServerNetworkInterface extends BaseNetworkInterface

var clients: Array[ENetPacketPeer] = []

func send_packet_reliable(peer : ENetPacketPeer, packet_type : String, data_to_encode : Array = []):
	_send_packet_raw(peer,0,PacketHandler.serialize(packet_type,data_to_encode),Network.PacketFlag.RELIABLE)

####################################################################################################################

func _event_connect(peer: ENetPacketPeer, data: int, channel: int):
	print(str(peer)," connected!")
	clients.append(peer)
	send_packet_reliable(peer,"CONNECTION_ESTABLISHED")

func _event_disconnect(peer: ENetPacketPeer, data: int, channel: int):
	print(str(peer)," disconnect!")
	clients.erase(peer)

func _event_receive(packet : Packet):
	print("Recieved packet: "+str(packet.type))
	
func _event_error(peer: ENetPacketPeer, data: int, channel: int):
	pass
