## SERVER INTERFACE
class_name ServerNetworkInterface extends _NetworkInterface

var clients: Array[NetworkConnection] = []

	
func send_unreliable(peer : ENetPacketPeer, packet_type: String, data_to_encode: Array = []):
	send_raw(peer,0,Network.TransportType.UNRELIABLE,PacketHandler.serialize(packet_type,data_to_encode))

func send_reliable(peer : ENetPacketPeer, packet_type : String, data_to_encode : Array = []):
	send_raw(peer,0,Network.TransportType.RELIABLE,PacketHandler.serialize(packet_type,data_to_encode))

func send_unsequenced(peer : ENetPacketPeer, packet_type: String, data_to_encode: Array = []):
	send_raw(peer,0,Network.TransportType.UNSEQUENCED,PacketHandler.serialize(packet_type,data_to_encode))


func send_reliable_all(packet_type: String, data_to_encode: Array = []):
	var packet = PacketHandler.serialize(packet_type,data_to_encode)
	for c : NetworkConnection in clients:
		send_raw(c.peer,0,Network.TransportType.RELIABLE,packet)

func send_reliable_except(except_peer: ENetPacketPeer, packet_type: String, data_to_encode: Array = []):
	var packet = PacketHandler.serialize(packet_type,data_to_encode)
	for connection : NetworkConnection in clients:
		if connection.peer == except_peer: continue
		send_raw(connection.peer,0,Network.TransportType.RELIABLE,packet)	

func send_unreliable_all(packet_type: String, data_to_encode: Array = []):
	var packet = PacketHandler.serialize(packet_type,data_to_encode)
	for connection : NetworkConnection in clients:
		send_raw(connection.peer,0,Network.TransportType.UNRELIABLE,packet)

func send_unreliable_except(except_peer: ENetPacketPeer, packet_type: String, data_to_encode: Array = []):
	var packet = PacketHandler.serialize(packet_type,data_to_encode)
	for connection : NetworkConnection in clients:
		if connection.peer == except_peer: continue
		send_raw(connection.peer,0,Network.TransportType.UNRELIABLE,packet)	
		
func send_unsequenced_all(packet_type: String, data_to_encode: Array = []):
	var packet = PacketHandler.serialize(packet_type,data_to_encode)
	for connection : NetworkConnection in clients:
		send_raw(connection.peer,0,Network.TransportType.UNSEQUENCED,packet)	

func send_unsequenced_except(except_peer : ENetPacketPeer, packet_type: String, data_to_encode: Array = []):
	var packet = PacketHandler.serialize(packet_type,data_to_encode)
	for connection : NetworkConnection in clients:
		if connection.peer == except_peer: continue
		send_raw(connection.peer,0,Network.TransportType.UNSEQUENCED,packet)	

####################################################################################################################

func _event_connect(peer: ENetPacketPeer, data: int, channel: int):
	print(str(peer)," connected!")
	clients.append(peer)
	send_reliable(peer,"CONNECTION_ESTABLISHED")

func _event_disconnect(peer: ENetPacketPeer, data: int, channel: int):
	print(str(peer)," disconnect!")
	clients.erase(peer)

func _event_receive(packet : Packet):
	#print("Recieved packet: "+str(packet.type))
	pass
	
func _event_error(peer: ENetPacketPeer, data: int, channel: int):
	pass
