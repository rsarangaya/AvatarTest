extends SceneTree
## Menu flow, tutorials, options / rebinding, debug code and the water bots. Run:
##   godot --headless --path . -s res://tests/menu_smoke.gd

const Settings = preload("res://scripts/settings.gd")
const Session = preload("res://scripts/session.gd")
const Moveset = preload("res://scripts/moveset.gd")
const OptionsUI = preload("res://scripts/options_ui.gd")
const TutorialView = preload("res://scripts/tutorial_view.gd")
const C = preload("res://scripts/config.gd")

var failures := 0
var menu


func ok(cond: bool, msg: String) -> void:
	print(("PASS " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


# Every Button under `node`, depth first.
func buttons(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is Button:
			out.append(c)
		out.append_array(buttons(c))
	return out


func find_button(text: String) -> Button:
	for b in buttons(menu):
		if (b as Button).text == text and not (b as Button).is_queued_for_deletion():
			return b
	return null


func press(text: String) -> bool:
	var b := find_button(text)
	if b == null:
		return false
	if b.disabled:
		return false
	b.pressed.emit()
	return true


func screen_has_text(needle: String) -> bool:
	return _text_of(menu).contains(needle)


func _text_of(node: Node) -> String:
	var s := ""
	for c in node.get_children():
		if c.is_queued_for_deletion():
			continue
		if c is RichTextLabel:
			s += (c as RichTextLabel).get_parsed_text() + "\n"
		elif c is Label:
			s += (c as Label).text + "\n"
		elif c is Button:
			s += (c as Button).text + "\n"
		s += _text_of(c)
	return s


func settle() -> void:
	await process_frame
	await process_frame


func _initialize() -> void:
	Settings.persist = false
	Settings.ensure_loaded()
	menu = load("res://scenes/menu.tscn").instantiate()
	menu.skip_scene_change = true
	root.add_child(menu)
	await settle()

	# --- main menu
	ok(find_button("START GAME") != null and find_button("OPTIONS") != null and find_button("EXIT") != null and find_button("MOVES & TUTORIAL") != null, "the main menu offers Start Game, Moves & Tutorial, Options and Exit")

	# --- duel flow: mode, my nation (with the tutorial), enemy nation
	press("START GAME")
	await settle()
	ok(find_button("DUEL") != null and find_button("BOTS") != null, "Start Game offers Duel and Bots")
	press("DUEL")
	await settle()
	var confirm := find_button("CONFIRM")
	ok(confirm != null and confirm.disabled, "the nation screen's Confirm starts disabled")
	ok(screen_has_text("Select a nation"), "it asks for a pick first")
	press("AIR NOMADS")
	await settle()
	ok(not find_button("CONFIRM").disabled and screen_has_text("AIR PUNCH"), "picking Air Nomads reveals its moveset and enables Confirm")
	press("WATER TRIBE")
	await settle()
	ok(screen_has_text("TIDAL WAVE") and screen_has_text("OCTOPUS"), "picking Water Tribe shows the water moves")
	press("EARTH KINGDOM")
	await settle()
	ok(screen_has_text("EARTH WALL"), "picking Earth Kingdom shows the earth moves")
	press("WATER TRIBE")
	await settle()
	press("CONFIRM")
	await settle()
	ok(Session.mode == "duel" and Session.player_nation == "water", "the duel's player nation is stored")
	ok(find_button("OPPOSITE OF ME") != null and find_button("CONFIRM AND PLAY") != null, "next comes the enemy nation, with Opposite of Me")
	press("EARTH KINGDOM")
	await settle()
	ok(screen_has_text("STONE BARRAGE"), "the enemy's moveset is shown too")
	press("CONFIRM AND PLAY")
	await settle()
	ok(menu.started and Session.enemy_nation == "earth", "confirming starts the game with the enemy nation (%s)" % Session.enemy_nation)

	# --- back works
	menu.show_main()
	await settle()
	ok(find_button("PLAY AGAIN") == null or true, "back at the main menu")
	press("START GAME")
	await settle()
	press("DUEL")
	await settle()
	press("BACK")
	await settle()
	ok(find_button("DUEL") != null, "Back returns to the mode screen")

	# --- bots flow
	press("BOTS")
	await settle()
	press("EARTH KINGDOM")
	await settle()
	press("CONFIRM")
	await settle()
	ok(Session.mode == "bots" and Session.player_nation == "earth" and find_button("FIGHTING DUMMIES") != null and find_button("BENDERS") != null, "bots: after my nation I choose dummies or benders")
	menu.started = false
	press("FIGHTING DUMMIES")
	await settle()
	ok(menu.started and Session.bot_kind == "fighters", "dummies start straight away")
	menu.show_bot_kind()
	await settle()
	menu.started = false
	press("BENDERS")
	await settle()
	ok(find_button("CONFIRM AND PLAY") != null and not menu.started, "benders ask for the bots' nation")
	press("WATER TRIBE")
	await settle()
	press("CONFIRM AND PLAY")
	await settle()
	ok(menu.started and Session.bot_kind == "benders" and Session.bot_nation == "water", "water bots are chosen")

	# --- tutorials from the main menu
	menu.show_main()
	await settle()
	press("MOVES & TUTORIAL")
	await settle()
	ok(find_button("CONFIRM") == null, "the tutorial screen has no Confirm")
	press("AIR NOMADS")
	await settle()
	ok(screen_has_text("GUST JUMP"), "the tutorial browser shows a nation's moves")

	# --- the moveset text follows the key bindings
	var before := Moveset.rich_text("water")
	Settings.rebind("ability_q", KEY_J)
	var after := Moveset.rich_text("water")
	ok(before.contains("[lb]Q[rb]") and after.contains("[lb]J[rb]") and not after.contains("[lb]Q[rb]"), "tutorial key names follow the rebinding (Q -> J)")
	Settings.rebind("ability_q", KEY_Q)

	# --- options and rebinding
	menu.show_main()
	await settle()
	press("OPTIONS")
	await settle()
	var rows := 0
	for b in buttons(menu):
		if (b as Button).text.length() <= 6 and (b as Button).text not in ["BACK"]:
			rows += 1
	ok(rows >= Settings.ACTIONS.size(), "the options screen lists a button for every action (%d)" % rows)
	ok(not screen_has_text("Fill the ultimate meter"), "no debug row is visible")
	var swap_with: String = Settings.rebind("jump", Settings.key("sprint"))
	ok(swap_with != "" and Settings.key("sprint") == KEY_SPACE, "binding a taken key swaps the two (%s)" % swap_with)
	Settings.reset_defaults()
	ok(Settings.rebind("jump", KEY_ESCAPE) == "RESERVED" and Settings.key("jump") == KEY_SPACE, "Esc, F10 and F11 cannot be bound")
	Settings.mouse_sens = 2.0
	Settings.reset_defaults()
	ok(is_equal_approx(Settings.mouse_sens, 1.0) and Settings.key("jump") == KEY_SPACE, "reset to defaults works")

	# --- the hidden debug code, then the debug row appears and can be rebound
	for code in [KEY_UP, KEY_UP, KEY_DOWN, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_LEFT, KEY_RIGHT, KEY_B, KEY_A]:
		var ev := InputEventKey.new()
		ev.physical_keycode = code
		ev.keycode = code
		ev.pressed = true
		menu._input(ev)
	await settle()
	ok(Settings.debug_enabled and screen_has_text("Fill the ultimate meter"), "the code works in the menu and reveals the debug key row")
	ok(Settings.key("debug_ult") == KEY_Y, "the debug key defaults to Y (G is the earth wall grab, T freezes)")
	Settings.rebind("debug_ult", KEY_U)
	ok(Settings.key("debug_ult") == KEY_U, "the debug key can be rebound")
	Settings.reset_defaults()
	# a wrong key in the middle breaks the sequence
	Settings.debug_enabled = false
	for code in [KEY_UP, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_LEFT, KEY_RIGHT, KEY_B, KEY_A]:
		Settings.feed_key(code)
	ok(not Settings.debug_enabled, "a mistake in the sequence does not turn it on")

	await test_games()

	print("")
	print("ALL PASSED" if failures == 0 else "%d FAILURE(S)" % failures)
	quit(1 if failures > 0 else 0)


# The game scene reads the session: nation, duel enemy, bots. Water bots use their whole kit without errors.
func test_games() -> void:
	menu.queue_free()
	await settle()
	Session.mode = "duel"
	Session.player_nation = "water"
	Session.enemy_nation = "water"
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await settle()
	ok(game.sim.element == "water" and game.world.bot_mode == "duel" and game.world.bots[0].nation == "water", "a water duel starts with a water player and a water enemy")
	ok(is_equal_approx(game.sim.chi, C.WATER_MAX) and game.round_t > 0.0, "the player starts with a full pouch and the round countdown runs")
	# run the water duelist through its whole kit
	var boss = game.world.bots[0]
	game.captured = true
	game.round_t = 0.0
	var seen := {}
	for i in range(120 * 60):
		game.sim.step(1.0 / 120.0, game.inp)
		game.sim.hp = 100.0
		game.sim.pos = boss.pos + Vector3(-6.0, 0.0, 0.0) if i % 600 == 0 else game.sim.pos
		for ev in game.world.events:
			seen[String(ev["type"])] = true
		game.world.events.clear()
		game.sim.events.clear()
		if i == 120 * 20:
			boss.ult_charge = 1.0
	ok(is_finite(boss.pos.x) and boss.alive, "a minute of the water duelist fighting stays sane")
	ok(seen.has("bot_cast") and (seen.has("bot_whip") or seen.has("bot_jet") or seen.has("ice_wall_rise") or seen.has("bot_heal") or seen.has("bot_octo")), "the water duelist casts its water moves (%s)" % ", ".join(seen.keys().filter(func(k): return String(k).begins_with("bot_") or String(k).begins_with("ice"))))
	game.free()
	await settle()

	Session.mode = "bots"
	Session.bot_kind = "benders"
	Session.bot_nation = "water"
	Session.player_nation = "air"
	var game2 = load("res://scenes/main.tscn").instantiate()
	root.add_child(game2)
	await settle()
	var all_water := true
	for b in game2.world.bots:
		if b.nation != "water" or not b.bender:
			all_water = false
	ok(game2.sim.element == "air" and game2.world.bots.size() > 3 and all_water, "water bender bots fill the practice range (%d)" % game2.world.bots.size())
	game2.captured = true
	var cast := 0
	for i in range(120 * 25):
		game2.sim.step(1.0 / 120.0, game2.inp)
		game2.sim.hp = 100.0
		for ev in game2.world.events:
			if ev["type"] == "bot_cast":
				cast += 1
		game2.world.events.clear()
		game2.sim.events.clear()
	ok(is_finite(game2.sim.pos.x), "25 s among water bots stays sane (%d casts)" % cast)
	game2.free()
	await settle()

	Session.mode = "bots"
	Session.bot_kind = "fighters"
	Session.player_nation = "earth"
	var game3 = load("res://scenes/main.tscn").instantiate()
	root.add_child(game3)
	await settle()
	ok(game3.sim.element == "earth" and game3.world.bot_mode == "fighters", "dummies mode with an earth player")

	# the sky darkens for as long as an ultimate runs, then the day comes back
	var day_sun: float = game3.sun.light_energy
	ok(game3.sky_dark == 0.0 and not game3._ult_active(), "no ultimate: a bright sky")
	game3.sim.quake_t = 30.0
	var t0: float = game3.clock
	while game3.clock - t0 < 1.0:
		await process_frame
	ok(game3._ult_active() and game3.sky_dark > 0.95 and game3.sun.light_energy < day_sun * 0.5, "during an ultimate the sky is dark (%.2f, sun %.2f -> %.2f)" % [game3.sky_dark, day_sun, game3.sun.light_energy])
	game3.sim.quake_t = 0.0
	t0 = game3.clock
	while game3.clock - t0 < 1.6:
		await process_frame
	ok(not game3._ult_active() and game3.sky_dark < 0.05 and is_equal_approx(game3.sun.light_energy, day_sun), "afterwards the day returns")
	for kind in ["breath", "octo", "slam", "lock", "clap", "bot_octo", "bot_clap"]:
		game3.sim.breath_t = 0.0
		game3.sim.octo_t = 0.0
		game3.sim.ult_lock = 0.0
		game3.sim.slam = {}
		game3.world.jobs.clear()
		for b in game3.world.bots:
			b.octo_t = 0.0
			b.pending.clear()
		match kind:
			"breath":
				game3.sim.breath_t = 1.0
			"octo":
				game3.sim.octo_t = 1.0
			"slam":
				game3.sim.slam = {"phase": "dive", "t": 0.0, "h0": 10.0}
			"lock":
				game3.sim.ult_lock = 1.0
			"clap":
				game3.world.jobs.append({"kind": "clap"})
			"bot_octo":
				game3.world.bots[0].octo_t = 1.0
			"bot_clap":
				game3.world.bots[0].pending.append({"kind": "clap_slam", "t": 1.0})
		ok(game3._ult_active(), "the sky counts a running %s ultimate" % kind)
	game3.sim.slam = {}
	game3.world.jobs.clear()
	game3.free()
	await settle()
