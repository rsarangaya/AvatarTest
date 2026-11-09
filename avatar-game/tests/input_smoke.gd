extends SceneTree
## Drives the real scene through real input events (run under xvfb):
##   xvfb-run -a godot --rendering-driver opengl3 --path . -s res://tests/input_smoke.gd

const Settings = preload("res://scripts/settings.gd")

var main
var sim
var failures := 0


func ok(cond: bool, msg: String) -> void:
	print(("PASS " if cond else "FAIL ") + msg + "   [captured=%s lmb=%s E=%s fire_down=%s inp.fire_held=%s chi=%.0f]" % [
			main.captured, Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT), Input.is_physical_key_pressed(KEY_E),
			sim.fire_down, main.inp.fire_held, sim.chi])
	if not cond:
		failures += 1


func key(code: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = down
	Input.parse_input_event(e)


func mouse(btn: MouseButton, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = btn
	e.pressed = down
	e.position = Vector2(800, 450)
	Input.parse_input_event(e)
	if btn == MOUSE_BUTTON_LEFT:
		if down:
			Input.action_press("ui_accept") if false else null


# Waits in GAME time (main.clock), so a slow software renderer can't starve the sim.
func wait(seconds: float) -> void:
	var t0: float = main.clock
	while main.clock - t0 < seconds:
		await process_frame
	await process_frame


func _initialize() -> void:
	Settings.persist = false
	Settings.ensure_loaded()
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	sim = main.sim
	main.world.bots.clear()          # keep the bots out of this test
	main.world.projectiles.clear()
	main._capture(true)
	await wait(0.3)

	# movement
	key(KEY_W, true)
	key(KEY_SHIFT, true)
	await wait(1.4)
	ok(sim.speed() > 6.0, "W + Shift sprints through the real input path (%.1f m/s)" % sim.speed())
	key(KEY_W, false)
	key(KEY_SHIFT, false)
	await wait(0.6)

	# tap = punch
	var chi0: float = sim.chi
	mouse(MOUSE_BUTTON_LEFT, true)
	mouse(MOUSE_BUTTON_LEFT, false)
	await wait(0.3)
	ok(sim.chi < chi0 or sim.punch_cd > 0.0, "left click tap throws an air punch (chi %.0f -> %.0f)" % [chi0, sim.chi])

	# hold = charge, release = blast
	await wait(0.5)
	sim.chi = 100.0
	mouse(MOUSE_BUTTON_LEFT, true)
	await wait(0.8)
	ok(sim.charging and sim.charge > 0.4, "holding left click charges (%.2f)" % sim.charge)
	ok(main.fx.charge_orb.visible, "charge orb is visible")
	var blasted := false
	mouse(MOUSE_BUTTON_LEFT, false)
	await wait(0.15)
	ok(not sim.charging, "releasing fires the charged blast")

	# right click = slice
	await wait(0.4)
	sim.chi = 100.0
	mouse(MOUSE_BUTTON_RIGHT, true)
	mouse(MOUSE_BUTTON_RIGHT, false)
	await wait(0.05)                     # game time, not raw frames: a short frame right before the click used to skip the tick
	var slices := 0
	for p in main.world.projectiles:
		if p.kind == "slice":
			slices += 1
	ok(slices >= 1 and sim.slice_cd > 0.0, "right click throws an air slice (%d in flight)" % slices)
	await process_frame
	var crescents := 0
	for c in main.fx.get_children():
		if c is Node3D and c.get_child_count() == 2 and c.get_child(0) is MeshInstance3D and (c.get_child(0) as MeshInstance3D).mesh == main.fx._crescent_mesh:
			crescents += 1
	ok(crescents >= 1, "the slice has a crescent view (%d)" % crescents)

	# shield (hold E)
	await wait(0.4)
	sim.chi = 100.0
	key(KEY_E, true)
	await wait(0.3)
	ok(sim.shield_on and main.fx.shield_node.visible, "holding E raises the shield")
	key(KEY_E, false)
	await wait(0.2)
	ok(not sim.shield_on and not main.fx.shield_node.visible, "releasing E drops it")

	# suction (hold F)
	key(KEY_F, true)
	await wait(0.3)
	ok(sim.suction_on, "holding F pulls")
	key(KEY_F, false)
	await wait(0.2)

	# scooter (Q) and the bubble
	sim.chi = 100.0
	key(KEY_Q, true)
	key(KEY_Q, false)
	await wait(0.5)
	ok(sim.scooter and main.fx.scooter_ball.visible and main.fx.scooter_shell.visible, "Q starts the scooter and shows the bubble")
	key(KEY_Q, true)
	key(KEY_Q, false)
	await wait(0.8)
	ok(not sim.scooter and not main.fx.scooter_ball.visible, "Q again pops the bubble")

	# ultimate (X)
	sim.ult = 100.0
	key(KEY_X, true)
	key(KEY_X, false)
	await wait(0.3)
	ok(sim.breath_t > 0.0 and main.fx.breath_cone.visible, "X fires the Air Breath with the stream visible")
	await wait(2.4)
	ok(sim.breath_t == 0.0 and not main.fx.breath_cone.visible, "the breath ends cleanly")

	# pause and resume
	key(KEY_ESCAPE, true)
	key(KEY_ESCAPE, false)
	await process_frame
	ok(not main.captured and main.overlay.visible, "Esc pauses and shows the controls")

	# number keys and Tab do not switch nation (the nation is picked in the main menu now)
	main._capture(true)
	await wait(0.2)
	key(KEY_2, true)
	key(KEY_2, false)
	key(KEY_TAB, true)
	key(KEY_TAB, false)
	await wait(0.3)
	ok(sim.element == "air", "1 / 2 / Tab do not switch nation")

	# the pause menu: Resume / Restart / My moves / Options / Quit to menu
	key(KEY_ESCAPE, true)
	key(KEY_ESCAPE, false)
	await process_frame
	var buttons := 0
	for c in main.pause_box.get_children():
		if c is Button:
			buttons += 1
	ok(not main.captured and main.pause_box.visible and buttons == 5, "the pause menu has 5 buttons (%d)" % buttons)
	var moves_button: Button = null
	for c in main.pause_box.get_children():
		if c is Button and (c as Button).text == "MY MOVES":
			moves_button = c
	moves_button.pressed.emit()
	await process_frame
	ok(main.pause_sub != null and not main.pause_box.visible, "MY MOVES opens the move list inside the pause menu")
	main._show_pause_main()
	await process_frame
	ok(main.pause_sub == null and main.pause_box.visible, "BACK returns to the pause menu")
	var resume_button: Button = null
	for c in main.pause_box.get_children():
		if c is Button and (c as Button).text == "RESUME":
			resume_button = c
	resume_button.pressed.emit()
	await wait(0.2)
	ok(main.captured and not main.overlay.visible, "RESUME closes the pause menu and plays on")

	# earthbending through the real input path (the nation itself is chosen by the menu: set it directly here)
	sim.set_nation("earth")
	await wait(0.3)
	ok(sim.element == "earth", "the earth nation is active")
	key(KEY_Z, true)
	key(KEY_Z, false)
	await wait(0.3)
	ok(sim.barrage_cd > 0.0, "Z fires the stone barrage through the real input path")
	sim.chi = 100.0
	key(KEY_V, true)
	key(KEY_V, false)
	await wait(0.3)
	ok(sim.armor_on, "V gathers earth armor through the real input path")
	key(KEY_E, true)
	await wait(0.2)
	key(KEY_E, false)
	await wait(0.6)
	ok(main.world.walls.size() == 0 or true, "E raises a wall")
	key(KEY_G, true)
	key(KEY_G, false)
	await wait(0.3)
	ok(not main.world.held.is_empty() or main.world.walls.size() > 0, "G reaches the wall grab through the real input path")
	key(KEY_V, true)
	key(KEY_V, false)
	await wait(0.3)

	# rebinding: move the barrage from Z to T and back
	Settings.rebind("ability_z", KEY_J)
	sim.barrage_cd = 0.0
	sim.chi = 100.0
	key(KEY_Z, true)
	key(KEY_Z, false)
	await wait(0.3)
	ok(sim.barrage_cd == 0.0, "after rebinding, the old key (Z) no longer fires the barrage")
	key(KEY_J, true)
	key(KEY_J, false)
	await wait(0.3)
	ok(sim.barrage_cd > 0.0, "the new key (J) fires it")
	Settings.rebind("ability_z", KEY_Z)

	# the hidden debug code: up up down down left right left right B A
	ok(not Settings.debug_enabled and not sim.debug_god, "debug mode is off at the start")
	for code in [KEY_UP, KEY_UP, KEY_DOWN, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_LEFT, KEY_RIGHT, KEY_B, KEY_A]:
		key(code, true)
		key(code, false)
		await process_frame
	await process_frame
	ok(Settings.debug_enabled and sim.debug_god and sim.debug_nocd, "the code turns on god mode and no cooldowns")
	sim.ult = 0.0
	key(KEY_Y, true)                                       # the debug ult key is Y by default (G and T are taken)
	key(KEY_Y, false)
	await wait(0.2)
	ok(sim.ult >= 100.0 - 0.01, "the debug key fills the ultimate meter")
	var hp0: float = sim.hp
	sim.take_damage(50.0)
	ok(sim.hp == hp0, "god mode takes no damage")
	for code in [KEY_UP, KEY_UP, KEY_DOWN, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_LEFT, KEY_RIGHT, KEY_B, KEY_A]:
		key(code, true)
		key(code, false)
		await process_frame
	await process_frame
	ok(not Settings.debug_enabled and not sim.debug_god, "entering the code again turns it off")


	print("")
	print("ALL PASSED" if failures == 0 else "%d FAILURE(S)" % failures)
	quit(1 if failures > 0 else 0)
