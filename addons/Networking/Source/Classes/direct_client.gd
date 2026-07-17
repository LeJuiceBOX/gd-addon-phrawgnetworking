# This is a representation of a client connected to the server.
class_name DirectClient extends Client

var peer: ENetPacketPeer

func _init(id: int, display_name: String, peer: ENetPacketPeer) -> void:
	super._init(id,display_name)
	self.peer = peer
