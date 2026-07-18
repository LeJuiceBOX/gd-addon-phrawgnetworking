class_name NetworkConnection

var cid: int
var display_name: String
var peer: ENetPacketPeer:
	get():
		assert(Network.is_server,"You cant access peer from client context.")
		return peer

func _init(peer: ENetPacketPeer, display_name) -> void:
	self.peer = peer
