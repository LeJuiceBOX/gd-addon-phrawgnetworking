@tool
extends EditorPlugin

const MAIN_PANEL := preload("res://addons/Networking/Editor/packet_editor.tscn")

var _panel_instance : Control


func _enter_tree() -> void:
	_panel_instance = MAIN_PANEL.instantiate()
	EditorInterface.get_editor_main_screen().add_child(_panel_instance)
	add_autoload_singleton("Network","res://addons/Networking/Library/network_singleton.gd")
	add_autoload_singleton("PacketTypes","res://addons/Networking/Editor/packet_types.gd")
	_make_visible(false)


func _exit_tree() -> void:
	if is_instance_valid(_panel_instance):
		_panel_instance.queue_free()
	_panel_instance = null
	remove_autoload_singleton("Network")
	remove_autoload_singleton("PacketTypes")


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if not is_instance_valid(_panel_instance):
		return
	_panel_instance.visible = visible
	if visible:
		# The main screen container can leave a hidden panel at zero size, so
		# match the parent's rect on show rather than trusting the last layout.
		var parent := EditorInterface.get_editor_main_screen()
		_panel_instance.size = parent.size
		_panel_instance.position = Vector2.ZERO


func _get_plugin_name() -> String:
	return "Packets"


func _get_plugin_icon() -> Texture2D:
	var theme_ := EditorInterface.get_editor_theme()
	# Icon names vary between editor versions, so fall back rather than warn.
	for candidate in [&"NetworkBytes", &"Signals", &"Node"]:
		if theme_.has_icon(candidate, &"EditorIcons"):
			return theme_.get_icon(candidate, &"EditorIcons")
	return null


## Godot calls this when the user hits Ctrl+S with this main screen focused.
func _save_external_data() -> void:
	if is_instance_valid(_panel_instance) and _panel_instance.has_method("save_if_dirty"):
		_panel_instance.save_if_dirty()
