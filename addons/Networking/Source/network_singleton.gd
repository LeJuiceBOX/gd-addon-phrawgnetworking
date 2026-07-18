extends Node

signal on_packet_received(packet: Packet)
signal on_packet_sent(packet:Packet)
			
var client_interface : ClientNetworkInterface :
	get():
		assert(is_server == false, "Tried to access client interface from server context.")
		return _current_interface as ClientNetworkInterface
var server_interface : ServerNetworkInterface :
	get():
		assert(is_server, "Tried to access server interface from client context.")
		return _current_interface as ServerNetworkInterface
var connection : ENetConnection
var packet_handler : PacketHandler

## Global payload statistics. Lives for the process, survives across
## start_server/start_client, and is reset by each of them.
var statistics : NetworkStatistics = NetworkStatistics.new()

var _current_interface : _NetworkInterface
var is_active : bool = false
var is_server : bool = false
var _packet_info : Array

enum TransportType {
	RELIABLE = ENetPacketPeer.FLAG_RELIABLE,
	UNRELIABLE = ENetPacketPeer.FLAG_UNRELIABLE_FRAGMENT,
	UNSEQUENCED = ENetPacketPeer.FLAG_UNSEQUENCED
}

func get_current_interface() -> _NetworkInterface:
	return _current_interface

func log(service_name : String, msg : String, color : Color = Color.WHITE):
	print_rich("[color=#%s][%s][/color] %s" % [color.to_html(false), service_name, msg])

func start_server(ip : String = "127.0.0.1", port : int = 7777):
	print("Starting server...")
	statistics.reset()
	packet_handler = PacketHandler.new()
	connection = ENetConnection.new()
	get_window().title = "SERVER"
	var c = connection.create_host_bound(ip, port, 32)
	if c != OK:
		push_error("host failed")
		return
	print("Hosting at "+str(ip)+":"+str(port)+"!")
	is_server = true
	is_active = true
	_current_interface = ServerNetworkInterface.new()
	
func start_client(connect_to_ip : String = "127.0.0.1", connect_to_port : int = 7777):
	print("Starting client...")
	statistics.reset()
	packet_handler = PacketHandler.new()
	connection = ENetConnection.new()
	get_window().title = "CLIENT"
	var c = connection.create_host(1)
	if c != OK:
		push_error("client host create failed")
		return
	var server_peer = connection.connect_to_host(connect_to_ip, connect_to_port, 1)
	if server_peer == null:
		push_error("connect_to_host failed")
		return
	
	print("Connecting to " + str(connect_to_ip) + ":" + str(connect_to_port))
	is_server = false
	is_active = true
	_current_interface = ClientNetworkInterface.new(server_peer)

func _physics_process(delta: float) -> void:
	if is_active:
		get_current_interface().poll()
		statistics.tick(delta)
		# RTT is a client-side notion here: the client has exactly one peer
		# (the server) to measure against. On the server there's one peer per
		# client, so a single global ping figure would be meaningless and is
		# left unsampled.
		if not is_server:
			var ci := _current_interface as ClientNetworkInterface
			if ci != null:
				statistics.sample_peer(ci.server_peer)
