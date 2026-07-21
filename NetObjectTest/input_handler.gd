class_name InputHandler extends Node

var input_mask : Array[bool] = [false, false, false, false, false, false]

func send_input():
	Network.client_interface.send_unreliable(PacketTypes.CLIENT_INPUT_PACKET,[input_mask])

func _process(delta: float) -> void:
	var up = Input.is_action_pressed("up")
	var down = Input.is_action_pressed("down")
	var left = Input.is_action_pressed("left")
	var right = Input.is_action_pressed("right")
	var jump = Input.is_action_pressed("jump")
	var dirty = false
	if input_mask[0] != up:
		input_mask[0] = up
		dirty = true
	if input_mask[1] != down:
		input_mask[1] = down
		dirty = true
	if input_mask[2] != left:
		input_mask[2] = left
		dirty = true
	if input_mask[3] != right:
		input_mask[3] = right
		dirty = true
	if input_mask[4] != jump:
		input_mask[4] = jump
		dirty = true
	
	if dirty: send_input()
