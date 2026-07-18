extends Node

signal packet_received(packet: Packet)

			
var client_interface : ClientNetworkInterface :
	get():
		assert(_is_server == false, "Tried to access client interface from server context.")
		return _current_interface as ClientNetworkInterface
var server_interface : ServerNetworkInterface :
	get():
		assert(_is_server, "Tried to access server interface from client context.")
		return _current_interface as ServerNetworkInterface
var connection : ENetConnection
var packet_handler : PacketHandler

var _current_interface : BaseNetworkInterface
var is_active : bool = false
var _is_server : bool = false
var _packet_info : Array

enum TransportType {
	RELIABLE = ENetPacketPeer.FLAG_RELIABLE,
	UNRELIABLE = ENetPacketPeer.FLAG_UNRELIABLE_FRAGMENT,
	UNSEQUENCED = ENetPacketPeer.FLAG_UNSEQUENCED
}

func get_current_interface() -> BaseNetworkInterface:
	return _current_interface

func log(service_name : String, msg : String, color : Color = Color.WHITE):
	print_rich("[color=#%s][%s][/color] %s" % [color.to_html(false), service_name, msg])

func start_server(ip : String = "127.0.0.1", port : int = 7777):
	print("Starting server...")
	packet_handler = PacketHandler.new()
	connection = ENetConnection.new()
	get_window().title = "SERVER"
	var c = connection.create_host_bound(ip, port, 32)
	if c != OK:
		push_error("host failed")
		return
	print("Hosting at "+str(ip)+":"+str(port)+"!")
	_is_server = true
	is_active = true
	_current_interface = ServerNetworkInterface.new()
	
func start_client(connect_to_ip : String = "127.0.0.1", connect_to_port : int = 7777):
	print("Starting client...")
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
	_is_server = false
	is_active = true
	_current_interface = ClientNetworkInterface.new(server_peer)

func _physics_process(delta: float) -> void:
	if is_active:
		get_current_interface().poll()
	
