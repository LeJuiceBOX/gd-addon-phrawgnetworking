@tool
extends Control

## Main screen panel for the Networking plugin. Owns nothing but the tab strip:
## each tab is one of the real editors, instanced as a child.
##
## This exists because an EditorPlugin exposes at most one main screen
## (_has_main_screen and _get_plugin_name are per-plugin), so a second top-bar
## entry is not available. Hosting both editors here keeps them under the one
## Networking plugin while leaving each editor script self-contained.

const PACKET_EDITOR := preload("res://addons/Networking/Editor/PacketEditor/packet_editor.tscn")
const OBJECT_EDITOR := preload("res://addons/Networking/Editor/ObjectEditor/object_editor.tscn")

var _tabs : TabContainer
var _packet_editor : Control
var _object_editor : Control


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_tabs = TabContainer.new()
	_tabs.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# The editors draw their own toolbars, so a tab strip flush against them
	# reads better than the boxed-in default.
	_tabs.tabs_visible = true
	add_child(_tabs)

	_packet_editor = PACKET_EDITOR.instantiate()
	_packet_editor.name = "Packets"
	_tabs.add_child(_packet_editor)

	_object_editor = OBJECT_EDITOR.instantiate()
	_object_editor.name = "Objects"
	_tabs.add_child(_object_editor)

	_apply_tab_icons()


## Tab icons are set after the children exist, since set_tab_icon indexes into
## the container. Icon names vary between editor versions, so a miss is silent
## and the tab simply shows its label.
func _apply_tab_icons() -> void:
	var theme_ := EditorInterface.get_editor_theme()
	_set_tab_icon(0, [&"Signals", &"Signal", &"Node"], theme_)
	_set_tab_icon(1, [&"NetworkBytes", &"Packet", &"Node"], theme_)


func _set_tab_icon(index: int, candidates: Array, theme_: Theme) -> void:
	if index >= _tabs.get_tab_count():
		return
	for candidate in candidates:
		if theme_.has_icon(candidate, &"EditorIcons"):
			_tabs.set_tab_icon(index, theme_.get_icon(candidate, &"EditorIcons"))
			return


## Ctrl+S reaches the plugin, not the focused tab, so every editor that has
## unsaved work is flushed rather than only the visible one.
func save_if_dirty() -> void:
	for editor in [_packet_editor, _object_editor]:
		if is_instance_valid(editor) and editor.has_method("save_if_dirty"):
			editor.save_if_dirty()
