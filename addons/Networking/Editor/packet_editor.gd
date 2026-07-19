@tool
extends Control

## Main screen editor for packet_types.json.
##
## type_id is positional: packet_handler.gd assigns each definition an id from
## its index in the array, and writes that id as the first byte of every packet.
## Reordering or removing a packet therefore renumbers the wire protocol. Those
## actions apply immediately and report the resulting id changes in the status bar.

var _doc : PacketTypesDocument

var _dirty := false
var _backup_made := false
var _selected := -1
var _updating_ui := false
## Notes start read-only; the toggle swaps to the raw editable source.
var _description_editing := false

# Layout
var _packet_list : ItemList
var _detail_root : VBoxContainer
var _empty_hint : Label
var _name_edit : LineEdit
var _max_bytes_spin : SpinBox
var _description_edit : TextEdit
var _description_view : RichTextLabel
var _description_toggle : Button
var _type_id_label : Label
var _schema_rows : VBoxContainer
var _schema_empty : Label
var _status_label : Label
var _status_icon : TextureRect
var _save_button : Button
var _revert_button : Button
var _move_up_button : Button
var _move_down_button : Button
var _remove_button : Button
var _confirm_dialog : ConfirmationDialog

var _pending_action := Callable()


func _ready() -> void:
	_doc = PacketTypesDocument.new()
	_build_ui()
	_reload(false)


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	# The editor main screen parents plugin panels into a container, which
	# overrides anchors. Size flags are what actually make this fill the area.
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	set_anchors_preset(Control.PRESET_FULL_RECT)
	custom_minimum_size = Vector2(0, 320)

	var theme_ := EditorInterface.get_editor_theme()

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	# --- Toolbar -----------------------------------------------------------
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 6)
	var tb_margin := MarginContainer.new()
	tb_margin.add_theme_constant_override("margin_left", 8)
	tb_margin.add_theme_constant_override("margin_right", 8)
	tb_margin.add_theme_constant_override("margin_top", 6)
	tb_margin.add_theme_constant_override("margin_bottom", 6)
	tb_margin.add_child(toolbar)
	root.add_child(tb_margin)

	_save_button = Button.new()
	_save_button.text = "Save changes"
	_save_button.icon = theme_.get_icon(&"Save", &"EditorIcons")
	_save_button.pressed.connect(_on_save_pressed)
	toolbar.add_child(_save_button)

	_revert_button = Button.new()
	_revert_button.text = "Discard changes"
	_revert_button.icon = theme_.get_icon(&"Reload", &"EditorIcons")
	_revert_button.pressed.connect(_on_revert_pressed)
	toolbar.add_child(_revert_button)

	var sep := VSeparator.new()
	toolbar.add_child(sep)

	_status_icon = TextureRect.new()
	_status_icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	_status_icon.custom_minimum_size = Vector2(18, 0)
	toolbar.add_child(_status_icon)

	_status_label = Label.new()
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.clip_text = true
	toolbar.add_child(_status_label)

	root.add_child(HSeparator.new())

	# --- Body: packet list | detail ---------------------------------------
	var split := HSplitContainer.new()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 240
	root.add_child(split)

	split.add_child(_build_list_pane(theme_))
	split.add_child(_build_detail_pane(theme_))

	# --- Confirmation dialog ----------------------------------------------
	_confirm_dialog = ConfirmationDialog.new()
	_confirm_dialog.title = "Discard changes"
	_confirm_dialog.confirmed.connect(_on_confirm_accepted)
	add_child(_confirm_dialog)


func _build_list_pane(theme_: Theme) -> Control:
	var pane := VBoxContainer.new()
	pane.custom_minimum_size = Vector2(200, 0)
	pane.add_theme_constant_override("separation", 4)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 4)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.size_flags_horizontal = Control.SIZE_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(pane)

	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "Packet types"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var add_button := Button.new()
	add_button.icon = theme_.get_icon(&"Add", &"EditorIcons")
	add_button.tooltip_text = "Add a packet type"
	add_button.flat = true
	add_button.pressed.connect(_on_add_packet)
	header.add_child(add_button)
	pane.add_child(header)

	_packet_list = ItemList.new()
	_packet_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_packet_list.allow_reselect = true
	_packet_list.item_selected.connect(_on_packet_selected)
	pane.add_child(_packet_list)

	var order_hint := Label.new()
	order_hint.text = "Order sets each type's id byte."
	order_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	order_hint.add_theme_font_size_override("font_size", 10)
	order_hint.modulate = Color(1, 1, 1, 0.6)
	pane.add_child(order_hint)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END

	_move_up_button = Button.new()
	_move_up_button.icon = theme_.get_icon(&"ArrowUp", &"EditorIcons")
	_move_up_button.tooltip_text = "Move up. Swaps this type's id with the one above."
	_move_up_button.pressed.connect(_on_move_up)
	actions.add_child(_move_up_button)

	_move_down_button = Button.new()
	_move_down_button.icon = theme_.get_icon(&"ArrowDown", &"EditorIcons")
	_move_down_button.tooltip_text = "Move down. Swaps this type's id with the one below."
	_move_down_button.pressed.connect(_on_move_down)
	actions.add_child(_move_down_button)

	_remove_button = Button.new()
	_remove_button.icon = theme_.get_icon(&"Remove", &"EditorIcons")
	_remove_button.tooltip_text = "Remove packet type. Every type below it shifts down one id."
	_remove_button.pressed.connect(_on_remove_packet)
	actions.add_child(_remove_button)

	pane.add_child(actions)
	return margin


func _build_detail_pane(theme_: Theme) -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(320, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 12)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(margin)

	var wrapper := VBoxContainer.new()
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(wrapper)

	_empty_hint = Label.new()
	_empty_hint.text = "Select a packet type to edit it."
	_empty_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_hint.modulate = Color(1, 1, 1, 0.5)
	_empty_hint.custom_minimum_size = Vector2(0, 80)
	_empty_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	wrapper.add_child(_empty_hint)

	_detail_root = VBoxContainer.new()
	_detail_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_root.add_theme_constant_override("separation", 8)
	wrapper.add_child(_detail_root)

	# Identity grid
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	_detail_root.add_child(grid)

	grid.add_child(_make_label("Name"))
	_name_edit = LineEdit.new()
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.placeholder_text = "CHAT"
	_name_edit.text_changed.connect(_on_name_changed)
	grid.add_child(_name_edit)

	grid.add_child(_make_label("Max bytes"))
	_max_bytes_spin = SpinBox.new()
	_max_bytes_spin.min_value = 0
	_max_bytes_spin.max_value = 1048576
	_max_bytes_spin.step = 1
	_max_bytes_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_max_bytes_spin.value_changed.connect(_on_max_bytes_changed)
	grid.add_child(_max_bytes_spin)

	grid.add_child(_make_label("Type id"))
	_type_id_label = Label.new()
	_type_id_label.modulate = Color(1, 1, 1, 0.7)
	grid.add_child(_type_id_label)

	var desc_header := HBoxContainer.new()
	desc_header.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var desc_label := _make_label("Notes")
	desc_header.add_child(desc_label)
	grid.add_child(desc_header)

	# View and edit states occupy the same cell; exactly one is visible.
	# The view state is a RichTextLabel because only it renders BBCode, and the
	# edit state is a TextEdit because only it accepts input.
	var desc_cell := VBoxContainer.new()
	desc_cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_cell.add_theme_constant_override("separation", 4)
	grid.add_child(desc_cell)

	var desc_row := HBoxContainer.new()
	desc_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_row.add_theme_constant_override("separation", 6)
	desc_cell.add_child(desc_row)

	var desc_stack := VBoxContainer.new()
	desc_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_row.add_child(desc_stack)

	_description_view = RichTextLabel.new()
	_description_view.bbcode_enabled = true
	_description_view.fit_content = true
	_description_view.scroll_active = false
	_description_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_description_view.custom_minimum_size = Vector2(0, 0)
	# Match the plain look of the Type id row rather than a framed input.
	_description_view.add_theme_constant_override("line_separation", 2)
	_description_view.modulate = Color(1, 1, 1, 0.7)
	desc_stack.add_child(_description_view)

	_description_edit = TextEdit.new()
	_description_edit.placeholder_text = "What this packet is for, when it's sent, anything worth remembering."
	_description_edit.custom_minimum_size = Vector2(0, 72)
	_description_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_description_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_description_edit.scroll_fit_content_height = true
	_description_edit.visible = false
	_description_edit.text_changed.connect(_on_description_changed)
	desc_stack.add_child(_description_edit)

	_description_toggle = Button.new()
	_description_toggle.flat = true
	_description_toggle.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_description_toggle.pressed.connect(_on_description_toggle)
	desc_row.add_child(_description_toggle)

	_detail_root.add_child(HSeparator.new())

	# Schema header
	var schema_header := HBoxContainer.new()
	var schema_title := Label.new()
	schema_title.text = "Schema"
	schema_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	schema_header.add_child(schema_title)

	var add_field := Button.new()
	add_field.text = "Add field"
	add_field.icon = theme_.get_icon(&"Add", &"EditorIcons")
	add_field.flat = true
	add_field.pressed.connect(_on_add_field)
	schema_header.add_child(add_field)
	_detail_root.add_child(schema_header)

	var schema_hint := Label.new()
	schema_hint.text = "Fields are written and read in this order."
	schema_hint.add_theme_font_size_override("font_size", 10)
	schema_hint.modulate = Color(1, 1, 1, 0.6)
	_detail_root.add_child(schema_hint)

	_schema_empty = Label.new()
	_schema_empty.text = "No fields. This packet is just its id byte."
	_schema_empty.modulate = Color(1, 1, 1, 0.5)
	_detail_root.add_child(_schema_empty)

	_schema_rows = VBoxContainer.new()
	_schema_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_schema_rows.add_theme_constant_override("separation", 4)
	_detail_root.add_child(_schema_rows)

	return scroll


func _make_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


# ---------------------------------------------------------------------------
# Loading / saving
# ---------------------------------------------------------------------------

func _reload(keep_selection: bool) -> void:
	var previous := _selected
	if not _doc.load_from_disk():
		_set_status(_doc.get_load_error(), true)
	_dirty = false
	_backup_made = false
	_refresh_list()
	if keep_selection and previous >= 0 and previous < _doc.packets.size():
		_select(previous)
	elif _doc.packets.size() > 0:
		_select(0)
	else:
		_select(-1)
	_refresh_status()


## Takes the one-per-session backup the first time an edit lands.
func _mark_dirty() -> void:
	if not _backup_made:
		if _doc.make_backup():
			_backup_made = true
		else:
			_set_status("Could not write the backup file. Changes are not saved.", true)
			return
	_dirty = true
	_refresh_status()


func save_if_dirty() -> void:
	if _dirty:
		_on_save_pressed()


func _on_save_pressed() -> void:
	var problems := _doc.validate()
	if problems.size() > 0:
		_set_status("Fix %d problem%s before saving: %s" % [
			problems.size(), "" if problems.size() == 1 else "s", problems[0]
		], true)
		return
	if not _doc.save_to_disk():
		_set_status("Could not write packet_types.json. Check file permissions.", true)
		return
	_dirty = false
	EditorInterface.get_resource_filesystem().scan()
	_set_status("Saved. Backup kept at packet_types.json.bak", false)


func _on_revert_pressed() -> void:
	if not _dirty:
		_reload(true)
		return
	_ask("Discard every change made since this session started?", func():
		_reload(true)
		_set_status("Reloaded from disk.", false)
	)


# ---------------------------------------------------------------------------
# Packet list
# ---------------------------------------------------------------------------

## Removes BBCode tags so text is safe for plain-text contexts like tooltips,
## which render markup literally. Only well-formed [tag] and [/tag] spans are
## stripped; a stray bracket is left alone, matching how RichTextLabel shows it.
## The [lb] and [rb] escapes become their literal brackets.
## Compiled once and reused; refreshing the list would otherwise recompile
## the pattern for every packet.
static var _bbcode_regex : RegEx = null


static func strip_bbcode(text: String) -> String:
	if text.find("[") == -1:
		return text

	# [lb] and [rb] match the tag pattern below, so swap them for placeholders
	# first and restore them afterwards. These are private-use codepoints, so
	# they cannot collide with anything the user typed.
	var lb_mark := char(0xE000)
	var rb_mark := char(0xE001)
	var protected := text.replace("[lb]", lb_mark).replace("[rb]", rb_mark)

	if _bbcode_regex == null:
		_bbcode_regex = RegEx.new()
		# A closing tag, or an opening tag with optional =value / attributes.
		_bbcode_regex.compile("\\[/?[a-zA-Z][a-zA-Z0-9_]*(=[^\\]]*)?(\\s+[^\\]]*)?\\]")
	var stripped := _bbcode_regex.sub(protected, "", true)

	return stripped.replace(lb_mark, "[").replace(rb_mark, "]")


func _refresh_list() -> void:
	_packet_list.clear()
	for i in _doc.packets.size():
		var p : Dictionary = _doc.packets[i]
		var pname := str(p.get("Name", ""))
		var field_count : int = (p.get("Schema", []) as Array).size()
		var label := "%d  %s" % [i, pname if pname != "" else "(unnamed)"]
		_packet_list.add_item(label)
		var tooltip := "%s\nid %d, %d field%s" % [
			pname, i, field_count, "" if field_count == 1 else "s"
		]
		# Tooltips render as plain text, so tags would otherwise show literally.
		var pdesc := strip_bbcode(str(p.get("_description", ""))).strip_edges()
		if pdesc != "":
			# Keep the tooltip to a readable size; the full text is in the panel.
			if pdesc.length() > 240:
				pdesc = pdesc.substr(0, 240).strip_edges() + "…"
			tooltip += "\n\n" + pdesc
		_packet_list.set_item_tooltip(i, tooltip)
	if _selected >= 0 and _selected < _packet_list.item_count:
		_packet_list.select(_selected)
	_refresh_buttons()


func _refresh_buttons() -> void:
	var has_sel := _selected >= 0 and _selected < _doc.packets.size()
	_move_up_button.disabled = not has_sel or _selected == 0
	_move_down_button.disabled = not has_sel or _selected >= _doc.packets.size() - 1
	_remove_button.disabled = not has_sel


func _select(index: int) -> void:
	_selected = index
	var valid := index >= 0 and index < _doc.packets.size()
	_detail_root.visible = valid
	_empty_hint.visible = not valid
	if valid:
		_packet_list.select(index)
		_bind_detail()
	_refresh_buttons()


func _on_packet_selected(index: int) -> void:
	_select(index)


func _on_add_packet() -> void:
	_mark_dirty()
	_doc.packets.append(_doc.new_packet())
	_refresh_list()
	_select(_doc.packets.size() - 1)
	_name_edit.grab_focus()
	_name_edit.select_all()


func _on_remove_packet() -> void:
	if _selected < 0:
		return
	var pname := str(_doc.packets[_selected].get("Name", ""))
	var trailing := _doc.packets.size() - _selected - 1
	_mark_dirty()
	_doc.packets.remove_at(_selected)
	var next : int = min(_selected, _doc.packets.size() - 1)
	_refresh_list()
	_select(next)
	if trailing > 0:
		_note("Removed '%s'. %d type%s below it shifted down one id." % [
			pname, trailing, "" if trailing == 1 else "s"
		])
	else:
		_note("Removed '%s'." % pname)


func _on_move_up() -> void:
	_move(-1)


func _on_move_down() -> void:
	_move(1)


func _move(delta: int) -> void:
	var target := _selected + delta
	if _selected < 0 or target < 0 or target >= _doc.packets.size():
		return
	var a := str(_doc.packets[_selected].get("Name", ""))
	var b := str(_doc.packets[target].get("Name", ""))
	_mark_dirty()
	var moved = _doc.packets[_selected]
	_doc.packets[_selected] = _doc.packets[target]
	_doc.packets[target] = moved
	_selected = target
	_refresh_list()
	_select(target)
	_note("%s is now id %d, %s is now id %d." % [a, target, b, target - delta])


# ---------------------------------------------------------------------------
# Detail pane
# ---------------------------------------------------------------------------

func _bind_detail() -> void:
	_updating_ui = true
	var p : Dictionary = _doc.packets[_selected]
	_name_edit.text = str(p.get("Name", ""))
	_max_bytes_spin.value = int(p.get("MaxBytes", 0))
	# Selecting a different packet always returns to the rendered view, so the
	# editor never shows one packet's raw source next to another's name.
	_description_editing = false
	_refresh_description()
	_type_id_label.text = "%d  (first byte of every %s packet)" % [
		_selected, str(p.get("Name", "")) if str(p.get("Name", "")) != "" else "packet"
	]
	_rebuild_schema_rows()
	_updating_ui = false


func _on_name_changed(new_text: String) -> void:
	if _updating_ui or _selected < 0:
		return
	_mark_dirty()
	_doc.packets[_selected]["Name"] = new_text
	var label := "%d  %s" % [_selected, new_text if new_text != "" else "(unnamed)"]
	_packet_list.set_item_text(_selected, label)
	_refresh_status()


func _on_description_toggle() -> void:
	if _selected < 0:
		return
	# Leaving edit mode commits the box, but only marks the document dirty when
	# the text actually differs, so toggling in and out is not itself an edit.
	if _description_editing:
		var current := str(_doc.packets[_selected].get("_description", ""))
		if _description_edit.text != current:
			_mark_dirty()
			_doc.packets[_selected]["_description"] = _description_edit.text
	_description_editing = not _description_editing
	_refresh_description()
	if _description_editing:
		_description_edit.grab_focus()


## Shows either the rendered BBCode or the raw editable source, and syncs the
## toggle button to match. Never writes to the document.
func _refresh_description() -> void:
	if _selected < 0:
		return
	var raw := str(_doc.packets[_selected].get("_description", ""))
	var theme_ := EditorInterface.get_editor_theme()

	_description_edit.visible = _description_editing
	_description_view.visible = not _description_editing

	if _description_editing:
		if _description_edit.text != raw:
			# Assigning text emits text_changed, which would mark the document
			# dirty for a mere view/edit swap. Suppress it.
			var was_updating := _updating_ui
			_updating_ui = true
			_description_edit.text = raw
			_updating_ui = was_updating
		_description_toggle.icon = _safe_icon(theme_, &"StatusSuccess")
		_description_toggle.text = "" if _description_toggle.icon else "Done"
		_description_toggle.tooltip_text = "Done editing. Renders the BBCode."
	else:
		if raw.strip_edges() == "":
			# Placeholder, so an empty field still reads as a field.
			_description_view.text = "[i]No notes.[/i]"
			_description_view.modulate = Color(1, 1, 1, 0.4)
		else:
			_description_view.text = raw
			_description_view.modulate = Color(1, 1, 1, 0.7)
		_description_toggle.icon = _safe_icon(theme_, &"Edit")
		_description_toggle.text = "" if _description_toggle.icon else "Edit"
		_description_toggle.tooltip_text = "Edit notes. Shows the raw BBCode source."


func _on_description_changed() -> void:
	if _updating_ui or _selected < 0:
		return
	_mark_dirty()
	_doc.packets[_selected]["_description"] = _description_edit.text


func _on_max_bytes_changed(value: float) -> void:
	if _updating_ui or _selected < 0:
		return
	_mark_dirty()
	_doc.packets[_selected]["MaxBytes"] = int(value)


func _rebuild_schema_rows() -> void:
	for child in _schema_rows.get_children():
		child.queue_free()

	var schema : Array = _doc.packets[_selected].get("Schema", [])
	_schema_empty.visible = schema.is_empty()

	for i in schema.size():
		_schema_rows.add_child(_build_schema_row(i, schema[i], schema.size()))


func _build_schema_row(index: int, chunk: Dictionary, total: int) -> Control:
	var theme_ := EditorInterface.get_editor_theme()
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 6)

	var order := Label.new()
	order.text = str(index)
	order.custom_minimum_size = Vector2(20, 0)
	order.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	order.modulate = Color(1, 1, 1, 0.5)
	row.add_child(order)

	var name_edit := LineEdit.new()
	name_edit.text = str(chunk.get("Name", ""))
	name_edit.placeholder_text = "field name"
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.size_flags_stretch_ratio = 2.0
	name_edit.text_changed.connect(func(t): _on_field_name_changed(index, t))
	row.add_child(name_edit)

	var type_option := OptionButton.new()
	type_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	type_option.size_flags_stretch_ratio = 1.5
	var current := str(chunk.get("Type", ""))
	var matched := -1
	for t in _doc.data_types.size():
		type_option.add_item(_doc.data_types[t], t)
		if _doc.data_types[t] == current:
			matched = t
	if matched >= 0:
		type_option.select(matched)
	else:
		# Preserve an unrecognized value rather than silently rewriting it.
		type_option.add_item("%s (unknown)" % current, _doc.data_types.size())
		type_option.select(type_option.item_count - 1)
	type_option.item_selected.connect(func(sel): _on_field_type_changed(index, sel))
	row.add_child(type_option)

	var length_spin := SpinBox.new()
	length_spin.min_value = 0
	length_spin.max_value = 1048576
	length_spin.step = 1
	length_spin.value = int(chunk.get("Length", 0))
	length_spin.prefix = "len "
	length_spin.custom_minimum_size = Vector2(110, 0)
	length_spin.tooltip_text = "Byte count read back for this field."
	length_spin.value_changed.connect(func(v): _on_field_length_changed(index, v))
	# Length only exists on the wire for fixed-size raw types.
	length_spin.visible = _doc.type_requires_length(current)
	row.add_child(length_spin)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(110, 0)
	spacer.visible = not length_spin.visible
	row.add_child(spacer)

	var up := Button.new()
	up.icon = theme_.get_icon(&"ArrowUp", &"EditorIcons")
	up.flat = true
	up.disabled = index == 0
	up.tooltip_text = "Move field up"
	up.pressed.connect(func(): _move_field(index, -1))
	row.add_child(up)

	var down := Button.new()
	down.icon = theme_.get_icon(&"ArrowDown", &"EditorIcons")
	down.flat = true
	down.disabled = index >= total - 1
	down.tooltip_text = "Move field down"
	down.pressed.connect(func(): _move_field(index, 1))
	row.add_child(down)

	var remove := Button.new()
	remove.icon = theme_.get_icon(&"Remove", &"EditorIcons")
	remove.flat = true
	remove.tooltip_text = "Remove field"
	remove.pressed.connect(func(): _remove_field(index))
	row.add_child(remove)

	return row


func _on_add_field() -> void:
	if _selected < 0:
		return
	_mark_dirty()
	var schema : Array = _doc.packets[_selected].get("Schema", [])
	schema.append(_doc.new_schema_entry())
	_doc.packets[_selected]["Schema"] = schema
	_rebuild_schema_rows()
	_refresh_status()


func _on_field_name_changed(index: int, text: String) -> void:
	if _updating_ui or _selected < 0:
		return
	_mark_dirty()
	_doc.packets[_selected]["Schema"][index]["Name"] = text
	_refresh_status()


func _on_field_type_changed(index: int, selection: int) -> void:
	if _updating_ui or _selected < 0:
		return
	if selection >= _doc.data_types.size():
		return
	_mark_dirty()
	var new_type := _doc.data_types[selection]
	var chunk : Dictionary = _doc.packets[_selected]["Schema"][index]
	chunk["Type"] = new_type
	# A length on a type that doesn't read it is dead weight, and the spinbox is
	# hidden for those types, so clear it here rather than stranding the value.
	if not _doc.type_requires_length(new_type):
		chunk["Length"] = 0
	# Redraw so the length field appears or disappears for the new type.
	_rebuild_schema_rows()
	_refresh_status()


func _on_field_length_changed(index: int, value: float) -> void:
	if _updating_ui or _selected < 0:
		return
	_mark_dirty()
	_doc.packets[_selected]["Schema"][index]["Length"] = int(value)
	_refresh_status()


func _move_field(index: int, delta: int) -> void:
	var schema : Array = _doc.packets[_selected].get("Schema", [])
	var target := index + delta
	if target < 0 or target >= schema.size():
		return
	_mark_dirty()
	var moved = schema[index]
	schema[index] = schema[target]
	schema[target] = moved
	_rebuild_schema_rows()


func _remove_field(index: int) -> void:
	var schema : Array = _doc.packets[_selected].get("Schema", [])
	if index < 0 or index >= schema.size():
		return
	_mark_dirty()
	schema.remove_at(index)
	_rebuild_schema_rows()
	_refresh_status()


# ---------------------------------------------------------------------------
# Status + dialogs
# ---------------------------------------------------------------------------

func _refresh_status() -> void:
	var problems := _doc.validate()
	if problems.size() > 0:
		_set_status(problems[0] if problems.size() == 1 else "%s  (+%d more)" % [problems[0], problems.size() - 1], true)
	elif _dirty:
		_set_status("Unsaved changes.", false)
	else:
		_set_status("Up to date.", false)


## Reports an id renumbering in the status bar. Validation problems still win,
## since those block saving and the note does not.
func _note(text: String) -> void:
	var problems := _doc.validate()
	if problems.size() > 0:
		_refresh_status()
		return
	_set_status(text + "  Unsaved.", false)


func _set_status(text: String, is_error: bool) -> void:
	var theme_ := EditorInterface.get_editor_theme()
	_status_label.text = text
	if is_error:
		_status_icon.texture = _safe_icon(theme_, &"StatusError")
		_status_label.modulate = theme_.get_color(&"error_color", &"Editor")
	else:
		_status_icon.texture = _safe_icon(theme_, &"StatusSuccess")
		_status_label.modulate = Color(1, 1, 1, 0.7)
	_save_button.disabled = false


## Editor icon names shift between versions; a miss should be silent.
func _safe_icon(theme_: Theme, icon_name: StringName) -> Texture2D:
	if theme_.has_icon(icon_name, &"EditorIcons"):
		return theme_.get_icon(icon_name, &"EditorIcons")
	return null


func _ask(message: String, on_confirm: Callable) -> void:
	_pending_action = on_confirm
	_confirm_dialog.dialog_text = message
	_confirm_dialog.popup_centered(Vector2i(460, 0))


func _on_confirm_accepted() -> void:
	if _pending_action.is_valid():
		_pending_action.call()
	_pending_action = Callable()
