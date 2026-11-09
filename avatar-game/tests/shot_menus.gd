extends SceneTree
## Saves screenshots of the menu screens and the pause menu. Needs a display:
##   set SHOT_OUT to an existing folder, then
##   godot --path . --resolution 1280x720 -s res://tests/shot_menus.gd

const Session = preload("res://scripts/session.gd")
const Settings = preload("res://scripts/settings.gd")

var out := ""
var menu


func _initialize() -> void:
	Settings.persist = false
	Settings.ensure_loaded()
	out = OS.get_environment("SHOT_OUT")
	if out == "":
		out = OS.get_user_data_dir()
	out += "/"
	DirAccess.make_dir_recursive_absolute(out)
	menu = load("res://scenes/menu.tscn").instantiate()
	menu.skip_scene_change = true
	root.add_child(menu)
	await frames(3)
	await save("m_main")
	menu.show_mode()
	await frames(3)
	await save("m_mode")
	Session.mode = "duel"
	menu.show_player_nation()
	await frames(2)
	await save("m_nation_empty")
	press("WATER TRIBE")
	await frames(3)
	await save("m_nation_water")
	menu.show_enemy_nation()
	await frames(2)
	press("EARTH KINGDOM")
	await frames(3)
	await save("m_enemy_earth")
	menu.show_options()
	await frames(3)
	await save("m_options")
	for code in [KEY_UP, KEY_UP, KEY_DOWN, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_LEFT, KEY_RIGHT, KEY_B, KEY_A]:
		var ev := InputEventKey.new()
		ev.physical_keycode = code
		ev.keycode = code
		ev.pressed = true
		menu._input(ev)
	await frames(3)
	await save("m_options_debug")
	Settings.debug_enabled = false
	menu.queue_free()
	await frames(2)

	# the game: a water duel against water, then the pause menu and its screens
	Session.mode = "duel"
	Session.player_nation = "water"
	Session.enemy_nation = "water"
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await frames(5)
	game.round_t = 0.0
	game._capture(true)                          # the screenshot window has no focus, which would pause the game
	game.overlay.visible = false
	var boss = game.world.bots[0]
	game.sim.pos = boss.pos + Vector3(-9.0, 0.0, 0.0)
	game.sim.pos.y = game.world.height_at(game.sim.pos.x, game.sim.pos.z) + 0.05
	game.sim.yaw = atan2(-(boss.pos.x - game.sim.pos.x), -(boss.pos.z - game.sim.pos.z))
	game.sim.pitch = 0.0
	game.prev_pos = game.sim.pos
	for k in range(90):
		game.sim.step(1.0 / 120.0, game.inp)
		game.sim.hp = 100.0
		if k % 3 == 0:
			game.prev_pos = game.sim.pos
			await process_frame
	await save("g_duel_start")
	for k in range(260):
		game.sim.step(1.0 / 120.0, game.inp)
		game.sim.hp = 100.0
		if k % 3 == 0:
			game.prev_pos = game.sim.pos
			await process_frame
	await save("g_duel_fight")
	game._capture(false)
	game._capture(false)
	await frames(3)
	await save("g_pause")
	game._show_moves()
	await frames(3)
	await save("g_pause_moves")
	game._show_pause_main()
	game._show_options()
	await frames(3)
	await save("g_pause_options")
	quit(0)


func press(text: String) -> void:
	for b in _buttons(menu):
		if (b as Button).text == text:
			(b as Button).pressed.emit()
			return


func _buttons(node: Node) -> Array:
	var o: Array = []
	for c in node.get_children():
		if c is Button:
			o.append(c)
		o.append_array(_buttons(c))
	return o


func frames(n: int) -> void:
	for i in range(n):
		await process_frame


func save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var err := img.save_png(out + name + ".png")
	print("saved ", name, " err=", err)
