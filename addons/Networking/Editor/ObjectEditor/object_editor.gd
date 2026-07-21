@tool
extends Control

## "Objects" tab of the Networking main screen, editing network_objects.json.
##
## Hosted in the TabContainer built by packet_editor.gd rather than being its own
## main screen: an EditorPlugin exposes at most one, so both editors live under
## the single Networking plugin.
##
## object_id is positional, mirroring the packet editor: an object's id is its
## index in the array, so reordering or removing an object renumbers the ones
## below it. Those actions apply immediately and report the resulting id changes
## in the status bar.

var _doc : NetworkObjectsDocument

var _dirty := false
var _backup_made := false
var _selected := -1
var _updating_ui := false
## Notes start read-only; the toggle swaps to the raw editable source.
var _description_editing := false

# Layout
var _object_list : ItemList
var _detail_root : VBoxContainer
var _empty_hint : Label
var _name_edit : LineEdit
var _mode_option : OptionButton
var _description_edit : TextEdit
var _description_view : RichTextLabel
var _description_toggle : Button
var _object_id_label : Label
var _selection_title : Label
var _selection_hint : Label
var _single_row : Control
var _split_rows : Control
var _scene_pickers : Dictionary = {}
var _status_label : Label
var _status_icon : TextureRect
var _save_button : Button
var _revert_button : Button
var _move_up_button : Button
var _move_down_button : Button
var _remove_button : Button
var _confirm_dialog : ConfirmationDialog
var _file_dialog : EditorFileDialog

## Which document key the open file dialog is picking for.
var _picking_key := ""

var _pending_action := Callable()


func _ready() -> void:
	_doc = NetworkObjectsDocument.new()
	_build_ui()
	_reload(false)


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	# A TabContainer sizes its children itself, so this only asks to fill the
	# space it is given. Setting a full-rect preset here would fight the
	# container rather than the main screen, unlike in packet_editor.gd.
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
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

	toolbar.add_child(VSeparator.new())

	_status_icon = TextureRect.new()
	_status_icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	_status_icon.custom_minimum_size = Vector2(18, 0)
	toolbar.add_child(_status_icon)

	_status_label = Label.new()
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.clip_text = true
	toolbar.add_child(_status_label)

	root.add_child(HSeparator.new())

	# --- Body: object list | detail ---------------------------------------
	var split := HSplitContainer.new()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 240
	root.add_child(split)

	split.add_child(_build_list_pane(theme_))
	split.add_child(_build_detail_pane(theme_))

	# --- Dialogs ----------------------------------------------------------
	_confirm_dialog = ConfirmationDialog.new()
	_confirm_dialog.title = "Discard changes"
	_confirm_dialog.confirmed.connect(_on_confirm_accepted)
	add_child(_confirm_dialog)

	# One dialog reused by every picker; _picking_key says where the result goes.
	_file_dialog = EditorFileDialog.new()
	_file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	for ext in NetworkObjectsDocument.SCENE_EXTENSIONS:
		_file_dialog.add_filter("*.%s" % ext, "Scenes")
	_file_dialog.file_selected.connect(_on_scene_file_selected)
	add_child(_file_dialog)


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
	title.text = "Network objects"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var add_button := Button.new()
	add_button.icon = theme_.get_icon(&"Add", &"EditorIcons")
	add_button.tooltip_text = "Add a network object"
	add_button.flat = true
	add_button.pressed.connect(_on_add_object)
	header.add_child(add_button)
	pane.add_child(header)

	_object_list = ItemList.new()
	_object_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_object_list.allow_reselect = true
	_object_list.item_selected.connect(_on_object_selected)
	pane.add_child(_object_list)

	var order_hint := Label.new()
	order_hint.text = "Order sets each object's id."
	order_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	order_hint.add_theme_font_size_override("font_size", 10)
	order_hint.modulate = Color(1, 1, 1, 0.6)
	pane.add_child(order_hint)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END

	_move_up_button = Button.new()
	_move_up_button.icon = theme_.get_icon(&"ArrowUp", &"EditorIcons")
	_move_up_button.tooltip_text = "Move up. Swaps this object's id with the one above."
	_move_up_button.pressed.connect(_on_move_up)
	actions.add_child(_move_up_button)

	_move_down_button = Button.new()
	_move_down_button.icon = theme_.get_icon(&"ArrowDown", &"EditorIcons")
	_move_down_button.tooltip_text = "Move down. Swaps this object's id with the one below."
	_move_down_button.pressed.connect(_on_move_down)
	actions.add_child(_move_down_button)

	_remove_button = Button.new()
	_remove_button.icon = theme_.get_icon(&"Remove", &"EditorIcons")
	_remove_button.tooltip_text = "Remove object. Every object below it shifts down one id."
	_remove_button.pressed.connect(_on_remove_object)
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
	_empty_hint.text = "Select a network object to edit it."
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
	_name_edit.placeholder_text = "PLAYER"
	_name_edit.text_changed.connect(_on_name_changed)
	grid.add_child(_name_edit)

	grid.add_child(_make_label("Object id"))
	_object_id_label = Label.new()
	_object_id_label.modulate = Color(1, 1, 1, 0.7)
	grid.add_child(_object_id_label)

	grid.add_child(_make_label("Scenes"))
	_mode_option = OptionButton.new()
	_mode_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in NetworkObjectsDocument.SCENE_MODES.size():
		var mode := NetworkObjectsDocument.SCENE_MODES[i]
		_mode_option.add_item(_doc.mode_label(mode), i)
		# The popup is where per-item tooltips live; OptionButton itself only
		# has the one for whichever entry is currently selected.
		var tip := _doc.mode_tooltip(mode)
		if tip != "":
			_mode_option.get_popup().set_item_tooltip(i, tip)
	_mode_option.item_selected.connect(_on_mode_changed)
	grid.add_child(_mode_option)

	var desc_header := HBoxContainer.new()
	desc_header.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	desc_header.add_child(_make_label("Notes"))
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
	# Match the plain look of the Object id row rather than a framed input.
	_description_view.add_theme_constant_override("line_separation", 2)
	_description_view.modulate = Color(1, 1, 1, 0.7)
	desc_stack.add_child(_description_view)

	_description_edit = TextEdit.new()
	_description_edit.placeholder_text = "What this object is, when it's spawned, anything worth remembering."
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

	# --- Object selection area --------------------------------------------
	# Sits below the identity fields, and swaps between one picker and two
	# depending on the scene mode above it.
	_selection_title = Label.new()
	_selection_title.text = "Object selection"
	_detail_root.add_child(_selection_title)

	_selection_hint = Label.new()
	_selection_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_selection_hint.add_theme_font_size_override("font_size", 10)
	_selection_hint.modulate = Color(1, 1, 1, 0.6)
	_detail_root.add_child(_selection_hint)

	_single_row = _build_scene_picker(
		theme_, "Scene", "Scene",
		"Instanced on both the server and every client. Any root node type."
	)
	_detail_root.add_child(_single_row)

	_split_rows = VBoxContainer.new()
	_split_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_split_rows.add_theme_constant_override("separation", 4)
	_split_rows.add_child(_build_scene_picker(
		theme_, "ClientScene", "Client scene",
		"Instanced on each connecting client. Root must be a %s." % _doc.required_root_class("ClientScene")
	))
	_split_rows.add_child(_build_scene_picker(
		theme_, "ServerScene", "Server scene",
		"Instanced on the server, holding the authoritative state. Root must be a %s." % _doc.required_root_class("ServerScene")
	))
	_detail_root.add_child(_split_rows)

	return scroll


## One labelled row of {path field, browse, clear} bound to a document key.
## The controls are recorded in _scene_pickers so binding can find them by key
## rather than by walking the tree.
func _build_scene_picker(theme_: Theme, key: String, label_text: String, hint: String) -> Control:
	var cell := VBoxContainer.new()
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.add_theme_constant_override("separation", 2)

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 6)
	cell.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(88, 0)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)

	# Editable rather than read-only, so a path can be pasted or hand-corrected
	# without opening the dialog.
	var path_edit := LineEdit.new()
	path_edit.placeholder_text = "res://path/to/scene.tscn"
	path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	path_edit.text_changed.connect(func(t): _on_scene_path_changed(key, t))
	row.add_child(path_edit)

	var browse := Button.new()
	browse.icon = _safe_icon(theme_, &"Folder")
	browse.text = "" if browse.icon else "Browse"
	browse.tooltip_text = "Pick a scene file."
	browse.pressed.connect(func(): _open_scene_dialog(key))
	row.add_child(browse)

	# Opening the scene is the usual next step after picking one, so it is worth
	# a button rather than a trip through the FileSystem dock.
	var open := Button.new()
	open.icon = _safe_icon(theme_, &"Load")
	open.text = "" if open.icon else "Open"
	open.tooltip_text = "Open this scene in the editor."
	open.pressed.connect(func(): _open_scene_in_editor(key))
	row.add_child(open)

	var clear := Button.new()
	clear.icon = _safe_icon(theme_, &"Remove")
	clear.text = "" if clear.icon else "Clear"
	clear.tooltip_text = "Clear this scene."
	clear.pressed.connect(func(): _on_scene_path_cleared(key))
	row.add_child(clear)

	var hint_label := Label.new()
	hint_label.text = hint
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.add_theme_font_size_override("font_size", 10)
	hint_label.modulate = Color(1, 1, 1, 0.45)
	cell.add_child(hint_label)

	# Sits under the hint and reports what the picked scene's root actually is,
	# so a wrong root is visible at the field rather than only in the status bar.
	var root_label := Label.new()
	root_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root_label.add_theme_font_size_override("font_size", 10)
	root_label.visible = false
	cell.add_child(root_label)

	_scene_pickers[key] = {"edit": path_edit, "open": open, "root": root_label}
	return cell


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
	if keep_selection and previous >= 0 and previous < _doc.objects.size():
		_select(previous)
	elif _doc.objects.size() > 0:
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


## Path of the generated class file. Written on every save so the constants
## always match the JSON, and registered as the ObjectTypes autoload by
## plugin.gd.
const GENERATED_PATH := "res://addons/Networking/Editor/ObjectEditor/object_types.gd"


func _on_save_pressed() -> void:
	var problems := _doc.validate()
	if problems.size() > 0:
		_set_status("Fix %d problem%s before saving: %s" % [
			problems.size(), "" if problems.size() == 1 else "s", problems[0]
		], true)
		return
	if not _doc.save_to_disk():
		_set_status("Could not write network_objects.json. Check file permissions.", true)
		return
	_dirty = false

	# The generated file is an open script in the editor as often as not, and
	# rewriting it underneath an open tab leaves that tab showing stale text.
	force_close_script(GENERATED_PATH)
	if not _write_object_types():
		_set_status("Saved the JSON, but could not write object_types.gd.", true)
		return

	EditorInterface.get_resource_filesystem().scan()
	_set_status("Saved. Backup kept at network_objects.json.bak", false)


## Closes the generated script if the editor has it open, so a save is not
## shadowed by an open tab holding the previous text.
func force_close_script(path: String) -> void:
	var se := EditorInterface.get_script_editor()
	var scripts := se.get_open_scripts()
	var editors := se.get_open_script_editors()
	for i in scripts.size():
		if scripts[i].resource_path == path:
			editors[i].queue_free()
			return


## Rebuilds object_types.gd from the document. Each object becomes a String
## constant holding its own name, matching how packet_types.gd exposes packets,
## so call sites read ObjectTypes.PLAYER rather than a bare literal.
func _write_object_types() -> bool:
	var file := FileAccess.open(GENERATED_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Failed to open object_types.gd. Error code: %d" % FileAccess.get_open_error())
		return false

	file.store_string("#Note: Do not edit this file, it is managed by an editor script using the data in`/Networking/network_objects.json`.\n")
	file.store_string("extends Node\n\n")
	for i in _doc.objects.size():
		var def : Dictionary = _doc.objects[i]
		var oname = def.get("Name")
		if i > 0:
			file.store_string("\n")
		file.store_string(_build_doc_comment(def, i))
		file.store_string("var " + str(oname) + ": String = \"" + str(oname) + "\"\n")
	file.close()
	return true


## Builds the '##' doc comment written above an object's constant in
## object_types.gd. The editor's notes field is BBCode, but a doc comment only
## renders a subset of it, so colour tags are dropped and the tags Godot does
## understand ([b], [i], [code]) are passed through unchanged.
func _build_doc_comment(obj: Dictionary, index: int) -> String:
	var lines : PackedStringArray = []

	var notes := _strip_color(str(obj.get("_description", ""))).strip_edges()
	if notes != "":
		for raw_line in notes.split("\n"):
			# A tab collapses to a single space in a doc comment, so any
			# hand-made column alignment in the notes is lost either way.
			# Collapsing it here at least keeps the line from looking ragged.
			# A [codeblock] in the notes would also close the one opened for
			# the scene list below, so the tag is defanged rather than passed on.
			var safe := _collapse_tabs(raw_line)
			safe = safe.replace("[codeblock]", "[lb]codeblock[rb]")
			safe = safe.replace("[/codeblock]", "[lb]/codeblock[rb]")
			lines.append(safe)
		lines.append("")

	lines.append("[b]Object id:[/b] %d" % index)

	var mode := str(obj.get("SceneMode", NetworkObjectsDocument.MODE_SINGLE))
	if _doc.mode_is_split(mode):
		lines.append("[b]Scenes:[/b] one per peer")
	else:
		lines.append("[b]Scenes:[/b] one shared by both peers")

	# Paths are padded to a common width so they line up. This sits in a
	# codeblock because that is the only doc context where the padding
	# survives as written.
	var slots := _doc.active_scene_slots(obj)
	var width := 0
	for key in slots:
		width = maxi(width, _doc.slot_label(key).length())
	lines.append("[codeblock]")
	for key in slots:
		var path := str(slots[key]).strip_edges()
		var required := _doc.required_root_class(key)
		var suffix := ""
		if required != "":
			suffix = "  (root: %s)" % required
		lines.append("%s  %s%s" % [
			_doc.slot_label(key).rpad(width), path if path != "" else "(none)", suffix
		])
	lines.append("[/codeblock]")

	var out := ""
	for line in lines:
		# An empty line still needs its marker, or the comment block breaks in
		# two and only the second half attaches to the variable.
		out += ("## " + line).rstrip(" ") + "\n"
	return out


## Removes [color=...] and [/color]. Godot's doc renderer ignores colour tags
## and would print them literally, unlike [b]/[i]/[code] which it renders.
static var _color_regex : RegEx = null


static func _strip_color(text: String) -> String:
	if text.find("[") == -1:
		return text
	if _color_regex == null:
		_color_regex = RegEx.new()
		_color_regex.compile("\\[/?color(=[^\\]]*)?\\]")
	return _color_regex.sub(text, "", true)


static func _collapse_tabs(text: String) -> String:
	var result := text
	while result.find("\t\t") != -1:
		result = result.replace("\t\t", "\t")
	return result.replace("\t", " ").rstrip(" ")


func _on_revert_pressed() -> void:
	if not _dirty:
		_reload(true)
		return
	_ask("Discard every change made since this session started?", func():
		_reload(true)
		_set_status("Reloaded from disk.", false)
	)


# ---------------------------------------------------------------------------
# Object list
# ---------------------------------------------------------------------------

## Removes BBCode tags so text is safe for plain-text contexts like tooltips,
## which render markup literally. Only well-formed [tag] and [/tag] spans are
## stripped; a stray bracket is left alone, matching how RichTextLabel shows it.
## The [lb] and [rb] escapes become their literal brackets.
## Compiled once and reused; refreshing the list would otherwise recompile
## the pattern for every object.
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
	_object_list.clear()
	for i in _doc.objects.size():
		var o : Dictionary = _doc.objects[i]
		var oname := str(o.get("Name", ""))
		var label := "%d  %s" % [i, oname if oname != "" else "(unnamed)"]
		_object_list.add_item(label)
		_refresh_item_tooltip(i)
	if _selected >= 0 and _selected < _object_list.item_count:
		_object_list.select(_selected)
	_refresh_buttons()


## Rebuilds one row's tooltip from the document. Kept separate so editing a
## scene path can refresh just the affected row rather than the whole list.
func _refresh_item_tooltip(index: int) -> void:
	if index < 0 or index >= _doc.objects.size() or index >= _object_list.item_count:
		return
	var o : Dictionary = _doc.objects[index]
	var mode := str(o.get("SceneMode", NetworkObjectsDocument.MODE_SINGLE))
	var mode_text := "two scenes" if _doc.mode_is_split(mode) else "single scene"
	var tooltip := "%s\nid %d, %s" % [str(o.get("Name", "")), index, mode_text]
	var slots := _doc.active_scene_slots(o)
	for key in slots:
		var path := str(slots[key]).strip_edges()
		tooltip += "\n%s: %s" % [_doc.slot_label(key), path if path != "" else "(none)"]
	# Tooltips render as plain text, so tags would otherwise show literally.
	var odesc := strip_bbcode(str(o.get("_description", ""))).strip_edges()
	if odesc != "":
		# Keep the tooltip to a readable size; the full text is in the panel.
		if odesc.length() > 240:
			odesc = odesc.substr(0, 240).strip_edges() + "…"
		tooltip += "\n\n" + odesc
	_object_list.set_item_tooltip(index, tooltip)


func _refresh_buttons() -> void:
	var has_sel := _selected >= 0 and _selected < _doc.objects.size()
	_move_up_button.disabled = not has_sel or _selected == 0
	_move_down_button.disabled = not has_sel or _selected >= _doc.objects.size() - 1
	_remove_button.disabled = not has_sel


func _select(index: int) -> void:
	_selected = index
	var valid := index >= 0 and index < _doc.objects.size()
	_detail_root.visible = valid
	_empty_hint.visible = not valid
	if valid:
		_object_list.select(index)
		_bind_detail()
	_refresh_buttons()


func _on_object_selected(index: int) -> void:
	_select(index)


func _on_add_object() -> void:
	_mark_dirty()
	_doc.objects.append(_doc.new_object())
	_refresh_list()
	_select(_doc.objects.size() - 1)
	_name_edit.grab_focus()
	_name_edit.select_all()


func _on_remove_object() -> void:
	if _selected < 0:
		return
	var oname := str(_doc.objects[_selected].get("Name", ""))
	var trailing := _doc.objects.size() - _selected - 1
	_mark_dirty()
	_doc.objects.remove_at(_selected)
	var next : int = min(_selected, _doc.objects.size() - 1)
	_refresh_list()
	_select(next)
	if trailing > 0:
		_note("Removed '%s'. %d object%s below it shifted down one id." % [
			oname, trailing, "" if trailing == 1 else "s"
		])
	else:
		_note("Removed '%s'." % oname)


func _on_move_up() -> void:
	_move(-1)


func _on_move_down() -> void:
	_move(1)


func _move(delta: int) -> void:
	var target := _selected + delta
	if _selected < 0 or target < 0 or target >= _doc.objects.size():
		return
	var a := str(_doc.objects[_selected].get("Name", ""))
	var b := str(_doc.objects[target].get("Name", ""))
	_mark_dirty()
	var moved = _doc.objects[_selected]
	_doc.objects[_selected] = _doc.objects[target]
	_doc.objects[target] = moved
	_selected = target
	_refresh_list()
	_select(target)
	_note("%s is now id %d, %s is now id %d." % [a, target, b, target - delta])


# ---------------------------------------------------------------------------
# Detail pane
# ---------------------------------------------------------------------------

func _bind_detail() -> void:
	_updating_ui = true
	var o : Dictionary = _doc.objects[_selected]
	_name_edit.text = str(o.get("Name", ""))
	_object_id_label.text = "%d" % _selected

	var mode := str(o.get("SceneMode", NetworkObjectsDocument.MODE_SINGLE))
	var mode_index : int = NetworkObjectsDocument.SCENE_MODES.find(mode)
	_mode_option.selected = maxi(mode_index, 0)

	# Every path is bound, not just the active mode's, so switching modes shows
	# whatever was already picked rather than a blank field.
	for key in _scene_pickers:
		var edit : LineEdit = _scene_pickers[key]["edit"]
		edit.text = str(o.get(key, ""))

	# Selecting a different object always returns to the rendered view, so the
	# editor never shows one object's raw source next to another's name.
	_description_editing = false
	_refresh_description()
	_refresh_selection_area()
	_updating_ui = false


## Shows one picker or two, matching the scene mode.
func _refresh_selection_area() -> void:
	if _selected < 0:
		return
	var mode := str(_doc.objects[_selected].get("SceneMode", NetworkObjectsDocument.MODE_SINGLE))
	var split := _doc.mode_is_split(mode)
	_single_row.visible = not split
	_split_rows.visible = split
	if split:
		_selection_hint.text = "Pick the scene each peer instances. The two must differ; use single scene if they don't."
	else:
		_selection_hint.text = "Pick the scene instanced on every peer."

	# The open button is only meaningful once a path points at a real file.
	for key in _scene_pickers:
		var path := str(_doc.objects[_selected].get(key, "")).strip_edges()
		var exists := path != "" and FileAccess.file_exists(path)
		_scene_pickers[key]["open"].disabled = not exists
		_refresh_root_label(key, path, exists)


## Reports the root class of the scene in one picker, and whether it satisfies
## that slot's requirement. Hidden when the slot constrains nothing or there is
## no scene to report on.
func _refresh_root_label(key: String, path: String, exists: bool) -> void:
	var label : Label = _scene_pickers[key]["root"]
	var required := _doc.required_root_class(key)
	if required == "" or not exists:
		label.visible = false
		return

	var theme_ := EditorInterface.get_editor_theme()
	var actual := NetworkObjectsDocument.scene_root_class(path)
	label.visible = true
	if actual == "":
		label.text = "Root has no script. Needs %s." % required
		label.modulate = theme_.get_color(&"error_color", &"Editor")
	elif _doc.root_class_satisfies(actual, required):
		# Naming the actual class is worth it when it is a subclass, since that
		# is the case a reader is most likely to want confirmed.
		if actual == required:
			label.text = "Root: %s" % actual
		else:
			label.text = "Root: %s, extends %s." % [actual, required]
		label.modulate = _ok_color(theme_)
	else:
		label.text = "Root is %s. Needs %s." % [actual, required]
		label.modulate = theme_.get_color(&"error_color", &"Editor")


## Colour for a satisfied requirement. Only error_color is relied on elsewhere
## in this plugin, so success_color is used when the theme defines it and a
## muted neutral stands in when it doesn't.
func _ok_color(theme_: Theme) -> Color:
	if theme_.has_color(&"success_color", &"Editor"):
		return theme_.get_color(&"success_color", &"Editor")
	return Color(1, 1, 1, 0.55)


func _on_name_changed(new_text: String) -> void:
	if _updating_ui or _selected < 0:
		return
	_mark_dirty()
	_doc.objects[_selected]["Name"] = new_text
	var label := "%d  %s" % [_selected, new_text if new_text != "" else "(unnamed)"]
	_object_list.set_item_text(_selected, label)
	_refresh_status()


func _on_mode_changed(selection: int) -> void:
	if _updating_ui or _selected < 0:
		return
	if selection < 0 or selection >= NetworkObjectsDocument.SCENE_MODES.size():
		return
	_mark_dirty()
	# Paths for the inactive mode are deliberately kept in memory, so flipping
	# back restores them. Only the active mode's keys reach the file.
	_doc.objects[_selected]["SceneMode"] = NetworkObjectsDocument.SCENE_MODES[selection]
	_refresh_selection_area()
	# The tooltip names the mode and lists only the slots that mode reads.
	_refresh_item_tooltip(_selected)
	_refresh_status()


func _open_scene_dialog(key: String) -> void:
	if _selected < 0:
		return
	_picking_key = key
	var current := str(_doc.objects[_selected].get(key, "")).strip_edges()
	if current != "" and FileAccess.file_exists(current):
		_file_dialog.current_path = current
	_file_dialog.popup_centered_ratio(0.6)


func _on_scene_file_selected(path: String) -> void:
	if _picking_key == "" or _selected < 0:
		return
	_set_scene_path(_picking_key, path)
	var edit : LineEdit = _scene_pickers[_picking_key]["edit"]
	edit.text = path
	_picking_key = ""


func _open_scene_in_editor(key: String) -> void:
	if _selected < 0:
		return
	var path := str(_doc.objects[_selected].get(key, "")).strip_edges()
	if path == "" or not FileAccess.file_exists(path):
		return
	EditorInterface.open_scene_from_path(path)


func _on_scene_path_changed(key: String, text: String) -> void:
	if _updating_ui or _selected < 0:
		return
	_set_scene_path(key, text)


func _on_scene_path_cleared(key: String) -> void:
	if _selected < 0:
		return
	var edit : LineEdit = _scene_pickers[key]["edit"]
	if edit.text == "" and str(_doc.objects[_selected].get(key, "")) == "":
		return
	_set_scene_path(key, "")
	edit.text = ""


func _set_scene_path(key: String, path: String) -> void:
	_mark_dirty()
	_doc.objects[_selected][key] = path
	# Refreshes the open button's enabled state, which reads the path.
	_refresh_selection_area()
	# Only this row's tooltip changed. Rebuilding the whole list on every
	# keystroke would also reset the scroll position while typing.
	_refresh_item_tooltip(_selected)
	_refresh_status()


func _on_description_toggle() -> void:
	if _selected < 0:
		return
	# Leaving edit mode commits the box, but only marks the document dirty when
	# the text actually differs, so toggling in and out is not itself an edit.
	if _description_editing:
		var current := str(_doc.objects[_selected].get("_description", ""))
		if _description_edit.text != current:
			_mark_dirty()
			_doc.objects[_selected]["_description"] = _description_edit.text
	_description_editing = not _description_editing
	_refresh_description()
	if _description_editing:
		_description_edit.grab_focus()


## Shows either the rendered BBCode or the raw editable source, and syncs the
## toggle button to match. Never writes to the document.
func _refresh_description() -> void:
	if _selected < 0:
		return
	var raw := str(_doc.objects[_selected].get("_description", ""))
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
	_doc.objects[_selected]["_description"] = _description_edit.text


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
