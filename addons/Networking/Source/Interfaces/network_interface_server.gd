## SERVER INTERFACE
class_name ServerNetworkInterface extends BaseNetworkInterface

var clients: Array[ENetPacketPeer] = []


func send_reliable(peer: ENetPacketPeer, packet_type : String, data_to_encode : Array = []):
	_send_packet_raw(peer,0,PacketHandler.serialize(packet_type,data_to_encode),Network.TransportType.RELIABLE)

func send_reliable_all(packet_type: String, data_to_encode: Array = []):
	var packet = PacketHandler.serialize(packet_type,data_to_encode)
	for peer : ENetPacketPeer in clients:
		_send_packet_raw(peer,0,packet,Network.TransportType.RELIABLE)

func send_reliable_except(except_peer: ENetPacketPeer, packet_type: String, data_to_encode: Array = []):
	var packet = PacketHandler.serialize(packet_type,data_to_encode)
	for peer : ENetPacketPeer in clients:
		if peer == except_peer: continue
		_send_packet_raw(peer,0,packet,Network.TransportType.RELIABLE)	

func send_unreliable(peer: ENetPacketPeer, packet_type: String, data_to_encode: Array = []):
	_send_packet_raw(peer,0,PacketHandler.serialize(packet_type,data_to_encode),Network.TransportType.UNRELIABLE)

func send_unreliable_all(packet_type: String, data_to_encode: Array = []):
	var packet = PacketHandler.serialize(packet_type,data_to_encode)
	for peer : ENetPacketPeer in clients:
		_send_packet_raw(peer,0,packet,Network.TransportType.UNRELIABLE)

func send_unreliable_except(except_peer: ENetPacketPeer, packet_type: String, data_to_encode: Array = []):
	var packet = PacketHandler.serialize(packet_type,data_to_encode)
	for peer : ENetPacketPeer in clients:
		if peer == except_peer: continue
		_send_packet_raw(peer,0,packet,Network.TransportType.UNRELIABLE)	
		
func send_unsequenced(peer: ENetPacketPeer, packet_type: String, data_to_encode: Array = []):
	_send_packet_raw(peer,0,PacketHandler.serialize(packet_type,data_to_encode),Network.TransportType.UNSEQUENCED)

func send_unsequenced_all(packet_type: String, data_to_encode: Array = []):
	var packet = PacketHandler.serialize(packet_type,data_to_encode)
	for peer : ENetPacketPeer in clients:
		_send_packet_raw(peer,0,packet,Network.TransportType.UNSEQUENCED)

func send_unsequenced_except(except_peer : ENetPacketPeer, packet_type: String, data_to_encode: Array = []):
	var packet = PacketHandler.serialize(packet_type,data_to_encode)
	for peer : ENetPacketPeer in clients:
		if peer == except_peer: continue
		_send_packet_raw(peer,0,packet,Network.TransportType.UNSEQUENCED)

####################################################################################################################

func _event_connect(peer: ENetPacketPeer, data: int, channel: int):
	print(str(peer)," connected!")
	clients.append(peer)
	send_reliable(peer,"CONNECTION_ESTABLISHED")

func _event_disconnect(peer: ENetPacketPeer, data: int, channel: int):
	print(str(peer)," disconnect!")
	clients.erase(peer)

func _event_receive(packet : Packet):
	print("Recieved packet: "+str(packet.type))
	
func _event_error(peer: ENetPacketPeer, data: int, channel: int):
	pass
