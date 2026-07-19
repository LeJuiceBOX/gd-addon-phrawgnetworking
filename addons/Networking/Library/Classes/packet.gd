## When the packet is recieved by the network interface it is deserialized into this class.

class_name Packet

var peer: ENetPacketPeer
var channel: int
var data: Dictionary
var type: String

func _init(peer : ENetPacketPeer, channel: int, type: String, data : Dictionary) -> void:
	self.peer = peer
	self.channel = channel
	self.data = data
	self.type = type
