# CLIENT INTERFACE
class_name ClientNetworkInterface extends BaseNetworkInterface

var server_peer: ENetPacketPeer

####################################################################################################################
## Fires when the server acknowledges the peers connection.
signal on_connection_established()
signal on_player_added()
signal on_player_removed()

####################################################################################################################

func _init(server_peer : ENetPacketPeer) -> void:
	self.server_peer = server_peer

func _event_connect(peer: ENetPacketPeer, data: int, channel: int):
	print(str(peer)," connected!")

func _event_disconnect(peer: ENetPacketPeer, data: int, channel: int):
	print(str(peer)," disconnect!")

func _event_receive(packet : Packet):
	print("Recieved packet: "+str(packet.type))
	
func _event_error(peer: ENetPacketPeer, data: int, channel: int):
	print("Error")
