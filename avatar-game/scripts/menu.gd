extends Control
## The main menu: Start Game (Duel or Bots, then nations) / Moves & Tutorial / Options / Exit.
## Picks are stored in Session; confirming the last screen loads the game scene.

const UI = preload("res://scripts/ui.gd")
const Settings = preload("res://scripts/settings.gd")
const Session = preload("res://scripts/session.gd")
const Moveset = preload("res://scripts/moveset.gd")
const TutorialView = preload("res://scripts/tutorial_view.gd")
const OptionsUI = preload("res://scripts/options_ui.gd")
const MenuBg = preload("res://scripts/menu_bg.gd")

const GAME_SCENE := "res://scenes/main.tscn"

var skip_scene_change := false         # tests: confirm without loading the game scene
var started := false                   # the last screen was confirmed
var _holder: CenterContainer
var _screen: Control
var _options: Control = null
var _bg_rect: TextureRect              # the flat gradient: only shown while the 3D backdrop is covered
var bg3d: Node3D = null                # the 3D backdrop (freed when a game starts)


func _ready() -> void:
	theme = UI.make_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Settings.ensure_loaded()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_background()
	bg3d = MenuBg.new()
	add_child(bg3d)
	_holder = CenterContainer.new()
	_holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_holder)
	show_main()
	if _quick_start():
		_start_game()


# Developer shortcut: `godot --path . -- --quick --nation=water --mode=duel --enemy=earth` skips the menus.
# Flags: --nation= --mode=(duel|bots) --enemy=(auto|air|earth|water|fire) --bots=(fighters|benders) --botnation=
static func _flag(args: PackedStringArray, name: String, fallback: String) -> String:
	for a in args:
		if a.begins_with("--%s=" % name):
			return a.substr(name.length() + 3)
	return fallback


func _quick_start() -> bool:
	var args := OS.get_cmdline_user_args()
	if not args.has("--quick") or Session.has_played:
		return false
	Session.player_nation = _flag(args, "nation", Session.player_nation)
	Session.mode = _flag(args, "mode", Session.mode)
	Session.enemy_nation = _flag(args, "enemy", Session.enemy_nation)
	Session.bot_kind = _flag(args, "bots", Session.bot_kind)
	Session.bot_nation = _flag(args, "botnation", Session.bot_nation)
	return true


func _build_background() -> void:
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(0.05, 0.10, 0.20), Color(0.10, 0.28, 0.38), Color(0.20, 0.42, 0.40)])
	grad.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0.5, 0.0)
	tex.fill_to = Vector2(0.5, 1.0)
	var bg := TextureRect.new()
	bg.texture = tex
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.visible = false
	_bg_rect = bg
	add_child(bg)


func _set_screen(c: Control) -> void:
	if _screen != null:
		_screen.queue_free()
	_screen = c
	_options = null
	if bg3d != null:                          # the busy text screens cover it: stop drawing and animating it
		var cov: bool = c is OptionsUI or bool(c.get_meta("covers_bg", false))
		bg3d.set_covered(cov)
		_bg_rect.visible = cov
	_holder.add_child(c)


func _col(sep := 14) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


# ------------------------------------------------------------------ screens

func show_main() -> void:
	var v := _col(16)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var title := UI.label("AVATAR", 84, Color(0.95, 0.97, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var sub := UI.label("air  -  earth  -  water  -  fire", 22, Color(0.7, 0.85, 0.95))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	v.add_child(Control.new())
	if Session.has_played:
		var again := UI.button("PLAY AGAIN  (%s)" % _setup_text(), Vector2(420.0, 56.0))
		again.pressed.connect(_start_game)
		v.add_child(again)
	var start := UI.button("START GAME", Vector2(420.0, 56.0))
	start.pressed.connect(show_mode)
	v.add_child(start)
	var moves := UI.button("MOVES & TUTORIAL", Vector2(420.0, 56.0))
	moves.pressed.connect(show_tutorials)
	v.add_child(moves)
	var opts := UI.button("OPTIONS", Vector2(420.0, 56.0))
	opts.pressed.connect(show_options)
	v.add_child(opts)
	var quit := UI.button("EXIT", Vector2(420.0, 56.0))
	quit.pressed.connect(func(): get_tree().quit())
	v.add_child(quit)
	_set_screen(v)


func _setup_text() -> String:
	var s := "%s, " % Session.nation_name(Session.player_nation).capitalize()
	if Session.mode == "duel":
		s += "duel vs %s" % ("the opposite" if Session.enemy_nation == "auto" else Session.nation_name(Session.enemy_nation).capitalize())
	elif Session.bot_kind == "fighters":
		s += "fighting dummies"
	else:
		s += "%s bots" % Session.nation_name(Session.bot_nation).capitalize()
	return s


func show_mode() -> void:
	var v := _col(16)
	var t := UI.label("CHOOSE A MODE", 40)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	for entry in [["duel", "DUEL", "One enemy bender with its whole kit. You start on opposite sides of the map."],
			["bots", "BOTS", "Training bots to practise on: dummies that fight back, or benders using their nation's moves."]]:
		var b := UI.button(String(entry[1]), Vector2(520.0, 64.0))
		b.pressed.connect(_pick_mode.bind(String(entry[0])))
		v.add_child(b)
		var d := UI.label(String(entry[2]), 15, UI.DIM)
		d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(d)
	var back := UI.button("BACK", Vector2(520.0, 48.0))
	back.pressed.connect(show_main)
	v.add_child(back)
	_set_screen(v)


func _pick_mode(m: String) -> void:
	Session.mode = m
	show_player_nation()


func show_player_nation() -> void:
	_set_screen(_nation_screen("CHOOSE YOUR NATION", "You will play as...", false, _on_player_nation, show_mode, "CONFIRM"))


func _on_player_nation(n: String) -> void:
	Session.player_nation = n
	if Session.mode == "duel":
		show_enemy_nation()
	else:
		show_bot_kind()


func show_enemy_nation() -> void:
	_set_screen(_nation_screen("CHOOSE YOUR ENEMY", "Your duel opponent is...", true, _on_enemy_nation, show_player_nation, "CONFIRM AND PLAY"))


func _on_enemy_nation(n: String) -> void:
	Session.enemy_nation = n
	_start_game()


func show_bot_kind() -> void:
	var v := _col(16)
	var t := UI.label("CHOOSE THE BOTS", 40)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	for entry in [["fighters", "FIGHTING DUMMIES", "They chase you and punch. No bending."],
			["benders", "BENDERS", "Bots that use a nation's moves. You pick the nation next."]]:
		var b := UI.button(String(entry[1]), Vector2(520.0, 64.0))
		b.pressed.connect(_pick_bot_kind.bind(String(entry[0])))
		v.add_child(b)
		var d := UI.label(String(entry[2]), 15, UI.DIM)
		d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(d)
	var back := UI.button("BACK", Vector2(520.0, 48.0))
	back.pressed.connect(show_player_nation)
	v.add_child(back)
	_set_screen(v)


func _pick_bot_kind(kind: String) -> void:
	Session.bot_kind = kind
	if kind == "fighters":
		_start_game()
	else:
		show_bot_nation()


func show_bot_nation() -> void:
	_set_screen(_nation_screen("CHOOSE THE BOTS' NATION", "The bots will be...", false, _on_bot_nation, show_bot_kind, "CONFIRM AND PLAY"))


func _on_bot_nation(n: String) -> void:
	Session.bot_nation = n
	_start_game()


func show_tutorials() -> void:
	var t := _nation_screen("MOVES & TUTORIAL", "Pick a nation to read its moves.", false, Callable(), show_main, "")
	t.set_meta("covers_bg", true)                 # a wall of text: the backdrop stops
	_set_screen(t)


func show_options() -> void:
	var o := OptionsUI.new()
	o.closed.connect(show_main)
	_set_screen(o)
	_options = o


# One reusable screen: nation buttons on the left, the picked nation's moveset on the right, Back and Confirm underneath.
# Selecting a nation reveals its moves; Confirm stays disabled until one is picked. `on_confirm` gets the nation (or "auto").
func _nation_screen(title: String, hint: String, allow_auto: bool, on_confirm: Callable, on_back: Callable,
		confirm_text: String) -> Control:
	var v := _col(12)
	var t := UI.label(title, 38)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var h := UI.label(hint, 16, UI.DIM)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(h)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 20)
	v.add_child(cols)
	var left := _col(10)
	cols.add_child(left)
	var view := TutorialView.new()
	view.custom_minimum_size = Vector2(760.0, 460.0)
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(view)
	var chosen := [""]
	var buttons := {}
	var confirm := UI.button(confirm_text if confirm_text != "" else "CONFIRM", Vector2(300.0, 52.0))
	confirm.disabled = true
	var pick := func(n: String):
		chosen[0] = n
		for k in buttons.keys():
			UI.set_selected(buttons[k], String(k) == n, UI.NATION_COLORS.get(String(k), Color.WHITE))
		if n == "auto":
			view.show_text("[b][color=#ffe08a]OPPOSITE OF ME[/color][/b]\n\nThe enemy takes the nation that counters yours:\n  - if you are Earth Kingdom, the enemy is an Air Nomad,\n  - otherwise the enemy is Earth Kingdom.")
		else:
			view.show_nation(n)
		confirm.disabled = false
	for n in Session.NATIONS:
		var b := UI.button(Session.nation_name(n), Vector2(300.0, 64.0))
		b.add_theme_color_override("font_color", UI.NATION_COLORS[n])
		b.pressed.connect(func(): pick.call(n))
		left.add_child(b)
		buttons[n] = b
	if allow_auto:
		var ab := UI.button("OPPOSITE OF ME", Vector2(300.0, 64.0))
		ab.pressed.connect(func(): pick.call("auto"))
		left.add_child(ab)
		buttons["auto"] = ab
	view.show_text("[color=#aab]Select a nation on the left to see its moves.[/color]")
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 20)
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(bottom)
	var back := UI.button("BACK", Vector2(300.0, 52.0))
	back.pressed.connect(on_back)
	bottom.add_child(back)
	if on_confirm.is_valid():
		confirm.pressed.connect(func(): on_confirm.call(chosen[0]))
		bottom.add_child(confirm)
	return v


# ------------------------------------------------------------------ start

func _start_game() -> void:
	Session.has_played = true
	started = true
	if bg3d != null:
		bg3d.set_covered(true)
		bg3d.queue_free()
		bg3d = null
		_bg_rect.visible = true
	if not skip_scene_change:
		get_tree().change_scene_to_file(GAME_SCENE)


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and Settings.feed_key(int(k.physical_keycode)) and _options != null:
			(_options as OptionsUI).rebuild()                 # the debug key row appears (or goes away)
