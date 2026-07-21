extends Node

# SHARED signals
signal on_packet_received(packet: Packet)
signal on_packet_sent(packet: Packet)
signal on_player_added(cid: int)
signal on_player_removed(cid: int)
# CLIENT signals
## Fires on the client when attempting to start the server.
signal on_new_remote_object(net_id: int, node: NetworkNode3D)
signal on_local_connect_attempt()
signal on_local_connect_fail(err)
signal on_local_connect_success(cid: int)

var client_interface : ClientNetworkInterface :
	get():
		assert(is_active,"Network is not active yet, you cannot read this variable yet.")
		assert(is_server == false, "Tried to access client interface from server context.")
		return _current_interface as ClientNetworkInterface
var server_interface : ServerNetworkInterface :
	get():
		assert(is_active,"Network is not active yet, you cannot read this variable yet.")
		assert(is_server, "Tried to access server interface from client context.")
		return _current_interface as ServerNetworkInterface
var connection : ENetConnection
var packet_handler : PacketHandler
var statistics : NetworkStatistics = NetworkStatistics.new()
var net_node_registry: Dictionary[int, NetworkNode3D]

var _current_interface : NetworkInterface
var is_active : bool = false
var is_server : bool = false
var _packet_info : Array

enum TransportType {
	RELIABLE = ENetPacketPeer.FLAG_RELIABLE,
	UNRELIABLE = ENetPacketPeer.FLAG_UNRELIABLE_FRAGMENT,
	UNSEQUENCED = ENetPacketPeer.FLAG_UNSEQUENCED
}

func __on_packet_recieved(packet: Packet):
	if is_server:
		match packet.type:
			"":
				pass
	else:
		match packet.type:
			PacketTypes.CONNECTION_ESTABLISHED:
				client_interface.local_cid = packet.data.get("cid")
				on_local_connect_success.emit(client_interface.local_cid)
				Network.log("ClientNetworkInterface","Successfully connected to the server. [color=GRAY](cid: [b]"+str(client_interface.local_cid)+"[/b])[/color]")
			PacketTypes.CLIENT_ADDED:
				on_player_added.emit(packet.data.get("cid"))
				Network.log("ClientNetworkInterface","Another client joined the server. [color=GRAY](cid: [b]"+str(packet.data.get("cid"))+"[/b])[/color]")
			PacketTypes.CLIENT_REMOVED:
				on_player_removed.emit(packet.data.get("cid"))
				Network.log("ClientNetworkInterface","A client left the server. [color=GRAY](cid: [b]"+str(packet.data.get("cid"))+"[/b])[/color]")
			PacketTypes.OBJECT_SYNC_CREATE:
				var assigned_nid = packet.data.get("net_id")
				var type = packet.data.get("type")
				var n = NetworkNode3D.new()
				get_tree().current_scene.add_child(n)
				var csg = CSGBox3D.new()
				n.add_child(csg)
				on_new_remote_object.emit(assigned_nid,n)
				Network.log("ClientNetworkInterface","A new RemoteNode3D was created.",Color.WEB_GRAY)
				

	
func start_server(ip : String = "127.0.0.1", port : int = 7777):
	self.log("Network","Starting server...")
	statistics.reset()
	packet_handler = PacketHandler.new()
	connection = ENetConnection.new()
	get_window().title = "SERVER"
	var c = connection.create_host_bound(ip, port, 32)
	if c != OK:
		self.log("Network","Failed to start server. ("+str(c)+")",Color.RED)
		return
	is_server = true
	is_active = true
	_current_interface = ServerNetworkInterface.new()
	self.log("Network","Successfully started server. [color=GRAY]("+str(ip)+":"+str(port)+")[/color]")
	
func start_client(connect_to_ip : String = "127.0.0.1", connect_to_port : int = 7777):
	self.log("Network","Starting client...")
	statistics.reset()
	packet_handler = PacketHandler.new()
	connection = ENetConnection.new()
	var c = connection.create_host(1)
	if c != OK:
		self.log("Network","Failed to create client.\n[color=LIGHT_RED]"+str(c)+"[/color]")
		return false
	var server_peer = connection.connect_to_host(connect_to_ip, connect_to_port, 1)
	if server_peer == null:
		self.log("Network","Failed to connect to server. [color=GRAY]("+str(connect_to_ip)+":"+str(connect_to_port)+")[/color]")
		return false
	is_server = false
	is_active = true
	_current_interface = ClientNetworkInterface.new(server_peer)
	get_window().title = "CLIENT"


func _init() -> void:
	on_packet_received.connect(__on_packet_recieved)

func _physics_process(delta: float) -> void:
	if is_active:
		poll()
		statistics.tick(delta)
		# RTT is a client-side notion here: the client has exactly one peer
		# (the server) to measure against. On the server there's one peer per
		# client, so a single global ping figure would be meaningless and is
		# left unsampled.
		if not is_server:
			var ci = _current_interface as ClientNetworkInterface
			if ci != null:
				statistics.sample_peer(ci.server_peer)


func get_current_interface() -> NetworkInterface:
	assert(is_active,"Network is not active yet, you cannot use this function yet.")
	return _current_interface

func log(service_name : String, msg : String, color : Color = Color.WHITE):
	var my_cid
	if is_server: my_cid = "[[color=LIGHT_SALMON][b]S[/b][/color]] "
	else:
		if is_active:
			my_cid = "[[color=LIGHT_SALMON][b]"+str(client_interface.local_cid)+"[/b][/color]] "
		else:
			my_cid = ""
	print_rich(my_cid+"[[color=LIGHTBLUE]%s[/color]] [color=#%s]%s[/color]" % [service_name, color.to_html(false), msg])

static func _type_name_of(bytes: PackedByteArray) -> String:
	if bytes.size() < 1:
		return "UNKNOWN"
	var id = bytes[0]
	if id < 0 or id > PacketHandler.packet_defs.size() - 1:
		return "UNKNOWN"
	return PacketHandler.packet_defs[id].name

func poll():
	if not Network.is_active:
		return
	for _i in 64:
		var result: Array = Network.connection.service(0)
		var type: ENetConnection.EventType = result[0]
		var peer: ENetPacketPeer = result[1]
		var data: int = result[2]
		var channel: int = result[3]
		match type:
			ENetConnection.EVENT_NONE:
				break
			ENetConnection.EVENT_CONNECT:
				_current_interface._event_connect(peer,data,channel)
			ENetConnection.EVENT_DISCONNECT:
				_current_interface._event_disconnect(peer,data,channel)
				if is_server == false:
					is_active = false
				break
			ENetConnection.EVENT_RECEIVE:
				var bytes = peer.get_packet()
				if bytes.size() < 1: continue
				# Counted before the id check so dropped packets still show up
				# as consumed bandwidth, which is the point of a diagnostic.
				statistics.record_in_typed(_type_name_of(bytes), bytes.size())
				var p : Packet = PacketHandler.deserialize(peer,channel,bytes) 
				# deserialize() returns null on an unrecognized type id.
				if p == null: continue
				_current_interface._event_receive(p)
				Network.on_packet_received.emit(p)
			ENetConnection.EVENT_ERROR:
				push_error("ENet service error")
				_current_interface._event_error(peer,data,channel)
				if is_server == false:
					is_active = false
				break
