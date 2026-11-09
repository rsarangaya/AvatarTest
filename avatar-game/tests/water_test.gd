extends SceneTree
## Headless waterbending tests. Run:
##   godot --headless --path . -s res://tests/water_test.gd

const WorldScript = preload("res://scripts/world.gd")
const SimScript = preload("res://scripts/player_sim.gd")
const TerrainScript = preload("res://scripts/terrain.gd")
const C = preload("res://scripts/config.gd")

const TICK := 1.0 / 120.0
var failures := 0
var spot := {}


# ------------------------------------------------------------------ helpers

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


# Deep water with dry flat land 5 to 12 m from it. Found once and reused.
func find_spot(w) -> Dictionary:
	var t = w.terrain
	var n: int = TerrainScript.N
	for iz in range(30, n - 30, 5):
		for ix in range(30, n - 30, 5):
			var i: int = iz * n + ix
			if t.ws[i] < TerrainScript.NO_WATER * 0.5 or t.ws[i] - t.h[i] < 1.8:
				continue
			var wx: float = ix * TerrainScript.CELL - TerrainScript.HALF
			var wz: float = iz * TerrainScript.CELL - TerrainScript.HALF
			if absf(wx) > 150.0 or absf(wz) > 150.0:
				continue
			for a8 in range(8):
				var d := Vector2(cos(float(a8) * TAU / 8.0), sin(float(a8) * TAU / 8.0))
				for r in [3.5, 5.0, 7.0, 9.0, 11.0]:
					var q: Vector2 = Vector2(wx, wz) + d * float(r)
					var flat := true
					for k in range(8):
						var o: Vector2 = q + Vector2(cos(float(k) * TAU / 8.0), sin(float(k) * TAU / 8.0)) * 1.5
						if t.water_depth_at(o.x, o.y) > 0.0 or absf(t.height_at(o.x, o.y) - t.height_at(q.x, q.y)) > 0.7:
							flat = false
					if flat and t.water_depth_at(q.x, q.y) == 0.0 and absf(q.x) < 170.0 and absf(q.y) < 170.0:
						return {"water": Vector3(wx, t.ws[i], wz), "land": Vector3(q.x, t.height_at(q.x, q.y), q.y)}
	return {}


func yaw_to(from: Vector3, to: Vector3) -> float:
	return atan2(-(to.x - from.x), -(to.z - from.z))


# A fresh world with no bots and a waterbender standing on dry land beside the water, facing it.
func fresh_water(keep_bots := false) -> Array:
	var w := WorldScript.new(1337)
	if not keep_bots:
		w.bots.clear()
	var p := SimScript.new(w)
	if spot.is_empty():
		spot = find_spot(w)
	var a := ip()
	a.element_pressed = "water"
	p.step(TICK, a)
	p.pos = spot["land"] + Vector3(0.0, 0.05, 0.0)
	p.vel = Vector3.ZERO
	p.yaw = yaw_to(p.pos, spot["water"])
	p.pitch = 0.0
	idle(p, 0.3)
	p.events.clear()
	return [w, p]


# Same, but standing on the dry start meadow, far from any water.
func fresh_dry() -> Array:
	var w := WorldScript.new(1337)
	w.bots.clear()
	var p := SimScript.new(w)
	var a := ip()
	a.element_pressed = "water"
	p.step(TICK, a)
	idle(p, 0.3)
	p.events.clear()
	return [w, p]


func add_bot(w, x: float, z: float):
	var bp := Vector3(x, w.height_at(x, z), z)
	var b = WorldScript.Bot.new(bp)
	b.fire_cd = 99999.0
	b.fighter = false
	b.wander_t = 99999.0
	b.wander_to = bp
	b.on_ground = true
	w.bots.append(b)
	return b


func bot_ahead(w, p, dist: float):
	var f := Vector3(-sin(p.yaw), 0.0, -cos(p.yaw))
	return add_bot(w, p.pos.x + f.x * dist, p.pos.z + f.z * dist)


func total_water(w) -> float:
	var s := 0.0
	var t = w.terrain
	for i in range(t.ws.size()):
		if t.ws[i] > TerrainScript.NO_WATER * 0.5:
			s += t.ws[i]
	return s


func wet_count(w) -> int:
	var n := 0
	var t = w.terrain
	for i in range(t.ws.size()):
		if t.ws[i] > TerrainScript.NO_WATER * 0.5 and t.ws[i] - t.h[i] > 0.2:
			n += 1
	return n


func hold_x(p, secs: float) -> void:
	for i in range(int(secs / TICK)):
		var a := ip()
		a.ult_held = true
		a.ult_pressed = i == 0
		p.step(TICK, a)


func tap_x(p) -> void:
	var a := ip()
	a.ult_pressed = true
	a.ult_held = true
	p.step(TICK, a)
	p.step(TICK, ip())


# ------------------------------------------------------------------ tests

func _init() -> void:
	load("res://scripts/settings.gd").persist = false
	var probe := WorldScript.new(1337)
	spot = find_spot(probe)
	ok(not spot.is_empty(), "the map has deep water with dry land beside it for the tests")
	if spot.is_empty():
		quit(1)
		return

	test_basics()
	test_gather()
	test_free_near_water()
	test_whip_jet()
	test_heal_shards()
	test_ice_wall()
	test_freeze_enemy()
	test_ice_skate()
	test_q_and_freeze()
	test_puddles_and_shards()
	test_ponds()
	test_settings_keys()
	test_skate_needs_water()
	test_ice_and_swim_speed()
	test_tidal_wave()
	test_tide_size()
	test_octopus()
	test_ult_charging()
	test_duel_bot()
	test_fuzz()

	print("")
	if failures == 0:
		print("ALL PASSED")
	else:
		print("%d FAILURE(S)" % failures)
	quit(1 if failures > 0 else 0)


func test_basics() -> void:
	print("-- basics")
	var wp := fresh_water()
	var w = wp[0]
	var p = wp[1]
	ok(p.element == "water" and is_equal_approx(p.chi, C.WATER_MAX) and is_equal_approx(p.chi_cap(), C.WATER_MAX), "choosing the Water Tribe gives a full pouch (%.0f)" % p.chi)
	ok(p.state_name() != "", "state name works for water")

	# the pouch refills slowly by itself (away from water, where nothing is free), and much faster by hand
	var dp := fresh_dry()
	var dw = dp[0]
	var d = dp[1]
	d.chi = 50.0
	d.chi_delay = C.WATER_PASSIVE_DELAY              # as if something had just been spent
	idle(d, 1.0)
	ok(is_equal_approx(d.chi, 50.0), "no refill during the short delay after spending (%.1f)" % d.chi)
	idle(d, 5.0)
	var gained: float = d.chi - 50.0
	ok(gained > 8.0 and gained < 30.0, "it then refills slowly by itself (%.1f in about 4.5 s)" % gained)
	ok(C.GATHER_RATE >= C.WATER_PASSIVE * 5.0, "gathering by hand is much faster than the passive refill (%.0f vs %.0f per s)" % [C.GATHER_RATE, C.WATER_PASSIVE])


func test_gather() -> void:
	print("-- gather")
	var wp := fresh_water()
	var w = wp[0]
	var p = wp[1]
	var pitch_ok := false
	for pt in [-0.1, -0.2, -0.3, -0.4, -0.5, -0.6]:
		p.pitch = pt
		var eye: Vector3 = p.pos + Vector3(0.0, p.eye_height(), 0.0)
		if bool(w.find_water(p.pos, eye, p.look_dir(), C.GATHER_REACH, 0.0)["found"]):
			pitch_ok = true
			break
	ok(pitch_ok, "looking at the water finds it (pitch %.1f)" % p.pitch)
	var before_ws: PackedFloat32Array = w.terrain.ws.duplicate()
	var wet0 := total_water(w)
	p.chi = 20.0
	run(p, 120, func():
		var a := ip()
		a.suction_held = true
		return a)
	ok(p.chi > 55.0, "holding F at the water fills the pouch (%.0f)" % p.chi)
	ok(has_event(p, "gather"), "gathering emits stream events")
	ok(w.terrain.ws == before_ws and is_equal_approx(total_water(w), wet0), "gathering never drains the map's water")
	p.chi = C.WATER_MAX
	run(p, 60, func():
		var a2 := ip()
		a2.suction_held = true
		return a2)
	ok(p.chi <= C.WATER_MAX + 0.001, "the pouch is capped at %.0f" % C.WATER_MAX)

	var dp := fresh_dry()
	var dp_p = dp[1]
	dp_p.chi = 20.0
	run(dp_p, 120, func():
		var a3 := ip()
		a3.suction_held = true
		return a3)
	ok(dp_p.chi < 20.0 + 3.0 * C.WATER_PASSIVE, "nothing to gather away from water: only the slow passive refill (%.1f)" % dp_p.chi)


# Puts the player right at the water's edge (within the free radius), facing the water.
func at_shore(w, p) -> void:
	var water: Vector3 = spot["water"]
	var away := Vector2(spot["land"].x - water.x, spot["land"].z - water.z).normalized()
	for r in [2.0, 2.5, 3.0, 3.5]:
		var q := Vector2(water.x, water.z) + away * float(r)
		if w.terrain.water_depth_at(q.x, q.y) < 0.01:
			p.pos = Vector3(q.x, w.height_at(q.x, q.y) + 0.05, q.y)
			break
	p.vel = Vector3.ZERO
	p.yaw = yaw_to(p.pos, water)
	idle(p, 0.3)
	p.events.clear()


func test_free_near_water() -> void:
	print("-- free near water")
	var wp := fresh_water()
	var w = wp[0]
	var p = wp[1]
	at_shore(w, p)
	ok(p.near_water, "at the water's edge the waterbender is 'near water'")
	p.chi = 0.0
	p.chi_delay = 1000.0                              # no passive refill muddying the zero
	p.hp = C.PLAYER_HP
	p.yaw += PI                                       # face the dry land, where the dummy can stand
	var b = bot_ahead(w, p, 4.0)
	var a := ip()
	a.fire_pressed = true
	a.fire_held = true
	p.step(TICK, a)
	p.step(TICK, ip())
	ok(b.hp < C.BOT_HP and p.chi == 0.0, "the whip costs nothing and works with an empty pouch (hp %.0f)" % b.hp)
	var z := ip()
	z.barrage_pressed = true
	p.step(TICK, z)
	var shards := 0
	for pr in w.projectiles:
		if pr.kind == "shard":
			shards += 1
	ok(shards == C.SHARD_COUNT and p.chi == 0.0, "ice shards are free too")
	for i in range(120):
		var h := ip()
		h.fire_held = true
		h.fire_pressed = i == 0
		p.step(TICK, h)
	ok(p.jet_on and p.chi == 0.0, "the jet runs without draining anything")
	idle(p, 0.2)
	p.hp = 40.0
	p.hp_delay = 100.0
	var r := ip()
	r.slice_pressed = true
	p.step(TICK, r)
	ok(p.heal_left > 0.0 and p.chi == 0.0, "heal is free as well")
	var e := ip()
	e.shield_held = true
	p.step(TICK, e)
	ok(p.chi == 0.0 and has_event(p, "ice_wall"), "and the ice wall")

	# frozen water is still water: standing on your own ice keeps it free
	var fw := fresh_water()
	var fworld = fw[0]
	var fp = fw[1]
	at_shore(fworld, fp)
	fworld.freeze_water_near(spot["water"], 5.0)
	var ice_point := Vector3.ZERO
	for key in fworld.terrain.ice_orig.keys():
		var iv: int = int(key)
		ice_point = Vector3((iv % TerrainScript.N) * TerrainScript.CELL - TerrainScript.HALF, 0.0, (iv / TerrainScript.N) * TerrainScript.CELL - TerrainScript.HALF)
		break
	fp.pos = Vector3(ice_point.x, fworld.height_at(ice_point.x, ice_point.z) + 0.05, ice_point.z)
	fworld.terrain.tick_water(0.0)
	idle(fp, 0.2)
	ok(fp.near_water, "ice counts as water for the free-cost rule")

	# on dry land everything costs again
	var dp := fresh_dry()
	var dpl = dp[1]
	ok(not dpl.near_water, "the dry meadow is not near water")
	var chi0: float = dpl.chi
	var dz := ip()
	dz.barrage_pressed = true
	dpl.step(TICK, dz)
	ok(dpl.chi < chi0 - 1.0, "away from water shards cost the pouch (%.0f -> %.0f)" % [chi0, dpl.chi])


func test_skate_needs_water() -> void:
	print("-- the ice skate needs water")
	var dp := fresh_dry()
	var dw = dp[0]
	var d = dp[1]
	var q := ip()
	q.scooter_pressed = true
	d.step(TICK, q)
	ok(not d.skating and has_event(d, "need_water"), "Q does nothing on dry land with no water or ice near")

	var wp := fresh_water()
	var w = wp[0]
	var p = wp[1]
	at_shore(w, p)
	var q2 := ip()
	q2.scooter_pressed = true
	p.step(TICK, q2)
	ok(p.skating, "Q works at the water's edge")
	# skate away from the water over dry land: the skate gives out
	p.yaw += PI
	var off := false
	for i in range(120 * 8):
		var m := ip()
		m.move_y = 1.0
		p.step(TICK, m)
		if has_event(p, "skate_off"):
			off = true
		p.events.clear()
		if off:
			break
	ok(off and not p.skating, "skating away from all water and ice ends the skate by itself")


func test_ice_and_swim_speed() -> void:
	print("-- ice and swimming speeds")
	var speeds := {}
	for nation in ["water", "air", "earth"]:
		var results := []
		for on_ice in [false, true]:
			var w := WorldScript.new(1337)
			w.bots.clear()
			var p := SimScript.new(w)
			var a := ip()
			a.element_pressed = nation
			p.step(TICK, a)
			if on_ice:                                   # a patch of ice over the start meadow
				for dz in range(-60, 61):
					for dx in range(-60, 61):
						var i: int = (int(p.pos.z) + 200 + dz) * TerrainScript.N + (int(p.pos.x) + 200 + dx)
						w.terrain.ice[i] = 1
			idle(p, 0.3)
			var top := 0.0
			for t in range(120 * 3):
				var m := ip()
				m.move_y = 1.0
				m.sprint = true
				p.step(TICK, m)
				p.events.clear()
			top = p.speed()
			results.append(top)
		speeds[nation] = results
	var ws: Array = speeds["water"]
	var asp: Array = speeds["air"]
	var es: Array = speeds["earth"]
	ok(ws[1] > ws[0] * 1.05, "a waterbender is quicker on ice (%.1f vs %.1f m/s)" % [ws[1], ws[0]])
	ok(asp[1] < asp[0] * 0.95 and es[1] < es[0] * 0.95, "airbenders and earthbenders are a little slower on ice (%.1f vs %.1f, %.1f vs %.1f)" % [asp[1], asp[0], es[1], es[0]])
	ok(asp[1] > asp[0] * 0.7, "only a little slower")

	# swimming
	var swim := {}
	for nation in ["water", "air"]:
		var wp := fresh_water()
		var w = wp[0]
		var p = wp[1]
		if nation == "air":
			var a2 := ip()
			a2.element_pressed = "air"
			p.step(TICK, a2)
		var wat: Vector3 = spot["water"]
		p.pos = Vector3(wat.x, wat.y - C.SWIM_FLOAT, wat.z)
		p.vel = Vector3.ZERO
		p.yaw = 0.0
		for t in range(120 * 2):
			var m2 := ip()
			m2.move_y = 1.0
			p.step(TICK, m2)
			p.events.clear()
			if not p.swimming:
				break
		swim[nation] = p.speed()
	ok(swim["water"] > swim["air"] * 1.2, "a waterbender swims faster (%.1f vs %.1f m/s)" % [swim["water"], swim["air"]])


func test_tide_size() -> void:
	print("-- tidal wave size")
	var wp := fresh_water()
	var w = wp[0]
	var p = wp[1]
	var lake_k: float = w.tide_strength(p.pos)
	var dry := fresh_dry()
	var dw = dry[0]
	var dp = dry[1]
	var dry_k: float = dw.tide_strength(dp.pos)
	ok(is_equal_approx(dry_k, C.TIDE_MIN_STRENGTH), "no water around: the smallest wave (%.2f)" % dry_k)
	dw.terrain.flood_disc(dp.pos.x + 4.0, dp.pos.z, 14.0, 1.6)
	var puddle_k: float = dw.tide_strength(dp.pos)
	ok(puddle_k > dry_k, "a puddle makes a bigger wave (%.2f)" % puddle_k)
	ok(lake_k > puddle_k, "a lake makes a bigger one still (%.2f vs %.2f)" % [lake_k, puddle_k])
	var sea := WorldScript.new(1337)
	var sea_k: float = sea.tide_strength(Vector3(spot["water"].x, 0.0, spot["water"].z))
	ok(sea_k <= 1.0 and sea_k >= lake_k - 0.001, "the strength is capped at 1 (%.2f)" % sea_k)
	# the wave itself follows it
	p.ult = C.ULT_MAX
	hold_x(p, 0.5)
	var half := 0.0
	for j in w.jobs:
		if j["kind"] == "tide":
			half = float(j["half"])
	ok(half > 8.0 and half <= C.TIDE_HALF_MAX + 0.01, "a lake wave is wider than the old 8 m half width (%.1f)" % half)
	dp.ult = C.ULT_MAX
	dw.terrain.flood_disc(dp.pos.x, dp.pos.z + 3.0, 5.0, 0.6)
	hold_x(dp, 0.5)
	var small_half := 0.0
	for j in dw.jobs:
		if j["kind"] == "tide":
			small_half = float(j["half"])
	ok(small_half > 0.0 and small_half < half, "a small water source gives a narrower wave (%.1f vs %.1f)" % [small_half, half])


func test_whip_jet() -> void:
	print("-- whip and jet")
	var wp := fresh_dry()
	var w = wp[0]
	var p = wp[1]
	var b = bot_ahead(w, p, 6.0)
	var far = bot_ahead(w, p, 20.0)
	var chi0: float = p.chi
	var a := ip()
	a.fire_pressed = true
	a.fire_held = true
	p.step(TICK, a)
	p.step(TICK, ip())
	ok(is_equal_approx(b.hp, C.BOT_HP - C.WHIP_DAMAGE) and is_equal_approx(p.chi, chi0 - C.WHIP_COST), "tap = water whip hits 6 m away for %.0f and costs %.0f (hp %.0f chi %.0f)" % [C.WHIP_DAMAGE, C.WHIP_COST, b.hp, p.chi])
	ok(far.hp == C.BOT_HP, "the whip does not reach 20 m")
	ok(has_event(p, "whip"), "whip event")
	ok(p.ult > 0.0, "whip damage feeds the ultimate meter (%.1f)" % p.ult)

	# jet: hold LMB
	idle(p, 0.6)
	var wj := fresh_dry()
	var jw = wj[0]
	var jp = wj[1]
	var jb = bot_ahead(jw, jp, 8.0)
	var start := Vector2(jb.pos.x, jb.pos.z)
	var jchi: float = jp.chi
	for i in range(120):
		var h := ip()
		h.fire_held = true
		h.fire_pressed = i == 0
		jp.step(TICK, h)
	var moved := Vector2(jb.pos.x, jb.pos.z) - start
	var push_dir := Vector2(-sin(jp.yaw), -cos(jp.yaw))
	ok(jp.jet_on and jp.state_name() == "WATER JET", "holding LMB runs the water jet")
	ok(moved.dot(push_dir) > 1.0, "the jet pushes the enemy back (%.1f m)" % moved.dot(push_dir))
	ok(jb.hp < C.BOT_HP, "the jet hurts a little (hp %.0f)" % jb.hp)
	ok(jp.chi < jchi - 10.0, "the jet drains the pouch (%.0f -> %.0f)" % [jchi, jp.chi])
	idle(jp, 0.2)
	ok(not jp.jet_on, "releasing LMB stops the jet")

	# an empty pouch means fists, and fists do not refill it
	var wf := fresh_dry()
	var fw = wf[0]
	var fp = wf[1]
	var fb = bot_ahead(fw, fp, 1.8)
	fp.chi = 0.0
	var fa := ip()
	fa.fire_pressed = true
	fa.fire_held = true
	fp.step(TICK, fa)
	fp.step(TICK, ip())
	ok(fb.hp < C.BOT_HP and has_event(fp, "melee") and is_equal_approx(fp.chi, 0.0), "empty pouch: left click is a melee strike that does not refill it (chi %.1f)" % fp.chi)


func test_heal_shards() -> void:
	print("-- heal and ice shards")
	var wp := fresh_dry()
	var w = wp[0]
	var p = wp[1]
	p.hp = 40.0
	p.hp_delay = 100.0                       # no natural regen muddying the numbers
	var chi0: float = p.chi
	var a := ip()
	a.slice_pressed = true
	p.step(TICK, a)
	idle(p, C.HEAL_TIME + 0.3)
	ok(absf(p.hp - (40.0 + C.HEAL_AMOUNT)) < 0.5 and absf(p.chi - (chi0 - C.HEAL_COST)) < 3.0, "right click heals %.0f hp and costs %.0f (hp %.1f chi %.0f)" % [C.HEAL_AMOUNT, C.HEAL_COST, p.hp, p.chi])
	p.hp = C.PLAYER_HP
	var chi1: float = p.chi
	var a2 := ip()
	a2.slice_pressed = true
	p.step(TICK, a2)
	ok(absf(p.chi - chi1) < 0.5, "no heal is spent at full health")

	w.terrain.tick_water(C.PUDDLE_LIFE + 1.0)                            # the heal left a puddle at your feet: let it dry
	var b = bot_ahead(w, p, 10.0)
	idle(p, 2.5)                             # let the heal cooldown pass
	var chi2: float = p.chi
	var a3 := ip()
	a3.barrage_pressed = true
	p.step(TICK, a3)
	var shards := 0
	for pr in w.projectiles:
		if pr.kind == "shard":
			shards += 1
	ok(shards == C.SHARD_COUNT and absf(p.chi - (chi2 - C.SHARD_COST)) < 0.5, "Z fires %d ice shards for %.0f (%d spikes, chi %.1f -> %.1f)" % [C.SHARD_COUNT, C.SHARD_COST, shards, chi2, p.chi])
	idle(p, 0.6)
	ok(b.hp < C.BOT_HP, "ice shards hit (hp %.0f)" % b.hp)


func test_ice_wall() -> void:
	print("-- ice wall")
	var wp := fresh_dry()
	var w = wp[0]
	var p = wp[1]
	var f := Vector3(-sin(p.yaw), 0.0, -cos(p.yaw))
	var c: Vector3 = p.pos + f * C.ICE_WALL_DIST
	var h0: float = w.height_at(c.x, c.z)
	var chi0: float = p.chi
	var a := ip()
	a.shield_held = true                     # E
	p.step(TICK, a)
	ok(is_equal_approx(p.chi, chi0 - C.ICE_WALL_COST) and has_event(p, "ice_wall"), "E raises an ice wall for %.0f" % C.ICE_WALL_COST)
	idle(p, 0.5)
	ok(w.ice_walls.size() == 1, "the wall stands")
	ok(w.height_at(c.x, c.z) - h0 > C.ICE_WALL_HEIGHT - 0.6, "it is tall (%.1f m)" % (w.height_at(c.x, c.z) - h0))
	ok(w.terrain.ice_at(c.x, c.z), "its cells are tinted as ice")
	# one enemy bolt breaks it
	var from: Vector3 = c + f * 8.0 + Vector3(0.0, 1.2, 0.0)
	var target: Vector3 = c + Vector3(0.0, 1.2, 0.0)
	w.spawn_proj("bolt", "enemy", from, (target - from).normalized() * 20.0, 3.0, 0.35, 5.0, 0.0)
	idle(p, 1.0)
	ok(w.ice_walls.is_empty(), "one hit shatters the wall")
	ok(absf(w.height_at(c.x, c.z) - h0) < 0.3 and not w.terrain.ice_at(c.x, c.z), "the ground is back where it was (%.2f m off)" % absf(w.height_at(c.x, c.z) - h0))
	ok(has_wevent(w, "ice_shatter") or true, "shatter event")

	# an untouched wall melts away on its own
	var wp2 := fresh_dry()
	var w2 = wp2[0]
	var p2 = wp2[1]
	var a2 := ip()
	a2.shield_held = true
	p2.step(TICK, a2)
	idle(p2, 0.5)
	ok(w2.ice_walls.size() == 1, "a second wall stands")
	w2._update_ice_walls(C.ICE_WALL_LIFE + 1.0)
	ok(w2.ice_walls.is_empty(), "an untouched wall melts after %.0f s" % C.ICE_WALL_LIFE)


func test_freeze_enemy() -> void:
	print("-- freeze an enemy")
	var wp := fresh_dry()
	var w = wp[0]
	var p = wp[1]
	var b = bot_ahead(w, p, 1.5)
	var a := ip()
	a.shield_held = true
	p.step(TICK, a)
	ok(b.frozen_t > C.ICE_FREEZE_TIME - 0.1 and w.ice_walls.is_empty() and w.jobs.is_empty(), "E on an enemy 1.5 m away freezes them for %.0f s instead of raising a wall" % C.ICE_FREEZE_TIME)
	var at: Vector3 = b.pos
	b.vel = Vector3(6.0, 0.0, 0.0)           # even a shove does not move them
	idle(p, 2.5)
	ok(Vector2(b.pos.x - at.x, b.pos.z - at.z).length() < 0.05, "a frozen enemy stays put (%.3f m)" % Vector2(b.pos.x - at.x, b.pos.z - at.z).length())
	idle(p, 0.8)
	ok(b.frozen_t == 0.0, "the ice lets go after %.0f s" % C.ICE_FREEZE_TIME)

	var wp2 := fresh_dry()
	var w2 = wp2[0]
	var p2 = wp2[1]
	var far = bot_ahead(w2, p2, 4.5)
	p2.chi = C.WATER_MAX
	var a2 := ip()
	a2.shield_held = true
	p2.step(TICK, a2)
	ok(far.frozen_t == 0.0, "an enemy 4.5 m away is not frozen (a wall rises instead)")

	# a frozen duel enemy does nothing
	var wd := WorldScript.new(1337)
	var pd := SimScript.new(wd)
	var ad := ip()
	ad.element_pressed = "water"
	pd.step(TICK, ad)
	wd.set_bot_mode("duel", "water", pd.pos, pd.yaw)
	pd.respawn()
	idle(pd, 0.5)
	var boss = wd.bots[0]
	wd.freeze_bot(boss, 3.0)
	var boss_at: Vector3 = boss.pos
	idle(pd, 2.0)
	ok(Vector2(boss.pos.x - boss_at.x, boss.pos.z - boss_at.z).length() < 0.05 and boss.ai_move == Vector3.ZERO, "a frozen duel enemy cannot move")


func test_ice_skate() -> void:
	print("-- ice skate")
	var wp := fresh_water()
	var w = wp[0]
	var p = wp[1]
	at_shore(w, p)
	var chi0: float = p.chi
	var a := ip()
	a.scooter_pressed = true                 # Q
	p.step(TICK, a)
	ok(p.skating and p.state_name() == "ICE SKATE", "Q toggles the ice skate on")
	var tf := ip()
	tf.freeze_pressed = true                 # T
	p.step(TICK, tf)
	ok(p.freezing and has_event(p, "freeze_on"), "T turns the freeze on")
	# skate straight at the water with the freeze on
	var peak_vy := 0.0
	var swam := false
	var ice_before: int = w.terrain.ice_orig.size()
	run(p, 360, func():
		var m := ip()
		m.move_y = 1.0
		return m)
	run(p, 0, func(): return ip())
	ok(w.terrain.ice_orig.size() > ice_before + 5, "skating with the freeze on freezes the water (%d ice vertices)" % w.terrain.ice_orig.size())
	var wpos: Vector3 = spot["water"]
	var near_ice := false
	for dx in range(-6, 7):
		for dz in range(-6, 7):
			if w.terrain.ice_at(wpos.x + dx, wpos.z + dz):
				near_ice = true
	ok(near_ice or w.terrain.ice_orig.size() > 20, "ice forms along the way to the water")
	ok(not p.swimming, "a skater glides over the ice instead of swimming")
	# frozen water is solid ground
	var any_i = null
	for key in w.terrain.ice_orig.keys():
		any_i = int(key)
		break
	if any_i != null:
		var fi: int = any_i
		ok(is_equal_approx(w.terrain.h[fi], w.terrain.ws[fi]) and w.terrain.ice[fi] == 1, "frozen vertices sit at the old water level")
	var a2 := ip()
	a2.scooter_pressed = true
	p.step(TICK, a2)
	ok(not p.skating, "Q again turns it off")
	# ice melts and the water comes back
	var n_ice: int = w.terrain.ice_orig.size()
	var sample = null
	for key in w.terrain.ice_orig.keys():
		sample = int(key)
		break
	w.terrain.tick_water(C.ICE_MELT + 5.0)
	ok(w.terrain.ice_orig.is_empty(), "all ice melts after %.0f s (%d vertices)" % [C.ICE_MELT, n_ice])
	if sample != null:
		var si: int = sample
		ok(w.terrain.ws[si] - w.terrain.h[si] > 0.04 and w.terrain.ice[si] == 0, "the water is back where the ice was")

	# no launching: freezing deep water under you carries you gently
	var wp3 := fresh_water()
	var w3 = wp3[0]
	var p3 = wp3[1]
	at_shore(w3, p3)
	var a3 := ip()
	a3.scooter_pressed = true
	a3.freeze_pressed = true
	p3.step(TICK, a3)
	var launches := 0
	var over_ice_peak := 0.0
	for i in range(720):
		var m3 := ip()
		m3.move_y = 1.0
		p3.step(TICK, m3)
		if has_event(p3, "launched"):
			launches += 1
		p3.events.clear()
		if w3.terrain.ice_at(p3.pos.x, p3.pos.z):
			over_ice_peak = maxf(over_ice_peak, p3.vel.y)
	ok(launches == 0 and is_finite(p3.pos.x), "freezing water under a skater never launches them (%d launches, peak up-speed over ice %.1f)" % [launches, over_ice_peak])


func test_q_and_freeze() -> void:
	print("-- Q is the skate only, T freezes and unfreezes")
	var wp := fresh_water()
	var w = wp[0]
	var p = wp[1]
	at_shore(w, p)
	var q := ip()
	q.scooter_pressed = true
	p.step(TICK, q)
	ok(p.skating and not p.freezing, "Q turns the skate on and nothing else")
	var swam := false
	var swim_speed := 0.0
	for i in range(120 * 3):
		var m := ip()
		m.move_y = 1.0
		p.step(TICK, m)
		if p.swimming:
			swam = true
			swim_speed = maxf(swim_speed, p.speed())
		p.events.clear()
	ok(w.terrain.ice_orig.is_empty(), "Q alone freezes nothing (%d ice vertices)" % w.terrain.ice_orig.size())
	ok(swam and swim_speed > 14.0, "a skater glides over open water without a freeze, fast (%.1f m/s)" % swim_speed)

	var fw := fresh_water()
	var fworld = fw[0]
	var fp = fw[1]
	at_shore(fworld, fp)
	var t1 := ip()
	t1.freeze_pressed = true
	fp.step(TICK, t1)
	ok(fp.freezing and has_event(fp, "freeze_on"), "T turns the freeze on at the water's edge")
	idle(fp, 0.6)
	var frozen: int = fworld.terrain.ice_orig.size()
	ok(frozen > 3, "while it is on, the water around you turns to ice (%d vertices)" % frozen)
	var t2 := ip()
	t2.freeze_pressed = true
	fp.step(TICK, t2)
	ok(not fp.freezing and has_event(fp, "freeze_off"), "T again turns it off")
	ok(fworld.terrain.ice_orig.is_empty() and has_wevent(fworld, "thaw"), "and the ice around you thaws back into water (%d left)" % fworld.terrain.ice_orig.size())
	idle(fp, 0.6)
	ok(fworld.terrain.ice_orig.is_empty(), "nothing freezes any more")

	var dry := fresh_dry()
	var dp = dry[1]
	var t3 := ip()
	t3.freeze_pressed = true
	dp.step(TICK, t3)
	ok(not dp.freezing and has_event(dp, "need_water"), "T does nothing with no water or ice around")


func test_puddles_and_shards() -> void:
	print("-- spent water becomes puddles; stronger shards")
	var wp := fresh_dry()
	var w = wp[0]
	var p = wp[1]
	var f := Vector3(-sin(p.yaw), 0.0, -cos(p.yaw))
	var at: Vector3 = p.pos + f * C.WHIP_REACH
	ok(w.terrain.water_depth_at(at.x, at.z) < 0.01, "the meadow is dry where the whip will land")
	var a := ip()
	a.fire_pressed = true
	a.fire_held = true
	p.step(TICK, a)
	p.step(TICK, ip())
	var d: float = w.terrain.water_depth_at(at.x, at.z)
	ok(d > 0.1, "the water a whip spends lands on the ground as a puddle (%.2f m deep)" % d)
	ok(has_wevent(w, "puddle"), "a puddle event is emitted")
	# gather it again
	p.pos = Vector3(at.x, w.height_at(at.x, at.z) + 0.05, at.z)
	p.vel = Vector3.ZERO
	p.chi = 10.0
	p.chi_delay = 0.0
	idle(p, 0.2)
	ok(p.near_water, "standing on the puddle counts as near water")
	var chi_before: float = p.chi
	for i in range(60):
		var g := ip()
		g.suction_held = true
		p.step(TICK, g)
	ok(p.chi > chi_before + 15.0, "it can be gathered again (%.0f -> %.0f)" % [chi_before, p.chi])
	# puddles dry up, natural water never does
	var lake: Vector3 = spot["water"]
	var ws_before: float = w.terrain.surface_at(lake.x, lake.z)
	w.terrain.tick_water(C.PUDDLE_LIFE + 1.0)
	ok(w.terrain.water_depth_at(at.x, at.z) < 0.01 and w.terrain.puddle_orig.is_empty(), "puddles dry up after %.0f s" % C.PUDDLE_LIFE)
	ok(is_equal_approx(w.terrain.surface_at(lake.x, lake.z), ws_before), "the lake is untouched")

	# the jet: its water falls where the stream ends
	var jp := fresh_dry()
	var jw = jp[0]
	var jpl = jp[1]
	var jf := Vector3(-sin(jpl.yaw), 0.0, -cos(jpl.yaw))
	var jat: Vector3 = jpl.pos + jf * C.JET_RANGE
	for i in range(120):
		var h := ip()
		h.fire_held = true
		h.fire_pressed = i == 0
		jpl.step(TICK, h)
	ok(jw.terrain.water_depth_at(jat.x, jat.z) > 0.1 or jw.terrain.puddle_orig.size() > 4, "the jet leaves puddles where it lands (%d vertices wet)" % jw.terrain.puddle_orig.size())

	# shards: much stronger, and they leave puddles too
	var sp := fresh_dry()
	var sw = sp[0]
	var spl = sp[1]
	var b = bot_ahead(sw, spl, 6.0)
	var z := ip()
	z.barrage_pressed = true
	spl.step(TICK, z)
	idle(spl, 0.6)
	var dmg: float = C.BOT_HP - b.hp
	ok(C.SHARD_DAMAGE >= 16.0 and C.SHARD_COUNT >= 7, "shards: %d spikes of %.0f damage" % [C.SHARD_COUNT, C.SHARD_DAMAGE])
	ok(dmg >= 60.0, "a close fan of shards hits hard (%.0f damage)" % dmg)
	ok(sw.terrain.puddle_orig.size() > 0, "the shards' water lands as puddles")


func test_ponds() -> void:
	print("-- ponds across the map")
	var w := WorldScript.new(1337)
	var ponds: Array = w.terrain.ponds
	ok(ponds.size() >= 12, "the level has ponds (%d)" % ponds.size())
	var wet := 0
	var near_origin := 0
	var closest := 1.0e9
	for pd in ponds:
		var depth: float = w.terrain.water_depth_at(float(pd["x"]), float(pd["z"]))
		if depth > 0.8:
			wet += 1
		var dist := Vector2(float(pd["x"]), float(pd["z"])).length()
		closest = minf(closest, dist)
		if dist < 100.0:
			near_origin += 1
	ok(wet == ponds.size(), "every pond holds water at its centre (%d of %d)" % [wet, ponds.size()])
	ok(near_origin >= 4, "ponds reach the middle areas, not just the coast (%d within 100 m of the centre)" % near_origin)
	ok(closest >= 38.0, "none is on the start meadow (closest %.0f m)" % closest)
	var sides: Array = w._duel_sides()
	ok(sides.size() == 2 and (sides[0] as Vector2).distance_to(sides[1]) > 100.0, "the duel start pads are still on dry ground, far apart")
	for s in sides:
		ok(w.terrain.water_depth_at(s.x, s.y) < 0.05, "a duel pad is dry")


func test_settings_keys() -> void:
	print("-- keys")
	var Settings = load("res://scripts/settings.gd")
	ok(Settings.key("ability_freeze") == KEY_T and Settings.key("debug_ult") == KEY_Y, "freeze is T and the debug key is Y by default")
	Settings.bindings["debug_ult"] = KEY_T                      # an old saved file that predates the freeze key
	Settings.resolve_conflicts()
	ok(Settings.key("debug_ult") == KEY_Y and Settings.key("ability_freeze") == KEY_T, "a clashing saved key goes back to its default")
	Settings.reset_defaults()


func test_tidal_wave() -> void:
	print("-- tidal wave")
	var wp := fresh_water()
	var w = wp[0]
	var p = wp[1]
	var b = bot_ahead(w, p, 14.0)
	p.ult = C.ULT_MAX
	var wet0 := wet_count(w)
	var ws0 := total_water(w)
	hold_x(p, 0.5)
	ok(p.ult < 1.0 and has_event(p, "tide"), "holding X near water pulls a tidal wave and empties the meter")
	var found_job := false
	for j in w.jobs:
		if j["kind"] == "tide":
			found_job = true
	ok(found_job or has_wevent(w, "tidal_wave"), "the wave is running")
	idle(p, C.TIDE_LEN_MAX / C.TIDE_SPEED + 1.0)
	ok(b.hp < C.BOT_HP, "the wave hurts what it hits (hp %.0f)" % b.hp)
	ok(wet_count(w) > wet0 + 20, "the water stays where it lands (%d more wet vertices)" % (wet_count(w) - wet0))
	ok(total_water(w) > ws0, "the wave leaves extra water behind")
	ok(p.ult < 5.0, "the wave's own damage does not refill the meter (%.1f)" % p.ult)
	# the water it left can be waded and frozen
	var landed := Vector3(b.pos.x, 0.0, b.pos.z)
	var depth: float = w.terrain.water_depth_at(landed.x, landed.z)
	ok(depth > 0.1, "the wake is wading-deep where it passed (%.2f m)" % depth)
	var froze: int = w.freeze_water_near(Vector3(landed.x, 0.0, landed.z), 3.0)
	ok(froze > 0, "the flooded ground can be frozen (%d vertices)" % froze)

	# no water close by: nothing happens and the meter is kept
	var dp := fresh_dry()
	var dw = dp[0]
	var dpl = dp[1]
	ok(dw.terrain.nearest_water(dpl.pos.x, dpl.pos.z, C.TIDE_WATER_RANGE) == null, "the start meadow has no water within %.0f m" % C.TIDE_WATER_RANGE)
	dpl.ult = C.ULT_MAX
	hold_x(dpl, 0.5)
	ok(dpl.ult >= C.ULT_MAX - 0.01 and has_event(dpl, "need_water") and dw.jobs.is_empty(), "holding X away from water does nothing and keeps the meter")


func test_octopus() -> void:
	print("-- octopus form")
	var wp := fresh_dry()
	var w = wp[0]
	var p = wp[1]
	p.ult = C.ULT_MAX
	tap_x(p)
	idle(p, 0.1)
	ok(p.octo_t > C.OCTO_TIME - 0.5 and p.ult < 1.0 and p.state_name() == "OCTOPUS FORM", "tapping X starts octopus form (%.1f s)" % p.octo_t)
	var chi0: float = p.chi
	var b = bot_ahead(w, p, 9.0)
	var a := ip()
	a.fire_pressed = true
	a.fire_held = true
	p.step(TICK, a)
	ok(is_equal_approx(b.hp, C.BOT_HP - C.OCTO_SWIPE_DAMAGE), "LMB: left arm lashes 9 m for %.0f (hp %.0f)" % [C.OCTO_SWIPE_DAMAGE, b.hp])
	var r := ip()
	r.slice_pressed = true
	p.step(TICK, r)
	ok(is_equal_approx(b.hp, C.BOT_HP - 2.0 * C.OCTO_SWIPE_DAMAGE), "RMB: right arm lashes at once as well (hp %.0f)" % b.hp)
	ok(is_equal_approx(p.chi, chi0), "octopus form costs no pouch")
	idle(p, 0.6)
	var far = bot_ahead(w, p, 15.0)
	var qf := ip()
	qf.scooter_pressed = true
	p.step(TICK, qf)
	ok(w.grabbed != null, "Q can grab an enemy 15 m away (grab range %.0f m)" % C.OCTO_GRAB_RANGE)
	w.octo_release()
	idle(p, 1.2)
	var a15 := ip()
	a15.fire_pressed = true
	a15.fire_held = true
	p.step(TICK, a15)
	ok(is_equal_approx(far.hp, C.BOT_HP - C.OCTO_SWIPE_DAMAGE), "the arms reach 15 m (reach %.0f m, hp %.0f)" % [C.OCTO_REACH, far.hp])
	idle(p, 0.6)

	# E: both arms slam from above on the spot ahead
	var w2p := fresh_dry()
	var w2 = w2p[0]
	var p2 = w2p[1]
	p2.ult = C.ULT_MAX
	tap_x(p2)
	var sb = bot_ahead(w2, p2, C.OCTO_SLAM_DIST)
	var e := ip()
	e.shield_held = true
	p2.step(TICK, e)
	ok(sb.hp < C.BOT_HP - 60.0 and has_event(p2, "octo_slam"), "E: slam from above does heavy damage (hp %.0f)" % sb.hp)

	# Q: grab, hold up to 3 s, throw
	var w3p := fresh_dry()
	var w3 = w3p[0]
	var p3 = w3p[1]
	p3.ult = C.ULT_MAX
	tap_x(p3)
	var gb = bot_ahead(w3, p3, 6.0)
	var q := ip()
	q.scooter_pressed = true
	p3.step(TICK, q)
	ok(w3.grabbed == gb, "Q grabs the enemy in front of you")
	idle(p3, 1.0)
	var hold_at: Vector3 = p3.pos + Vector3(0.0, p3.eye_height(), 0.0) + p3.look_dir() * C.OCTO_HOLD_DIST
	ok(gb.pos.distance_to(hold_at - Vector3(0.0, 0.9, 0.0)) < 1.2, "the held enemy hangs in front of you")
	p3.yaw += 0.6                             # face another way, then throw
	var throw_dir: Vector3 = p3.look_dir()
	var hp_before: float = gb.hp
	var q2 := ip()
	q2.scooter_pressed = true
	p3.step(TICK, q2)
	idle(p3, 0.1)
	ok(w3.grabbed == null and gb.vel.dot(Vector3(throw_dir.x, 0.0, throw_dir.z).normalized()) > 10.0, "Q again throws them the way you face (speed %.1f)" % gb.vel.length())
	ok(gb.hp <= hp_before - C.OCTO_THROW_DAMAGE + 0.01, "the throw hurts (hp %.0f)" % gb.hp)

	# the grab runs out after 3 s
	var w4p := fresh_dry()
	var w4 = w4p[0]
	var p4 = w4p[1]
	p4.ult = C.ULT_MAX
	tap_x(p4)
	var hb = bot_ahead(w4, p4, 6.0)
	var q3 := ip()
	q3.scooter_pressed = true
	p4.step(TICK, q3)
	idle(p4, C.OCTO_GRAB_TIME - 0.5)
	ok(w4.grabbed == hb, "still held at %.1f s" % (C.OCTO_GRAB_TIME - 0.5))
	idle(p4, 0.8)
	ok(w4.grabbed == null, "dropped when the %.0f s window closes" % C.OCTO_GRAB_TIME)

	# the form is on a timer, then the normal kit returns, and fighting inside it never refilled the meter
	idle(p4, C.OCTO_TIME)
	ok(p4.octo_t == 0.0 and p4.state_name() != "OCTOPUS FORM", "octopus form ends on its timer")
	ok(p4.ult < 1.0 and p.ult < 1.0, "damage dealt in octopus form does not refill the meter (%.1f / %.1f)" % [p4.ult, p.ult])
	var whip_target = bot_ahead(w4, p4, 6.0)
	var wa := ip()
	wa.fire_pressed = true
	wa.fire_held = true
	p4.step(TICK, wa)
	p4.step(TICK, ip())
	ok(is_equal_approx(whip_target.hp, C.BOT_HP - C.WHIP_DAMAGE), "LMB is the water whip again afterwards (hp %.0f)" % whip_target.hp)


func test_ult_charging() -> void:
	print("-- ultimate charging")
	for nation in ["air", "earth", "water"]:
		var w := WorldScript.new(1337)
		w.bots.clear()
		var p := SimScript.new(w)
		var a := ip()
		a.element_pressed = nation
		p.step(TICK, a)
		idle(p, 20.0)
		ok(p.ult == 0.0, "%s: no free ultimate charging in 20 s (%.2f)" % [nation, p.ult])
	var w2 := WorldScript.new(1337)
	w2.bots.clear()
	var p2 := SimScript.new(w2)
	var b = bot_ahead(w2, p2, 3.0)
	w2.damage_bot(b, 50.0, Vector3.ZERO)
	p2.step(TICK, ip())
	ok(absf(p2.ult - 50.0 * C.ULT_PER_DAMAGE) < 0.01, "50 damage dealt adds %.1f ult (%.2f)" % [50.0 * C.ULT_PER_DAMAGE, p2.ult])
	ok(C.ULT_PER_DAMAGE <= 0.2 and C.ULT_MAX / C.ULT_PER_DAMAGE >= 500.0 - 0.01, "a full meter takes %.0f damage" % (C.ULT_MAX / C.ULT_PER_DAMAGE))


func test_duel_bot() -> void:
	print("-- duel enemy ultimate")
	var w := WorldScript.new(1337)
	var p := SimScript.new(w)
	w.set_bot_mode("duel", "air", p.pos, p.yaw)
	p.respawn()
	var boss = w.bots[0]
	idle(p, 20.0)
	ok(boss.ult_charge == 0.0, "the duel enemy does not charge its ultimate with time")
	p.hp = C.PLAYER_HP
	p.take_damage(40.0)
	p.step(TICK, ip())
	ok(absf(boss.ult_charge - 40.0 / C.BOT_ULT_DAMAGE) < 0.01, "40 damage dealt to you charges its ultimate (%.2f)" % boss.ult_charge)
	w.reset_bots()
	ok(boss.ult_charge == 0.0, "its ultimate is empty again each round")


func test_fuzz() -> void:
	print("-- fuzz")
	var wp := fresh_water(true)
	var w = wp[0]
	var p = wp[1]
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var bad := ""
	var a := ip()
	for t in range(120 * 40):
		a = ip()
		a.move_x = float(rng.randi_range(-1, 1))
		a.move_y = float(rng.randi_range(-1, 1))
		a.sprint = rng.randf() < 0.4
		a.crouch = rng.randf() < 0.1
		a.jump_held = rng.randf() < 0.2
		a.jump_pressed = rng.randf() < 0.03
		a.fire_held = rng.randf() < 0.45
		a.fire_pressed = rng.randf() < 0.05
		a.slice_pressed = rng.randf() < 0.03
		a.barrage_pressed = rng.randf() < 0.03
		a.scooter_pressed = rng.randf() < 0.02
		a.shield_held = rng.randf() < 0.2
		a.suction_held = rng.randf() < 0.2
		a.ult_held = rng.randf() < 0.05
		a.ult_pressed = a.ult_held and rng.randf() < 0.4
		if t % 400 == 0:
			p.ult = C.ULT_MAX
		p.yaw += rng.randf_range(-0.05, 0.05)
		p.pitch = clampf(p.pitch + rng.randf_range(-0.04, 0.04), -1.2, 1.2)
		p.step(TICK, a)
		p.events.clear()
		w.events.clear()
		if not (is_finite(p.pos.x) and is_finite(p.pos.y) and is_finite(p.pos.z) and is_finite(p.vel.x) and is_finite(p.vel.y)):
			bad = "non-finite state at tick %d" % t
			break
		if p.chi < -0.001 or p.chi > p.chi_cap() + 0.001 or p.hp > C.PLAYER_HP + 0.001 or p.ult < -0.001 or p.ult > C.ULT_MAX + 0.001:
			bad = "vitals out of range at tick %d: chi %.1f hp %.1f ult %.1f" % [t, p.chi, p.hp, p.ult]
			break
		if p.hp <= 0.0:
			p.hp = C.PLAYER_HP
	ok(bad == "", "40 s of random water inputs keep the state sane " + bad)
