extends Node

func _ready() -> void:
	var args = OS.get_cmdline_args()
	#print(args)
	if args.has("--server"):
		Network.start_server()
		%Label.text = "[color=ORANGE]SERVER"
		#get_tree().unload_current_scene()
		get_tree().change_scene_to_file("res://NetObjectTest/server.tscn")
	elif args.has("--client"):
		await get_tree().create_timer(1).timeout
		Network.start_client()
		%Label.text = "[color=BLUE]CLIENT"
		#get_tree().unload_current_scene()
		get_tree().change_scene_to_file("res://NetObjectTest/client.tscn")	
