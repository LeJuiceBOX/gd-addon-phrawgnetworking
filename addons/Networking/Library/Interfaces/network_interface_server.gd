## SERVER INTERFACE
class_name ServerNetworkInterface extends NetworkInterface

var clients: Array[NetworkConnection] = []

var _peer_to_client_map : Dictionary[ENetPacketPeer,NetworkConnection]

####################################################################################################################

func _event_connect(peer: ENetPacketPeer, data: int, channel: int):
	var c = NetworkConnection.new(peer,"UNNAMED")
	send_reliable(peer,PacketTypes.CONNECTION_ESTABLISHED,[c.cid])
	_peer_to_client_map.set(peer,c)
	clients.append(c)
	send_reliable_except(c.peer,PacketTypes.CLIENT_ADDED,[c.cid])
	Network.on_player_added.emit(c.cid)

func _event_disconnect(peer: ENetPacketPeer, data: int, channel: int):
	var c = get_client(peer)
	var cid = c.cid
	clients.erase(c)
	_peer_to_client_map.erase(peer)
	send_reliable_all(PacketTypes.CLIENT_REMOVED,[cid])
	Network.on_player_removed.emit(cid)

func _event_receive(packet : Packet):
	#print("Recieved packet: "+str(packet.type))
	pass
	
func _event_error(peer: ENetPacketPeer, data: int, channel: int):
	pass

####################################################################################################################

func get_client(peer : ENetPacketPeer) -> NetworkConnection:
	return _peer_to_client_map.get(peer)
	
####################################################################################################################

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
