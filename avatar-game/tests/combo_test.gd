extends SceneTree
## Headless tests for the combos, kill momentum, burn and the two lightning extras (wet chain, bolt duel). Run:
##   godot --headless --path . -s res://tests/combo_test.gd

const WorldScript = preload("res://scripts/world.gd")
const SimScript = preload("res://scripts/player_sim.gd")
const BenderAI = preload("res://scripts/bender_ai.gd")
const Moveset = preload("res://scripts/moveset.gd")
const Settings = preload("res://scripts/settings.gd")
const C = preload("res://scripts/config.gd")

const TICK := 1.0 / 120.0
var failures := 0


func ok(cond: bool, msg: String) -> void:
	print(("PASS " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func ip() -> SimScript.InputState:
	return SimScript.InputState.new()


func idle(p, secs: float) -> void:
	for i in range(int(secs / TICK)):
		p.step(TICK, ip())


func press(p, field: String) -> void:
	var a = ip()
	a.set(field, true)
	p.step(TICK, a)


func has_event(p, type: String) -> bool:
	for e in p.events:
		if e["type"] == type:
			return true
	return false


func has_wevent(w, type: String) -> bool:
	for e in w.events:
		if e["type"] == type:
			return true
	return false


func fresh(nation: String) -> Array:
	var w := WorldScript.new(1337)
	w.burn_chance = 0.0
	w.bots.clear()
	var p := SimScript.new(w)
	p.set_nation(nation)
	p.respawn()
	p.yaw = 0.0
	idle(p, 0.6)
	p.events.clear()
	w.events.clear()
	return [w, p]


func dummy(w, pos: Vector3, hp := 450.0):
	var b := WorldScript.Bot.new(pos)
	b.pos.y = w.height_at(pos.x, pos.z)
	b.home = b.pos
	b.wander_to = b.pos
	b.wander_t = 1e9
	b.fighter = false
	b.max_hp = hp
	b.hp = hp
	w.bots.append(b)
	return b


func proj_damage(w, kind: String) -> float:
	for q in w.projectiles:
		if q.kind == kind:
			return q.damage
	return -1.0


# A spot of open water (at least 0.4 m deep) with room for neighbours, or Vector3.INF.
func find_water() -> Vector3:
	var w := WorldScript.new(1337)
	var x := -150.0
	while x <= 150.0:
		var z := -150.0
		while z <= 150.0:
			var good := true
			for o in [Vector2(0, 0), Vector2(4, 0), Vector2(8, 0), Vector2(4, 4)]:
				if w.terrain.water_depth_at(x + o.x, z + o.y) < 0.4:
					good = false
					break
			if good:
				return Vector3(x, 0.0, z)
			z += 4.0
		x += 4.0
	return Vector3.INF


func test_combos() -> void:
	print("-- combos")
	# fire: kick then flame burst
	var f := fresh("fire")
	var w = f[0]
	var p = f[1]
	press(p, "barrage_pressed")
	ok(p.combo_t > 0.0 and has_event(p, "combo_ready"), "fire: the kick opens the combo window")
	idle(p, 0.3)
	p.events.clear()
	press(p, "slice_pressed")
	ok(has_event(p, "combo") and absf(proj_damage(w, "fpellet") - C.FBURST_DAMAGE * C.COMBOS["fire"]["mult"]) < 0.01, "fire: the burst right after the kick does x%.1f pellet damage" % C.COMBOS["fire"]["mult"])
	f = fresh("fire")
	w = f[0]
	p = f[1]
	press(p, "slice_pressed")
	ok(not has_event(p, "combo") and absf(proj_damage(w, "fpellet") - C.FBURST_DAMAGE) < 0.01, "fire: a burst with no kick is plain")
	f = fresh("fire")
	w = f[0]
	p = f[1]
	press(p, "barrage_pressed")
	idle(p, C.COMBO_WINDOW + 0.2)
	press(p, "slice_pressed")
	ok(not has_event(p, "combo") and p.combo_t <= 0.0, "fire: the window closes after %.1f s" % C.COMBO_WINDOW)

	# air: dash then slice
	f = fresh("air")
	w = f[0]
	p = f[1]
	p.chi = p.chi_cap()
	press(p, "barrage_pressed")
	ok(p.combo_t > 0.0, "air: the air dash opens the combo")
	idle(p, 0.25)
	p.chi = p.chi_cap()
	press(p, "slice_pressed")
	ok(has_event(p, "combo") and absf(proj_damage(w, "slice") - C.SLICE_DAMAGE * C.COMBOS["air"]["mult"]) < 0.01, "air: dash then slice does x%.1f" % C.COMBOS["air"]["mult"])
	ok(p.combo_t <= 0.0, "air: the combo is used up (no second bonus)")

	# earth: barrage then boulder
	f = fresh("earth")
	w = f[0]
	p = f[1]
	p.chi = p.chi_cap()
	press(p, "barrage_pressed")
	ok(p.combo_t > 0.0, "earth: the barrage opens the combo")
	idle(p, 0.3)
	p.chi = p.chi_cap()
	press(p, "slice_pressed")
	ok(has_event(p, "combo") and p.boulder_mult > 1.0, "earth: starting the boulder takes the bonus")
	idle(p, C.BOULDER_PULL_TIME + 0.3)
	var bd := proj_damage(w, "boulder")
	ok(absf(bd - C.BOULDER_DAMAGE * C.COMBOS["earth"]["mult"]) < 0.01, "earth: the boulder does x%.1f (%.0f)" % [C.COMBOS["earth"]["mult"], bd])

	# water: shards then whip (tap)
	f = fresh("water")
	w = f[0]
	p = f[1]
	p.chi = p.chi_cap()
	press(p, "barrage_pressed")
	ok(p.combo_t > 0.0, "water: the ice shards open the combo")
	idle(p, 0.2)
	w.projectiles.clear()
	var b = dummy(w, p.pos + Vector3(0.0, 0.0, -3.0))
	p.chi = p.chi_cap()
	var a = ip()
	a.fire_pressed = true
	a.fire_held = true
	p.step(TICK, a)
	p.step(TICK, ip())
	var lost: float = b.max_hp - b.hp
	ok(has_event(p, "combo") and absf(lost - C.WHIP_DAMAGE * C.COMBOS["water"]["mult"]) < 0.5, "water: the whip after the shards does x%.1f (%.1f)" % [C.COMBOS["water"]["mult"], lost])

	# balance: every combo is a moderate burst, and the nations have exactly one
	ok(C.COMBOS.size() == 4, "one combo per nation")
	for n in C.COMBOS:
		ok(float(C.COMBOS[n]["mult"]) <= 2.0 and float(C.COMBOS[n]["mult"]) > 1.0, "%s combo multiplier %.1f is a moderate burst" % [n, C.COMBOS[n]["mult"]])
	var t := Moveset.rich_text("fire")
	ok(t.contains("KICK + BURST") and Moveset.rich_text("air").contains("DASH SLICE") and Moveset.rich_text("earth").contains("QUAKE BOULDER") and Moveset.rich_text("water").contains("FROST LASH"), "the kit cards list every combo")


func test_momentum() -> void:
	print("-- kill momentum")
	var speeds := {}
	for mode in ["duel", "fighters", "benders"]:
		var f := fresh("air")
		var w = f[0]
		var p = f[1]
		w.bot_mode = mode
		var b = dummy(w, p.pos + Vector3(0.0, 0.0, -40.0), 10.0)
		w.damage_bot(b, 999.0, Vector3.ZERO)
		p.step(TICK, ip())
		var got: bool = p.momentum_t > 2.5
		ok(got == (mode != "duel"), "%s: a kill %s momentum" % [mode, "gives" if got else "does not give"])
		var a := ip()
		a.move_y = 1.0
		for i in range(240):
			p.step(TICK, a)
		speeds[mode] = p.speed()
	ok(speeds["fighters"] > speeds["duel"] * 1.1, "momentum is faster (%.1f vs %.1f m/s)" % [speeds["fighters"], speeds["duel"]])
	var f2 := fresh("fire")
	f2[0].bot_mode = "fighters"
	var bb = dummy(f2[0], f2[1].pos + Vector3(0.0, 0.0, -40.0), 10.0)
	f2[0].damage_bot(bb, 999.0, Vector3.ZERO)
	f2[1].step(TICK, ip())
	idle(f2[1], C.MODE_KILL_EFFECTS["fighters"]["time"] + 0.2)
	ok(f2[1].momentum_t <= 0.0, "it runs out after %.0f s" % C.MODE_KILL_EFFECTS["fighters"]["time"])
	ok(C.MODE_KILL_EFFECTS["duel"].is_empty(), "the mode table gives duel nothing")


func test_burn() -> void:
	print("-- burn")
	var f := fresh("fire")
	var w = f[0]
	var p = f[1]
	w.burn_chance = 1.0
	var b = dummy(w, p.pos + Vector3(0.0, 0.0, -6.0))
	var a = ip()
	a.fire_pressed = true
	a.fire_held = true
	p.step(TICK, a)
	p.step(TICK, ip())
	idle(p, 0.6)
	ok(b.burn_t > 0.0 and has_wevent(w, "burn_on"), "a fire hit can set a bot on fire (chance forced to 1)")
	var hp0: float = b.hp
	idle(p, 1.0)
	ok(hp0 - b.hp > C.BURN_DPS * 0.7, "it burns for damage over time (%.1f in 1 s)" % (hp0 - b.hp))
	idle(p, C.BURN_TIME)
	ok(b.burn_t <= 0.0, "and goes out after %.0f s" % C.BURN_TIME)

	f = fresh("fire")
	w = f[0]
	p = f[1]
	w.burn_chance = 0.0
	b = dummy(w, p.pos + Vector3(0.0, 0.0, -6.0))
	a = ip()
	a.fire_pressed = true
	a.fire_held = true
	p.step(TICK, a)
	p.step(TICK, ip())
	idle(p, 0.6)
	ok(b.burn_t <= 0.0, "with chance 0 a hit never burns (it is not guaranteed)")
	ok(C.BURN_CHANCE > 0.0 and C.BURN_CHANCE <= 0.2, "the default chance is %.0f%%" % (C.BURN_CHANCE * 100.0))

	# water puts a burning bot out
	var spot := find_water()
	ok(spot != Vector3.INF, "found open water for the water checks")
	if spot != Vector3.INF:
		f = fresh("fire")
		w = f[0]
		p = f[1]
		var wb = dummy(w, spot)
		wb.pos.y = w.terrain.surface_at(spot.x, spot.z) - 0.3
		wb.burn_t = 3.0
		w.update_combat(TICK, null)
		ok(wb.burn_t <= 0.0 and has_wevent(w, "burn_out"), "water puts a burning bot out")

	# the player: an enemy fireball can ignite, damage ticks, water puts it out
	f = fresh("air")
	w = f[0]
	p = f[1]
	w.burn_chance = 1.0
	var hp1: float = p.hp
	w.spawn_proj("fpunch", "enemy", p.pos + Vector3(0.0, 1.0, -0.5), Vector3(0.0, 0.0, 10.0), 0.5, 0.4, 5.0, 0.0)
	w.update_combat(TICK, p)
	ok(p.burn_t > 0.0, "an enemy fireball can set the player on fire")
	hp1 = p.hp
	p.hp_delay = 100.0
	idle(p, 2.0)
	ok(hp1 - p.hp > C.BURN_DPS * 1.5 and has_event(p, "hurt"), "the player takes burn damage (%.1f in 2 s)" % (hp1 - p.hp))
	if spot != Vector3.INF:
		p.pos = Vector3(spot.x, w.terrain.surface_at(spot.x, spot.z), spot.z)
		p.events.clear()
		idle(p, 0.2)
		ok(p.burn_t <= 0.0 and has_event(p, "burn_out"), "water puts the player out")


func test_chain() -> void:
	print("-- lightning chain")
	var spot := find_water()
	if spot == Vector3.INF:
		ok(false, "no water for the chain test")
		return
	var f := fresh("fire")
	var w = f[0]
	var p = f[1]
	var surf: float = w.terrain.surface_at(spot.x, spot.z)
	var a = dummy(w, Vector3(spot.x, surf, spot.z))
	var b = dummy(w, Vector3(spot.x + 8.0, surf, spot.z))
	var c = dummy(w, Vector3(spot.x + 4.0, surf, spot.z + 4.0))
	var dry = dummy(w, Vector3(spot.x + 40.0, 0.0, spot.z))
	var eye := Vector3(spot.x, surf + 2.4, spot.z + 7.0)
	var aim: Vector3 = (w.bot_center(a) - eye).normalized()
	var res: Dictionary = w.lightning(eye, aim, C.LIGHT_RANGE, C.LIGHT_DAMAGE, true)
	ok(a.hp < a.max_hp, "the bolt hits the first enemy in the water")
	ok(b.hp < b.max_hp and c.hp < c.max_hp, "a full-charge wet bolt chains to the other enemies standing in water")
	ok(dry.hp == dry.max_hp, "an enemy on dry land is not chained")
	ok(a.max_hp - a.hp > b.max_hp - b.hp or b.max_hp - b.hp < C.LIGHT_DAMAGE, "chain hits are weaker (falloff %.1f)" % C.LIGHT_CHAIN_FALLOFF)
	# not full charge: no chain
	for x in [a, b, c]:
		x.hp = x.max_hp
	w.lightning(eye, aim, C.LIGHT_RANGE, C.LIGHT_DAMAGE * 0.5, false)
	ok(a.hp < a.max_hp and b.hp == b.max_hp and c.hp == c.max_hp, "a partial charge does not chain")


func make_bolt_bot(w, p, dist: float):
	var b = dummy(w, p.pos + Vector3(0.0, 0.0, -dist), 450.0)
	b.bender = true
	b.boss = true
	b.nation = "fire"
	b.light_t = 1.0                                     # it has been charging for 1 s of its 2
	b.pending.append({"kind": "lightning", "t": 1.0, "dir": Vector3(0.0, 0.0, 1.0)})
	return b


func test_bolt_duel() -> void:
	print("-- lightning duel")
	# the player fires first at a charging bot: the bot answers and the bolt comes back at the player
	var f := fresh("fire")
	var w = f[0]
	var p = f[1]
	var b = make_bolt_bot(w, p, 25.0)
	p.hp_delay = 100.0
	var hp0: float = p.hp
	w.lightning(p.pos + Vector3(0.0, 1.5, 0.0), Vector3(0.0, 0.0, -1.0), C.LIGHT_RANGE, 60.0, false)
	ok(not w.bolt_duel.is_empty() and b.hp == b.max_hp and has_wevent(w, "lightning_clash"), "a bolt at a charging enemy waits for their answer")
	for i in range(int(0.3 / TICK)):
		w.update_combat(TICK, p)
	ok(w.bolt_duel.is_empty() and has_wevent(w, "lightning_redirect"), "the bot fires second and the bolt is redirected")
	ok(hp0 - p.hp >= 59.0 and b.hp == b.max_hp, "the first shooter takes the bolt (%.0f), the bot is unhurt" % (hp0 - p.hp))
	w.events.clear()
	for i in range(int(1.2 / TICK)):
		w.update_combat(TICK, p)
	ok(w.bolt_duel.is_empty() and not has_wevent(w, "lightning_clash"), "no second clash or loop afterwards")

	# the bot fires first while the player is charging: the player fires second and sends it back
	f = fresh("fire")
	w = f[0]
	p = f[1]
	b = make_bolt_bot(w, p, 25.0)
	b.pending[0]["t"] = 0.0
	b.pending[0]["dir"] = Vector3(0.0, 0.0, 1.0)
	p.light_t = 1.2
	p.hp_delay = 100.0
	hp0 = p.hp
	w.update_combat(TICK, p)
	ok(not w.bolt_duel.is_empty() and p.hp == hp0 and has_wevent(w, "lightning_clash"), "a bolt at a charging player waits for the answer")
	p.ult = C.ULT_MAX
	p._fire_lightning(p.look_dir(), p.pos + Vector3(0.0, 1.5, 0.0))
	ok(w.bolt_duel.is_empty() and p.hp == hp0 and b.hp < b.max_hp and has_wevent(w, "lightning_redirect"), "the player fires second: the bot takes its own bolt (%.0f)" % (b.max_hp - b.hp))

	# no answer: the bolt lands when the window ends
	f = fresh("fire")
	w = f[0]
	p = f[1]
	b = make_bolt_bot(w, p, 25.0)
	b.pending[0]["t"] = 0.0
	p.light_t = 1.2
	p.hp_delay = 100.0
	hp0 = p.hp
	w.update_combat(TICK, p)
	p.light_t = -1.0
	for i in range(int((C.LIGHT_DUEL_WINDOW + 0.2) / TICK)):
		w.update_combat(TICK, p)
	ok(w.bolt_duel.is_empty() and hp0 - p.hp > 40.0, "with no answer the bolt lands after %.2f s (%.0f)" % [C.LIGHT_DUEL_WINDOW, hp0 - p.hp])

	# a bot that is not charging is hit at once, no waiting
	f = fresh("fire")
	w = f[0]
	p = f[1]
	b = dummy(w, p.pos + Vector3(0.0, 0.0, -25.0))
	w.lightning(p.pos + Vector3(0.0, 1.5, 0.0), Vector3(0.0, 0.0, -1.0), C.LIGHT_RANGE, 100.0, false)
	ok(w.bolt_duel.is_empty() and b.hp < b.max_hp, "a target that is not charging is struck at once")


func test_pellet_sweep() -> void:
	print("-- pellet sweep")
	var f := fresh("fire")
	var w = f[0]
	var h: float = w.height_at(0.0, -30.0)
	var q = w.spawn_proj("fpellet", "player", Vector3(0.0, h + 0.2, -30.0), Vector3(0.0, 64.0, 0.0), 0.3, 0.3, 6.5, 0.0)
	ok(w._swept_solid(q, TICK), "a pellet that skipped over the ground between ticks is caught")
	q.pos.y = h + 5.0
	ok(not w._swept_solid(q, TICK), "and one in open air is not")


func _init() -> void:
	Settings.persist = false
	Settings.ensure_loaded()
	test_combos()
	test_momentum()
	test_burn()
	test_chain()
	test_bolt_duel()
	test_pellet_sweep()
	print("")
	print("ALL PASSED" if failures == 0 else "%d FAILURE(S)" % failures)
	quit(1 if failures > 0 else 0)
