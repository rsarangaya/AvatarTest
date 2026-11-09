extends PanelContainer
## The options screen: mouse sensitivity, field of view and key rebinding.
## Click a key to change it, then press the new key (Esc cancels). If another action already uses that key they swap.

signal closed

const Settings = preload("res://scripts/settings.gd")
const UI = preload("res://scripts/ui.gd")

var _list: VBoxContainer
var _status: Label
var _buttons := {}                  # action id -> Button
var _waiting := ""                  # the action being rebound ("" = none)


func _init() -> void:
	custom_minimum_size = Vector2(760.0, 560.0)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	add_child(root)
	root.add_child(UI.label("OPTIONS", 30))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)
	_status = UI.label("", 14, UI.DIM)
	root.add_child(_status)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	root.add_child(row)
	var reset := UI.button("RESET TO DEFAULTS", Vector2(240.0, 46.0))
	reset.pressed.connect(_on_reset)
	row.add_child(reset)
	var back := UI.button("BACK", Vector2(240.0, 46.0))
	back.pressed.connect(func(): _cancel(); closed.emit())
	row.add_child(back)
	rebuild()


func rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
	_buttons.clear()
	_waiting = ""
	_slider("Mouse sensitivity", 0.2, 3.0, Settings.mouse_sens, func(v): Settings.mouse_sens = v; Settings.save())
	_slider("Field of view", 70.0, 110.0, Settings.fov, func(v): Settings.fov = v; Settings.save())
	var group := ""
	var actions: Array = Settings.ACTIONS + (Settings.DEBUG_ACTIONS if Settings.debug_enabled else [])
	for a in actions:
		if String(a["group"]) != group:
			group = String(a["group"])
			var head := UI.label(group.to_upper() + (" KEYS" if group != "Debug" else ""), 18, Color(0.62, 0.83, 1.0))
			_list.add_child(head)
		_add_row(String(a["id"]))
	_list.add_child(UI.label("Fixed: left / right click and the mouse wheel, Esc (pause), F10 (quit), F11 (fullscreen).", 13, UI.DIM))


func _slider(name: String, lo: float, hi: float, value: float, on_change: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l := UI.label(name, 16)
	l.custom_minimum_size = Vector2(260.0, 0.0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 0.01 if hi < 10.0 else 1.0
	s.value = value
	s.custom_minimum_size = Vector2(300.0, 24.0)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(s)
	var v := UI.label("%.2f" % value if hi < 10.0 else "%d" % int(value), 16, UI.DIM)
	row.add_child(v)
	s.value_changed.connect(func(x):
		v.text = "%.2f" % x if hi < 10.0 else "%d" % int(x)
		on_change.call(x))
	_list.add_child(row)


func _add_row(id: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l := UI.label(Settings.label(id), 16)
	l.custom_minimum_size = Vector2(420.0, 0.0)
	row.add_child(l)
	var b := UI.button(Settings.key_name(id), Vector2(160.0, 38.0))
	b.pressed.connect(_begin_rebind.bind(id))
	row.add_child(b)
	_buttons[id] = b
	_list.add_child(row)


func _begin_rebind(id: String) -> void:
	_cancel()
	_waiting = id
	(_buttons[id] as Button).text = "press a key..."
	_status.text = "Press the new key for \"%s\" (Esc cancels)." % Settings.label(id)


func _cancel() -> void:
	if _waiting != "" and _buttons.has(_waiting):
		(_buttons[_waiting] as Button).text = Settings.key_name(_waiting)
	_waiting = ""


func _on_reset() -> void:
	Settings.reset_defaults()
	rebuild()
	_status.text = "Everything is back to the defaults."


func _input(event: InputEvent) -> void:
	if _waiting == "" or not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if not k.pressed or k.echo:
		return
	get_viewport().set_input_as_handled()
	if k.physical_keycode == KEY_ESCAPE:
		_cancel()
		_status.text = "Cancelled."
		return
	var id := _waiting
	var swapped: String = Settings.rebind(id, int(k.physical_keycode))
	_waiting = ""
	if swapped == "RESERVED":
		_status.text = "That key is used by the game (Esc, F10, F11). Pick another."
		(_buttons[id] as Button).text = Settings.key_name(id)
		return
	for other in _buttons.keys():
		(_buttons[other] as Button).text = Settings.key_name(String(other))
	_status.text = "\"%s\" is now %s." % [Settings.label(id), Settings.key_name(id)] \
			+ ("   (swapped with \"%s\")" % swapped if swapped != "" else "")
