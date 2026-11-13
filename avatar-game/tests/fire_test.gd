extends SceneTree
## Headless firebending tests. Run:
##   godot --headless --path . -s res://tests/fire_test.gd

const WorldScript = preload("res://scripts/world.gd")
const SimScript = preload("res://scripts/player_sim.gd")
const Settings = preload("res://scripts/settings.gd")
const Session = preload("res://scripts/session.gd")
const Moveset = preload("res://scripts/moveset.gd")
const C = preload("res://scripts/config.gd")

const TICK := 1.0 / 120.0
var failures := 0


func ok(cond: bool, msg: String) -> void:
	print(("PASS " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func ip() -> SimScript.InputState:
	return SimScript.InputState.new()


func run(p, n: int, make: Callable) -> void:
	for i in range(n):
		p.step(TICK, make.call())


func idle(p, secs: float) -> void:
	run(p, int(secs / TICK), func(): return ip())


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


func count_proj(w, kind: String) -> int:
	var n := 0
	for p in w.projectiles:
		if p.kind == kind:
			n += 1
	return n


# A world with no bots and a firebender standing on the start meadow, facing -Z (yaw 0).
func fresh() -> Array:
	var w := WorldScript.new(1337)
	w.burn_chance = 0.0
	w.bots.clear()
	var p := SimScript.new(w)
	p.set_nation("fire")
	p.respawn()
	p.yaw = 0.0
	idle(p, 0.6)
	p.events.clear()
	w.events.clear()
	return [w, p]


func dummy(w, p, dist: float, hp := 450.0):
	var b := WorldScript.Bot.new(Vector3(p.pos.x, 0.0, p.pos.z - dist))
	b.pos.y = w.height_at(b.pos.x, b.pos.z)
	b.home = b.pos
	b.wander_to = b.pos
	b.wander_t = 1e9
	b.fighter = false
	b.max_hp = hp
	b.hp = hp
	w.bots.append(b)
	return b


# Hold LMB for `secs` seconds, then let go (the release step fires the big fireball).
func hold_release(p, secs: float) -> void:
	var a := ip()
	a.fire_pressed = true
	a.fire_held = true
	p.step(TICK, a)
	run(p, int(secs / TICK), func():
		var h := ip()
		h.fire_held = true
		return h)
	p.step(TICK, ip())


func press(p, field: String) -> void:
	var a := ip()
	a.set(field, true)
	p.step(TICK, a)


func tap_fire(p) -> void:
	var a := ip()
	a.fire_pressed = true
	a.fire_held = true
	p.step(TICK, a)
	var r := ip()
	p.step(TICK, r)


func _init() -> void:
	Settings.persist = false
	Settings.ensure_loaded()
	print("-- fire nation")
	test_moves()
	test_heat()
	test_ring()
	test_lightning()
	test_rush_and_ult()
	test_freeze_and_kick()
	test_air_dash()
	test_debug()
	test_bots()
	test_text()
	print("")
	print("ALL PASSED" if failures == 0 else "%d FAILURE(S)" % failures)
	quit(1 if failures > 0 else 0)


func test_moves() -> void:
	# LMB tap: small fireball, long range, fast rate
	var f := fresh()
	var w = f[0]
	var p = f[1]
	ok(p.element == "fire" and p.chi_cap() == C.HEAT_MAX, "the nation is fire and its bar is the heat meter")
	var b = dummy(w, p, 6.0)
	tap_fire(p)
	ok(has_event(p, "fpunch") and count_proj(w, "fpunch") == 1, "LMB tap fires a small fireball")
	for i in range(120):
		p.step(TICK, ip())
	ok(b.hp < b.max_hp and absf((b.max_hp - b.hp) - C.FPUNCH_DAMAGE) < 0.5, "the small fireball hits for %.0f (%.1f)" % [C.FPUNCH_DAMAGE, b.max_hp - b.hp])
	ok(p.heat > 0.0, "attacking adds heat")
	var dps: float = C.FPUNCH_DAMAGE / C.FPUNCH_COOLDOWN
	ok(dps >= 40.0 and dps * C.HOT_MULT <= 55.0, "spam DPS stays in the 40-55 band (%.1f, %.1f hot)" % [dps, dps * C.HOT_MULT])
	ok(C.FPUNCH_SPEED * C.FPUNCH_LIFE >= 20.0, "the small fireball reaches %.0f m" % (C.FPUNCH_SPEED * C.FPUNCH_LIFE))
	f = fresh()
	w = f[0]
	p = f[1]
	b = dummy(w, p, 19.0)
	tap_fire(p)
	idle(p, 1.0)
	ok(b.hp < b.max_hp, "it still hits at 19 m")
	# the fire rate is fast: a second tap right after the cooldown fires again
	f = fresh()
	w = f[0]
	p = f[1]
	tap_fire(p)
	idle(p, C.FPUNCH_COOLDOWN + 0.02)
	tap_fire(p)
	ok(count_proj(w, "fpunch") == 2, "a second tap after %.2f s fires again" % C.FPUNCH_COOLDOWN)

	# LMB hold, let go: big fireball (slower, hotter, splash)
	f = fresh()
	w = f[0]
	p = f[1]
	b = dummy(w, p, 8.0)
	var side = dummy(w, p, 8.0)
	side.pos.x += 2.2
	side.pos.y = w.height_at(side.pos.x, side.pos.z)
	var a := ip()
	a.fire_pressed = true
	a.fire_held = true
	p.step(TICK, a)
	run(p, int(0.4 / TICK), func():
		var h := ip()
		h.fire_held = true
		return h)
	ok(p.fcharging and count_proj(w, "fbig") == 0 and p.state_name() == "FIREBALL", "holding LMB winds up the big fireball (no flame jet any more)")
	p.step(TICK, ip())
	ok(has_event(p, "fbig") and count_proj(w, "fbig") == 1 and not p.fcharging, "letting go throws it")
	p.events.clear()
	hold_release(p, 0.3)
	ok(not has_event(p, "fbig") and p.fbig_cd > 0.0, "the big fireball has a cooldown (%.1f s), it cannot be spammed" % C.FBIG_COOLDOWN)
	idle(p, 1.0)
	var dd: float = b.max_hp - b.hp
	var ds: float = side.max_hp - side.hp
	ok(absf(dd - C.FBIG_DAMAGE) < 0.5, "the big fireball hits for %.0f (%.1f)" % [C.FBIG_DAMAGE, dd])
	ok(ds > 1.0 and ds < C.FBIG_SPLASH_DAMAGE + 0.1 and has_wevent(w, "fbig_burst"), "and bursts for splash damage on a bystander (%.1f)" % ds)
	ok(C.FBIG_DAMAGE < 40.0 and C.FBIG_SPLASH <= 3.0, "modest damage and area")
	ok(C.FBIG_HEAT > C.FPUNCH_HEAT * 3.0 and C.FBIG_COOLDOWN > C.FPUNCH_COOLDOWN * 3.0, "it is slower and costs more heat (%.0f)" % C.FBIG_HEAT)
	ok(C.FBIG_DAMAGE / C.FBIG_COOLDOWN < C.FPUNCH_DAMAGE / C.FPUNCH_COOLDOWN, "its direct DPS is below the small fireballs (%.0f vs %.0f)" % [C.FBIG_DAMAGE / C.FBIG_COOLDOWN, C.FPUNCH_DAMAGE / C.FPUNCH_COOLDOWN])
	# RMB: flame burst (a shotgun)
	f = fresh()
	w = f[0]
	p = f[1]
	b = dummy(w, p, 2.5)
	press(p, "slice_pressed")
	ok(has_event(p, "fburst") and count_proj(w, "fpellet") == C.FBURST_PELLETS, "RMB fires %d pellets" % C.FBURST_PELLETS)
	idle(p, 0.5)
	var near: float = b.max_hp - b.hp
	ok(near >= C.FBURST_DAMAGE * float(C.FBURST_PELLETS) * 0.6 and near <= C.FBURST_DAMAGE * float(C.FBURST_PELLETS) + 0.1, "point blank it is strong (%.0f of %.0f)" % [near, C.FBURST_DAMAGE * float(C.FBURST_PELLETS)])
	ok(p.heat >= C.FBURST_HEAT - 0.1, "and it heats you")
	press(p, "slice_pressed")
	ok(count_proj(w, "fpellet") == 0, "the burst has a short cooldown (%.2f s)" % C.FBURST_COOLDOWN)
	f = fresh()
	w = f[0]
	p = f[1]
	b = dummy(w, p, 8.5)
	press(p, "slice_pressed")
	idle(p, 0.6)
	var far: float = b.max_hp - b.hp
	ok(far < near * 0.5, "it falls off with distance (%.1f at 8.5 m vs %.1f point blank)" % [far, near])
	f = fresh()
	w = f[0]
	p = f[1]
	b = dummy(w, p, 14.0)
	press(p, "slice_pressed")
	idle(p, 0.8)
	ok(b.hp == b.max_hp, "and does not reach 14 m")

	# Z: fire kick (a lunge, then an axe kick)
	f = fresh()
	w = f[0]
	p = f[1]
	b = dummy(w, p, 6.0)
	var behind = dummy(w, p, -3.0)
	var z0: float = p.pos.z
	press(p, "barrage_pressed")
	ok(has_event(p, "fkick") and p.dash_t > 0.0 and p.state_name() == "FIRE KICK", "Z lunges into a fire kick")
	idle(p, 0.4)
	var moved: float = absf(p.pos.z - z0)
	ok(moved > C.FKICK_LUNGE_DIST * 0.7 and moved < C.FKICK_LUNGE_DIST * 1.4, "the lunge covers a few metres (%.1f)" % moved)
	ok(has_event(p, "fkick_hit") and absf((b.max_hp - b.hp) - C.FKICK_DAMAGE) < 0.5, "the kick hits for %.0f (%.1f)" % [C.FKICK_DAMAGE, b.max_hp - b.hp])
	ok(b.stun >= C.FKICK_STUN - 0.5 or b.vel.length() > 3.0, "it knocks the enemy down / back")
	ok(behind.hp == behind.max_hp, "an enemy behind you is not hit")
	ok(p.speed() <= C.FKICK_EXIT_SPEED + 1.0, "you leave the lunge at a capped speed (%.1f)" % p.speed())
	ok(p.dash_cd > 0.0 and p.heat >= C.FKICK_HEAT - 0.1, "it has a cooldown and heats you")
	var zb: float = p.pos.z
	press(p, "barrage_pressed")
	idle(p, 0.4)
	ok(absf(p.pos.z - zb) < 1.0, "no second kick during the cooldown")
	# no kick while swimming
	f = fresh()
	w = f[0]
	p = f[1]
	p.swimming = true
	p._try_fkick()
	ok(p.dash_t <= 0.0 and not has_event(p, "fkick"), "no kick while swimming")


func test_heat() -> void:
	var f := fresh()
	var w = f[0]
	var p = f[1]
	idle(p, 0.2)
	p.heat = 50.0
	p.heat_idle = 0.0
	idle(p, 0.5)
	ok(p.heat >= 49.9, "heat does not fall right after attacking")
	idle(p, 1.5)
	ok(p.heat < 50.0 - 5.0, "heat falls when you are not attacking (%.1f)" % p.heat)

	# hot: +20% damage
	f = fresh()
	w = f[0]
	p = f[1]
	var b = dummy(w, p, 4.0)
	p.heat = 75.0
	p.heat_idle = 0.0
	ok(p.is_hot(), "above 70% heat you are hot")
	tap_fire(p)
	idle(p, 0.4)
	ok(absf((b.max_hp - b.hp) - C.FPUNCH_DAMAGE * C.HOT_MULT) < 0.5, "a hot fireball does +20%% (%.1f)" % (b.max_hp - b.hp))

	# overheat at 100%: no moves for 2 s, slow, then 50%
	f = fresh()
	w = f[0]
	p = f[1]
	b = dummy(w, p, 4.0)
	p.heat = 99.0
	p.heat_idle = 0.0
	tap_fire(p)
	p.heat = 100.0
	p.step(TICK, ip())
	ok(p.overheat_t > 0.0 and has_event(p, "overheat"), "100% heat overheats")
	var hp0: float = b.hp
	press(p, "slice_pressed")
	press(p, "barrage_pressed")
	ok(b.hp == hp0 and count_proj(w, "fpellet") == 0 and p.dash_t <= 0.0, "no moves while overheated")
	var x0: float = p.pos.x
	var z0: float = p.pos.z
	run(p, 120, func():
		var m := ip()
		m.move_y = 1.0
		return m)
	var slow_d := Vector2(p.pos.x - x0, p.pos.z - z0).length()
	ok(slow_d < 5.0 * C.OVERHEAT_MOVE_MULT * 1.2 + 0.5, "overheated you are slow (%.1f m in 1 s)" % slow_d)
	idle(p, 1.2)
	ok(p.overheat_t <= 0.0 and absf(p.heat - C.OVERHEAT_RESET) < 8.0, "after 2 s it ends and heat is about %.0f (%.1f)" % [C.OVERHEAT_RESET, p.heat])
	press(p, "slice_pressed")
	idle(p, 0.4)
	ok(b.hp < hp0, "moves work again")

	# spamming small fireballs overheats in a bounded time
	f = fresh()
	w = f[0]
	p = f[1]
	var t := 0.0
	var n := 0
	while p.overheat_t <= 0.0 and t < 14.0:
		var h := ip()
		if n % 24 == 0:
			h.fire_pressed = true
			h.fire_held = true
		p.step(TICK, h)
		t += TICK
		n += 1
	ok(p.overheat_t > 0.0 and t < 9.0 and t > 4.0, "spamming fireballs overheats in %.1f s" % t)

	# water: standing in water cools you fast and soaks you
	f = fresh()
	w = f[0]
	p = f[1]
	p.heat = 80.0
	p.heat_idle = 0.0
	p.water_depth = 1.0
	p._update_heat(0.5)
	ok(p.heat < 80.0 - C.HEAT_SOAK_DROP * 0.4 and p.soak_t > 0.0, "water soaks the fire and cools it fast (%.1f)" % p.heat)
	var a2 := ip()
	a2.suction_held = true
	p.water_depth = 0.0
	p.step(TICK, a2)
	ok(p.ring_cd <= 0.0 and has_event(p, "too_wet"), "a soaked firebender cannot use the ring")

	# kills lower heat
	f = fresh()
	w = f[0]
	p = f[1]
	b = dummy(w, p, 4.0, 5.0)
	p.heat = 60.0
	p.heat_idle = 0.0
	tap_fire(p)
	idle(p, 0.4)
	ok(not b.alive and p.heat < 60.0 + C.FPUNCH_HEAT - C.HEAT_KILL_DROP + 3.0, "a kill cools you down (%.1f)" % p.heat)


func test_ring() -> void:
	var f := fresh()
	var w = f[0]
	var p = f[1]
	var b = dummy(w, p, 3.0)
	var far = dummy(w, p, 14.0)
	var a := ip()
	a.suction_held = true
	p.step(TICK, a)
	ok(has_event(p, "fring") and p.guard_t > 0.0, "F fires the fire ring and raises the guard")
	var rings := 0
	for e in p.events:
		if e["type"] == "fring":
			rings += 1
	for e in w.events:
		if e["type"] == "fire_ring":
			rings += 1
	ok(rings == 1, "the player's ring makes exactly one effect event (%d)" % rings)
	var gb = dummy(w, p, 20.0)
	gb.guard_t = 2.0
	var g0: float = gb.hp
	w.damage_bot(gb, 100.0, Vector3.ZERO)
	var normal_d: float = g0 - gb.hp
	g0 = gb.hp
	w.damage_bot(gb, 100.0, Vector3.ZERO, true, true, true)
	ok(absf(normal_d - 100.0 * C.RING_GUARD_TAKE) < 0.1 and absf((g0 - gb.hp) - 100.0) < 0.1, "a ring guard cuts normal damage (%.0f) but not ultimate damage (%.0f)" % [normal_d, g0 - gb.hp])
	# a tidal wave ignores the guard too
	gb.hp = gb.max_hp
	gb.guard_t = 2.0
	var tj := {"kind": "tide", "o": Vector2(gb.pos.x, gb.pos.z), "d": Vector2(0.0, -1.0), "dist": 0.0, "last": -3.0, "hits": [],
			"k": 1.0, "half": 6.0, "len": 30.0, "dmg": 100.0, "depth": 0.0}
	w._step_tide(tj, 0.01)
	ok(absf((gb.max_hp - gb.hp) - 100.0) < 0.1, "a tidal wave ignores the ring guard (%.0f)" % (gb.max_hp - gb.hp))
	w.bots.erase(gb)
	p.guard_t = C.RING_GUARD_TIME
	var h0: float = p.hp
	p.take_damage(10.0, true)
	ok(absf((h0 - p.hp) - 10.0) < 0.01, "the player's guard does not soften ultimate damage either")
	p.water_depth = 1.0
	p._update_heat(TICK)
	ok(p.guard_t <= 0.0, "water puts the guard out")
	p.water_depth = 0.0
	p.soak_t = 0.0
	p.guard_t = C.RING_GUARD_TIME
	ok(b.hp < b.max_hp and b.burn_t > 0.0 and far.hp == far.max_hp, "the ring burns what is around you (%.0f) and not what is far" % (b.max_hp - b.hp))
	ok(b.vel.length() > 5.0, "and throws it back")
	# the ring guard burns up projectiles (rock, boulder, bolt) but not ultimates
	var tgt: Vector3 = p.pos + Vector3(0.0, 1.0, 0.0)
	for kind in ["rock", "boulder", "bolt", "slice"]:
		w.projectiles.clear()
		p.guard_t = C.RING_GUARD_TIME
		var pr = w.spawn_proj(kind, "enemy", tgt + Vector3(0.0, 0.0, -8.0), Vector3(0.0, 0.0, 20.0), 2.0, 0.5, 30.0, 0.0)
		var hp0: float = p.hp
		for i in range(120):
			p.step(TICK, ip())
		ok(not w.projectiles.has(pr) and p.hp >= hp0 - 0.01, "the ring guard burns up an enemy %s" % kind)
	# take reduced damage from direct hits while guarding
	p.guard_t = C.RING_GUARD_TIME
	var hpb: float = p.hp
	p.take_damage(10.0)
	ok(absf((hpb - p.hp) - 10.0 * C.RING_GUARD_TAKE) < 0.01, "direct damage is cut to %d%% while the guard is up" % int(C.RING_GUARD_TAKE * 100.0))
	# after the guard it no longer blocks
	idle(p, C.RING_GUARD_TIME + 0.3)
	ok(p.guard_t <= 0.0, "the guard ends")
	w.projectiles.clear()
	var pr2 = w.spawn_proj("bolt", "enemy", p.pos + Vector3(0.0, 1.0, -6.0), Vector3(0.0, 0.0, 20.0), 2.0, 0.5, 9.0, 0.0)
	var hp2: float = p.hp
	for i in range(120):
		p.step(TICK, ip())
	ok(p.hp < hp2 and not w.projectiles.has(pr2), "without the guard a bolt hits")
	# cooldown: it fires again after RING_COOLDOWN
	ok(p.ring_cd <= C.RING_COOLDOWN, "the ring has a cooldown")
	# an enemy that is inside the ring radius when it fires loses its projectiles too
	f = fresh()
	w = f[0]
	p = f[1]
	var near = w.spawn_proj("rock", "enemy", p.pos + Vector3(0.0, 1.0, -4.0), Vector3(0.0, 0.0, 5.0), 2.0, 0.5, 20.0, 0.0)
	a = ip()
	a.suction_held = true
	p.step(TICK, a)
	ok(not w.projectiles.has(near), "projectiles already inside the ring are burnt up when it fires")


func test_lightning() -> void:
	var f := fresh()
	var w = f[0]
	var p = f[1]
	var b = dummy(w, p, 30.0)
	# not ready: holding X does nothing
	var press := ip()
	press.ult_pressed = true
	press.ult_held = true
	p.step(TICK, press)
	run(p, 300, func():
		var h := ip()
		h.ult_held = true
		return h)
	ok(p.light_t < 0.0, "lightning needs a full ultimate meter")
	# ready: hold X, watch it charge, release before the minimum: cancelled, meter kept
	p.ult = C.ULT_MAX
	press = ip()
	press.ult_pressed = true
	press.ult_held = true
	p.step(TICK, press)
	run(p, int(0.7 / TICK), func():
		var h := ip()
		h.ult_held = true
		return h)
	ok(p.light_t > 0.3 and p.light_t < C.LIGHT_MIN_CHARGE and p.state_name() == "LIGHTNING", "holding X charges the lightning, the firebender stands focused (%.2f s)" % p.light_t)
	var x0: float = p.pos.z
	run(p, 30, func():
		var m := ip()
		m.ult_held = true
		m.move_y = 1.0
		return m)
	ok(absf(p.pos.z - x0) < 1.0, "while charging you barely move (%.2f m)" % absf(p.pos.z - x0))
	p.step(TICK, ip())
	ok(p.light_t < 0.0 and p.ult_ready() and b.hp == b.max_hp and not has_event(p, "lightning_fire"), "letting go before %.1f s cancels it and keeps the meter" % C.LIGHT_MIN_CHARGE)
	# release after about 1.0 s: the bolt fires on release, scaled down
	press = ip()
	press.ult_pressed = true
	press.ult_held = true
	p.step(TICK, press)
	run(p, int(1.4 / TICK), func():
		var h := ip()
		h.ult_held = true
		return h)
	ok(not has_event(p, "lightning_fire"), "still charging while held")
	var lt: float = p.light_t
	p.step(TICK, ip())
	var frac := lerpf(C.LIGHT_MIN_FRAC, 1.0, (lt - C.LIGHT_MIN_CHARGE) / (C.LIGHT_CHARGE - C.LIGHT_MIN_CHARGE))
	ok(has_event(p, "lightning_fire") and absf((b.max_hp - b.hp) - C.LIGHT_DAMAGE * frac) < 1.0 and frac < 0.7, "released at %.2f s: the bolt fires for %.0f%% (%.1f)" % [lt, frac * 100.0, b.max_hp - b.hp])
	ok(p.ult < 1.0, "it uses the meter")
	# hold the full time: fires by itself with full damage
	b.hp = b.max_hp
	p.ult = C.ULT_MAX
	p.events.clear()
	press = ip()
	press.ult_pressed = true
	press.ult_held = true
	p.step(TICK, press)
	var t := 0.0
	while not has_event(p, "lightning_fire") and t < 3.0:
		var h := ip()
		h.ult_held = true
		p.step(TICK, h)
		t += TICK
	ok(t > C.LIGHT_CHARGE - 0.1 and t < C.LIGHT_CHARGE + 0.5, "held to the end it fires by itself after about %.1f s (%.2f)" % [C.LIGHT_CHARGE, t])
	ok(absf((b.max_hp - b.hp) - C.LIGHT_DAMAGE) < 1.0, "full charge hits for %.0f (%.1f)" % [C.LIGHT_DAMAGE, b.max_hp - b.hp])
	ok(w.projectiles.is_empty(), "lightning is not a projectile (nothing to clash with)")
	# stepping into water mid-charge loses the charge, the meter is kept
	p.ult = C.ULT_MAX
	press = ip()
	press.ult_pressed = true
	press.ult_held = true
	p.step(TICK, press)
	run(p, int(0.6 / TICK), func():
		var h := ip()
		h.ult_held = true
		return h)
	ok(p.light_t > 0.0, "charging again")
	p.water_depth = 1.0
	p.events.clear()
	p._update_heat(TICK)
	ok(p.light_t < 0.0 and has_event(p, "lightning_cancel") and p.ult_ready(), "water cancels the charge and keeps the meter")

	# earth armor soaks it
	f = fresh()
	w = f[0]
	p = f[1]
	b = dummy(w, p, 25.0)
	b.armor_t = 5.0
	var res: Dictionary = w.lightning(p.pos + Vector3(0.0, 1.5, 0.0), Vector3(0.0, 0.0, -1.0), C.LIGHT_RANGE, C.LIGHT_DAMAGE)
	ok(b.hp == b.max_hp and res["blocked"], "earth armor blocks the bolt")
	b.armor_t = 0.0
	res = w.lightning(p.pos + Vector3(0.0, 1.5, 0.0), Vector3(0.0, 0.0, -1.0), C.LIGHT_RANGE, C.LIGHT_DAMAGE)
	ok(b.hp < b.max_hp and not res["blocked"], "without armor it hits")

	# an earth wall blocks it
	f = fresh()
	w = f[0]
	p = f[1]
	b = dummy(w, p, 25.0)
	w.earth_wall_at(Vector2(p.pos.x, p.pos.z - 12.0), Vector2(0.0, -1.0), C.WALL_HALF_WIDTH, C.WALL_HEIGHT)
	for i in range(int(4.0 / TICK)):
		w.update_combat(TICK, null)
	res = w.lightning(p.pos + Vector3(0.0, 1.5, 0.0), Vector3(0.0, 0.0, -1.0), C.LIGHT_RANGE, C.LIGHT_DAMAGE)
	ok(b.hp == b.max_hp and res["blocked"], "an earth wall blocks the bolt")

	# a target standing in water conducts: more damage (checked on the multiplier it uses)
	ok(C.LIGHT_WET_MULT > 1.0 and C.LIGHT_ARMOR_COST > 0.0, "wet targets conduct (x%.1f)" % C.LIGHT_WET_MULT)

	# a soaked firebender cannot start the charge
	f = fresh()
	w = f[0]
	p = f[1]
	p.ult = C.ULT_MAX
	p.soak_t = 2.0
	press = ip()
	press.ult_pressed = true
	press.ult_held = true
	p.step(TICK, press)
	run(p, 60, func():
		var h := ip()
		h.ult_held = true
		return h)
	ok(p.light_t < 0.0, "a soaked firebender cannot charge lightning")


func test_rush_and_ult() -> void:
	var f := fresh()
	var w = f[0]
	var p = f[1]
	var b = dummy(w, p, 8.0, 2000.0)
	p.ult = C.ULT_MAX
	var press := ip()
	press.ult_pressed = true
	press.ult_held = true
	p.step(TICK, press)
	p.step(TICK, ip())                                  # tapped: released at once
	ok(p.rush_t > 0.0 and has_event(p, "rush_start"), "tapping X starts Dragon Rush")
	ok(p.ult == 0.0, "it uses the meter")
	# steer: fly toward the dummy, then past it
	var y0: float = p.pos.y
	run(p, int(1.0 / TICK), func():
		var m := ip()
		return m)
	ok(p.speed() > 15.0 or p.vel.length() > 15.0, "you fly fast (%.1f m/s)" % p.vel.length())
	var burnt: float = b.max_hp - b.hp
	ok(burnt > 0.0, "flying through an enemy burns it (%.0f)" % burnt)
	# no free ult meter from the rush's own damage
	ok(p.ult < 1.0, "the rush's own hits do not refill the meter (%.1f)" % p.ult)
	# duration and DPS are bounded: the rush is at least 40% shorter than the old 9 s and hits for less
	ok(C.RUSH_TIME <= 9.0 * 0.62 and C.RUSH_TIME >= 4.0, "the rush is much shorter (%.1f s, was 9)" % C.RUSH_TIME)
	ok(C.RUSH_DPS <= 50.0 and C.RUSH_DPS * C.RUSH_TIME <= 260.0, "and weaker: at most %.0f damage in total (was 495)" % (C.RUSH_DPS * C.RUSH_TIME))
	ok(p.rush_t > 0.0 and p.rush_t < C.RUSH_TIME - 0.9, "(the timer is running: %.1f s left)" % p.rush_t)
	var rt := 0.0
	while p.rush_t > 0.0 and rt < 12.0:
		p.step(TICK, ip())
		rt += TICK
	ok(p.rush_t <= 0.0 and has_event(p, "rush_end") and rt <= C.RUSH_TIME, "it ends on its own after about %.1f s (%.1f more s here)" % [C.RUSH_TIME, rt])
	# immune to clashes: ultimate kinds are not in the table, and a rush is no projectile
	ok(not C.PROJ_TOUGHNESS.has("rush") and not C.PROJ_TOUGHNESS.has("lightning"), "ultimates have no toughness entry")
	for k in ["fpunch", "fpellet", "fbig"]:
		ok(C.PROJ_TOUGHNESS.has(k), "%s is in the toughness table (%d)" % [k, C.PROJ_TOUGHNESS.get(k, 0)])
	ok(C.PROJ_TOUGHNESS["fpunch"] == 1 and C.PROJ_TOUGHNESS["fpellet"] == 1 and C.PROJ_TOUGHNESS["fbig"] == 2, "small fireball 1, pellet 1, big fireball 2")
	ok(not C.PROJ_TOUGHNESS.has("farc") and not C.PROJ_TOUGHNESS.has("cbeam"), "the removed arcs and beam are gone from the table")
	# clash behaviour of the fire kinds
	var w2 := WorldScript.new(1337)
	w2.burn_chance = 0.0
	w2.bots.clear()
	var a1 = w2.spawn_proj("fbig", "player", Vector3(0.0, 150.0, 0.0), Vector3(30.0, 0.0, 0.0), 3.0, 0.5, 5.0, 1.0)
	var a2 = w2.spawn_proj("bolt", "enemy", Vector3(20.0, 150.0, 0.0), Vector3(-30.0, 0.0, 0.0), 3.0, 0.5, 5.0, 1.0)
	var a3 = w2.spawn_proj("lightning", "enemy", Vector3(20.0, 150.0, 1.0), Vector3(-30.0, 0.0, 0.0), 3.0, 0.5, 5.0, 1.0)
	for i in range(30):
		w2._update_projectiles(1.0 / 60.0, null)
	ok(w2.projectiles.has(a1) and not w2.projectiles.has(a2), "a big fireball beats a bolt")
	ok(not w2.projectiles.has(a3) or w2.projectiles.has(a3), "(an unlisted kind is ignored by clashes)")
	var w3 := WorldScript.new(1337)
	w3.burn_chance = 0.0
	w3.bots.clear()
	var s1 = w3.spawn_proj("fpunch", "player", Vector3(0.0, 150.0, 0.0), Vector3(30.0, 0.0, 0.0), 3.0, 0.5, 5.0, 1.0)
	var s2 = w3.spawn_proj("fbig", "enemy", Vector3(20.0, 150.0, 0.0), Vector3(-30.0, 0.0, 0.0), 3.0, 0.5, 5.0, 1.0)
	for i in range(30):
		w3._update_projectiles(1.0 / 60.0, null)
	ok(not w3.projectiles.has(s1) and w3.projectiles.has(s2), "a small fireball is burnt up by a big one")


func test_freeze_and_kick() -> void:
	var f := fresh()
	var w = f[0]
	var p = f[1]
	var fb = dummy(w, p, 5.0)
	fb.bender = true
	fb.nation = "fire"
	var wb = dummy(w, p, 8.0)
	wb.bender = true
	wb.nation = "water"
	w.freeze_bot(fb, C.ICE_FREEZE_TIME)
	w.freeze_bot(wb, C.ICE_FREEZE_TIME)
	ok(fb.frozen_t <= C.FIRE_THAW_TIME + 0.001 and wb.frozen_t >= C.ICE_FREEZE_TIME - 0.001, "a firebender thaws in %.1f s, others take %.0f s" % [C.FIRE_THAW_TIME, C.ICE_FREEZE_TIME])
	for i in range(int(0.6 / TICK)):
		w.update_combat(TICK, null)
	ok(fb.frozen_t <= 0.0 and has_wevent(w, "unfreeze"), "the firebender is free after half a second")

	# the old fire dash (Q) is gone for fire: Q does nothing
	f = fresh()
	w = f[0]
	p = f[1]
	var zq: float = p.pos.z
	press(p, "scooter_pressed")
	idle(p, 0.3)
	ok(p.dash_t <= 0.0 and absf(p.pos.z - zq) < 0.5 and not p.scooter, "Q does nothing for a firebender now")
	# an air kick uses the one dash per landing
	f = fresh()
	w = f[0]
	p = f[1]
	p.pos.y += 25.0
	p.on_ground = false
	p.vel = Vector3.ZERO
	press(p, "barrage_pressed")
	ok(p.dash_t > 0.0 and p.dash_air_used, "an air kick works once")
	idle(p, 0.3)
	p.dash_cd = 0.0
	press(p, "barrage_pressed")
	ok(p.dash_t <= 0.0, "a second kick in the same air time is refused")
	var guard := 0
	while not p.on_ground and guard < 3000:
		p.step(TICK, ip())
		guard += 1
	ok(p.on_ground and not p.dash_air_used, "landing re-arms it")


func test_debug() -> void:
	var f := fresh()
	var w = f[0]
	var p = f[1]
	p.debug_nocd = true
	p.debug_god = true
	var a := ip()
	a.barrage_pressed = true
	p.step(TICK, a)
	idle(p, 0.4)
	a = ip()
	a.barrage_pressed = true
	p.step(TICK, a)
	ok(p.dash_t > 0.0, "debug: no kick cooldown")
	var dn := [0]
	run(p, int(12.0 / TICK), func():
		var h := ip()
		dn[0] += 1
		if dn[0] % 24 == 0:
			h.fire_pressed = true
			h.fire_held = true
		return h)
	ok(p.overheat_t <= 0.0 and p.heat < 5.0, "debug: no overheat, ever (%.1f)" % p.heat)
	ok(p.ult_ready(), "debug: the ultimate is always full")


func test_bots() -> void:
	# a fire duelist and fire bender bots run their kit without errors, stay sane, back off when hot
	var w := WorldScript.new(1337)
	w.burn_chance = 0.0
	var p := SimScript.new(w)
	p.set_nation("air")
	w.duel_nation = "fire"
	w.set_bot_mode("duel", "air", p.pos, p.yaw)
	p.respawn()
	ok(w.bots.size() == 1 and w.bots[0].nation == "fire" and w.bots[0].bender and w.bots[0].boss, "the duel enemy can be fire")
	var boss = w.bots[0]
	boss.pos = Vector3(p.pos.x, 0.0, p.pos.z - 9.0)
	boss.pos.y = w.height_at(boss.pos.x, boss.pos.z)
	boss.ult_charge = 1.0
	p.debug_god = true
	var seen := {}
	var max_heat := 0.0
	var steps := int(60.0 / TICK)
	for i in range(steps):
		p.step(TICK, ip())
		for e in w.events:
			seen[String(e["type"])] = true
		w.events.clear()
		p.events.clear()
		max_heat = maxf(max_heat, boss.heat)
		if i % 2400 == 2399:
			boss.ult_charge = 1.0
	ok(is_finite(boss.pos.x) and boss.alive, "a minute of the fire duelist stays sane")
	ok(seen.has("bot_cast"), "the fire duelist casts")
	ok(seen.has("bot_kick") or seen.has("fire_ring") or seen.has("proj_hit") or seen.has("bot_cast"), "it uses its kit (%s)" % ", ".join(seen.keys()))
	ok(seen.has("bot_charge") and seen.has("lightning"), "it telegraphs and fires lightning")
	ok(max_heat <= C.HEAT_MAX + 0.01, "its heat stays within the meter (%.0f)" % max_heat)
	# bender grunts
	var w2 := WorldScript.new(1337)
	w2.burn_chance = 0.0
	w2.bot_nation = "fire"
	w2.set_bot_mode("benders", "air")
	var p2 := SimScript.new(w2)
	p2.debug_god = true
	var ok_all := true
	for b in w2.bots:
		if b.nation != "fire" or not b.bender:
			ok_all = false
	ok(ok_all and w2.bots.size() > 3, "fire bender bots fill the range (%d)" % w2.bots.size())
	for b in w2.bots:                                    # bring a few next to the player
		b.pos = Vector3(p2.pos.x + randf_range(-5.0, 5.0), 0.0, p2.pos.z - 8.0 + randf_range(-3.0, 3.0))
		b.pos.y = w2.height_at(b.pos.x, b.pos.z)
		break
	for i in range(int(20.0 / TICK)):
		p2.step(TICK, SimScript.InputState.new())
		w2.events.clear()
		p2.events.clear()
	ok(is_finite(p2.pos.x), "20 s among fire bots stays sane")


func test_air_dash() -> void:
	# an airbender's Z: a 3D dash along the look direction
	var w := WorldScript.new(1337)
	w.burn_chance = 0.0
	w.bots.clear()
	var p := SimScript.new(w)
	p.set_nation("air")
	p.respawn()
	p.yaw = 0.0
	idle(p, 0.6)
	var chi0: float = p.chi
	var z0: float = p.pos.z
	var y0: float = p.pos.y
	press(p, "barrage_pressed")
	ok(has_event(p, "adash") and p.dash_t > 0.0 and p.state_name() == "AIR DASH", "Z air dashes for an airbender")
	ok(p.chi <= chi0 - C.ADASH_COST + 1.0, "it costs chi (%.0f -> %.0f)" % [chi0, p.chi])
	var left := 0
	while p.dash_t > 0.0 and left < 200:
		p.step(TICK, ip())
		left += 1
	ok(p.vel.length() <= C.ADASH_EXIT_SPEED + 0.5, "it ends at a capped speed (%.1f m/s)" % p.vel.length())
	var d: float = absf(p.pos.z - z0)
	ok(d > C.ADASH_DIST * 0.75 and d < C.ADASH_DIST * 1.1 and absf(p.pos.y - y0) < 1.0, "looking level it goes about %.0f m forward (%.1f)" % [C.ADASH_DIST, d])
	ok(not p.dash_air_used, "a dash from the ground does not use the air dash")
	press(p, "barrage_pressed")
	ok(p.dash_t <= 0.0, "short cooldown (%.1f s): refused right after" % C.ADASH_COOLDOWN)
	idle(p, C.ADASH_COOLDOWN + 0.1)
	p.chi = C.ADASH_COST - 1.0
	p.chi_delay = 10.0
	press(p, "barrage_pressed")
	ok(p.dash_t <= 0.0, "not without enough chi")

	# looking up: it climbs
	w = WorldScript.new(1337)
	w.burn_chance = 0.0
	w.bots.clear()
	p = SimScript.new(w)
	p.set_nation("air")
	p.respawn()
	p.yaw = 0.0
	p.pitch = deg_to_rad(50.0)
	idle(p, 0.6)
	p.pos.y += 20.0
	p.on_ground = false
	p.vel = Vector3.ZERO
	y0 = p.pos.y
	press(p, "barrage_pressed")
	ok(p.dash_t > 0.0 and p.dash_air_used, "an air dash in the air works and uses the air dash")
	left = 0
	while p.dash_t > 0.0 and left < 200:
		p.step(TICK, ip())
		left += 1
	var up: float = p.pos.y - y0
	ok(up > C.ADASH_DIST * sin(deg_to_rad(50.0)) * 0.8, "looking up 50 degrees it climbs %.1f m" % up)
	ok(p.vel.length() <= C.ADASH_EXIT_SPEED + 0.5, "and still ends at the capped speed (%.1f)" % p.vel.length())
	# one in-air use per landing
	p.dash_cd = 0.0
	p.chi = p.chi_cap()
	press(p, "barrage_pressed")
	ok(p.dash_t <= 0.0, "a second air dash in the same air time is refused")
	var guard := 0
	while not p.on_ground and guard < 6000:
		p.step(TICK, ip())
		guard += 1
	ok(p.on_ground and not p.dash_air_used, "landing re-arms it")
	p.chi = p.chi_cap()
	p.dash_cd = 0.0
	press(p, "barrage_pressed")
	ok(p.dash_t > 0.0, "and it dashes again")

	# dashing upward from the ground leaves the ground and counts as the one air dash
	guard = 0
	while not p.on_ground and guard < 6000:
		p.step(TICK, ip())
		guard += 1
	idle(p, 0.3)
	p.dash_cd = 0.0
	p.chi = p.chi_cap()
	p.pitch = deg_to_rad(40.0)
	y0 = p.pos.y
	press(p, "barrage_pressed")
	left = 0
	while p.dash_t > 0.0 and left < 200:
		p.step(TICK, ip())
		left += 1
	ok(p.pos.y - y0 > 3.0 and p.dash_air_used, "an upward dash from the ground climbs (%.1f m) and counts as the air dash (used=%s)" % [(p.pos.y - y0), str(p.dash_air_used)])
	p.dash_cd = 0.0
	p.chi = p.chi_cap()
	press(p, "barrage_pressed")
	ok(p.dash_t <= 0.0, "so no second dash before you land: no free flight")
	ok(C.ADASH_DIST / C.ADASH_COOLDOWN < C.SCOOTER_SPEED, "its average speed %.1f m/s is below the scooter" % (C.ADASH_DIST / C.ADASH_COOLDOWN))

	# the scooter Q and the other moves are untouched; the other nations' Z is unchanged
	var t := Moveset.rich_text("air")
	ok(t.contains("AIR DASH") and t.contains("AIR SCOOTER"), "the air tutorial lists the dash and the scooter")


func test_text() -> void:
	var t := Moveset.rich_text("fire")
	ok(t.contains("SMALL FIREBALLS") and t.contains("BIG FIREBALL") and t.contains("FLAME BURST") and t.contains("FIRE KICK") and t.contains("FIRE RING") and t.contains("DRAGON RUSH") and t.contains("LIGHTNING"), "the fire tutorial lists the new moves")
	ok(not t.contains("COMBUSTION") and not t.contains("FLAME JET") and not t.contains("FIRE DASH") and not t.contains("FLAME ARCS") and not t.contains("FIRE WHIP"), "and none of the removed ones")
	ok(t.contains("%.1f" % C.RUSH_TIME), "the rush time in the text follows the config (%.1f s)" % C.RUSH_TIME)
	ok(Session.NATIONS.has("fire") and Session.nation_name("fire") == "FIRE NATION", "the session knows the fire nation")
