class_name NetworkNode3D extends Node3D

static var registry: Dictionary[int,NetworkNode3D] = {}

var net_object_id: int = -1 :
	set(v):
		if is_active:
			Network.log("NetworkNode3D","["+str(net_object_id)+"] Tried to set net_object_id while active.", Color.RED)
			return
		else:
			net_object_id = v
var is_server: bool = false
var is_active: bool = false

## Do not use anywhere, only utilized on the client to set network id
func _start_(net_object_id: int):
	self.net_object_id = net_object_id
	self.is_server = false
	self.is_active = true
	registry.set(net_object_id,self)

## Fires whenever a packet is recieved by our machine.
func _packet_recieved(packet: Packet):
	pass

## Fires only when the object packet specifies my net_object_id.
func _object_packet_recieved(packet: Packet):
	pass
	
## Fires when the object is ready.
func _object_ready():
	pass

func _init():
	if Network.is_server:
		self.net_object_id = Network.server_interface.next_net_object_id
		Network.server_interface.next_net_object_id += 1
		registry.set(self.net_object_id,self)
		self.is_server = true
		self.is_active = true

func _ready() -> void:
	Network.on_packet_received.connect(func(packet : Packet):
		if is_active:
			_object_packet_recieved(packet)
			
	)
	
