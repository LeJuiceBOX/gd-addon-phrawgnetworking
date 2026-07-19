class_name NetworkConnection

static var next_cid : int = 0

var cid: int
var display_name: String
var peer: ENetPacketPeer:
	get():
		assert(Network.is_server,"You cant access peer from a client context.")
		return peer

func _init(peer: ENetPacketPeer, display_name) -> void:
	self.peer = peer
	self.display_name = display_name
	self.cid = next_cid
	next_cid += 1
