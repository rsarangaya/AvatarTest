extends SceneTree
## The HUD's ability indicators for air, earth and water: the rows exist, only the active one shows, and a slot
## follows cooldown / ready / unusable without errors. Run:
##   godot --headless --path . -s res://tests/hud_slot_test.gd

const Settings = preload("res://scripts/settings.gd")
const Session = preload("res://scripts/session.gd")
const HudSlot = preload("res://scripts/hud_slot.gd")
const C = preload("res://scripts/config.gd")

var failures := 0


func ok(cond: bool, msg: String) -> void:
	print(("PASS " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func settle() -> void:
	await process_frame
	await process_frame


func _initialize() -> void:
	Settings.persist = false
	Settings.ensure_loaded()
	for el in ["air", "earth", "water"]:
		await check_element(el)
	print("")
	print("ALL PASSED" if failures == 0 else "%d FAILURE(S)" % failures)
	quit(1 if failures > 0 else 0)


func check_element(el: String) -> void:
	Session.mode = "bots"
	Session.bot_kind = "fighters"
	Session.player_nation = el
	Session.enemy_nation = el
	Session.bot_nation = el
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await settle()
	var sim = game.sim

	ok(game.sim.element == el and game.slot_nodes.has(el), "%s: the HUD builds a slot row for the element" % el)
	var slots: Array = game.slot_nodes[el]
	var all_slots := slots.size() >= 5
	for s in slots:
		all_slots = all_slots and s is HudSlot and is_instance_valid(s)
	ok(all_slots, "%s: every slot is a HudSlot (%d slots)" % [el, slots.size()])
	var only_active := true
	for k in game.slot_rows:
		only_active = only_active and game.slot_rows[k].visible == (k == el)
	ok(only_active, "%s: only the active element's row is visible" % el)

	var basic: HudSlot = slots[0]
	var ult: HudSlot = slots[slots.size() - 1]

	# cooldown: the basic attack's sweep is down while it runs, and it is usable with chi
	sim.chi = C.CHI_MAX
	sim.punch_cd = 0.1
	game._update_slots(0.0)
	ok(basic._sweep_px > 0 and basic._usable, "%s: a basic attack on cooldown shows a sweep" % el)

	# ready: the sweep clears again
	sim.punch_cd = 0.0
	game._update_slots(0.0)
	ok(basic._sweep_px == 0, "%s: the basic attack clears its sweep when ready" % el)

	# unusable: no chi dims the slot
	sim.chi = 0.0
	game._update_slots(0.0)
	ok(not basic._usable, "%s: with no chi the basic attack is marked unusable" % el)

	# the ultimate flashes when it fills up (the sweep is what is still missing)
	sim.chi = C.CHI_MAX
	sim.ult = 0.0
	game._update_slots(0.0)
	sim.ult = C.ULT_MAX
	game._update_slots(0.0)
	ok(ult._flash > 0.0 and ult._sweep_px == 0, "%s: a full ultimate meter flashes its slot" % el)

	game.free()
	await settle()
