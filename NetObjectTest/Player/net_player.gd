extends NetworkNode3D

var controlled_by_cid: int = -1

var input_axis = Vector2(0,0)

func _ready() -> void:
	Network.on_packet_received.connect(func(packet: Packet):
			if Network.is_server == false: return
			match packet.type:
				PacketTypes.CLIENT_INPUT_PACKET:
					if Network.server_interface.get_client(packet.peer).cid != controlled_by_cid: return
					
					#if Network.server_interface.get_client(packet.peer).cid != 1: return
					var input = packet.data.get("input_mask")
					var left : bool = input.get("left")
					var right : bool = input.get("right")
					var up : bool = input.get("up")
					var down : bool = input.get("down")
					var x = 0
					var y = 0
					if left:
						x -= 1
					if right:
						x += 1
					if up:
						y += 1
					if down:
						y -= 1
						
					input_axis.x = x
					input_axis.y = y
	)

func _process(delta: float) -> void:
		global_position += Vector3(0,input_axis.y*(1*delta),input_axis.x*(1*delta))
