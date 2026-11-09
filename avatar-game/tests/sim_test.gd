extends SceneTree
## Headless physics + combat tests. Run:
##   godot --headless --path . -s res://tests/sim_test.gd

const WorldScript = preload("res://scripts/world.gd")
const SimScript = preload("res://scripts/player_sim.gd")
const C = preload("res://scripts/config.gd")

const TICK := 1.0 / 120.0
var failures := 0


# ------------------------------------------------------------------ helpers

func ok(cond: bool, msg: String) -> void:
	print(("PASS " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func inp(move_x := 0.0, move_y := 0.0, sprint := false, crouch := false, jump_held := false, jump_pressed := false) -> SimScript.InputState:
	var i := SimScript.InputState.new()
	i.move_x = move_x
	i.move_y = move_y
	i.sprint = sprint
	i.crouch = crouch
	i.jump_held = jump_held
	i.jump_pressed = jump_pressed
	return i


func ip() -> SimScript.InputState:
	return SimScript.InputState.new()


# Fresh world + player standing on the flat start zone. Bots are removed unless asked for,
# so they can't wander into or shoot at tests that are about movement.
func fresh(keep_bots := false) -> Array:
	var w := WorldScript.new(1337)
	if not keep_bots:
		w.bots.clear()
	var p := SimScript.new(w)
	for i in range(30):
		p.step(TICK, ip())
	p.chi = C.CHI_MAX        # tests were written against a 100-chi pool
	return [w, p]


# A motionless, peaceful bot standing on the ground at (x, z).
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


func run_ticks(p, n: int, make: Callable) -> void:
	for i in range(n):
		p.step(TICK, make.call())


func finite_v(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)


func finite(p) -> bool:
	return finite_v(p.pos) and finite_v(p.vel)


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


func tap_fire(p) -> void:
	var a := ip()
	a.fire_pressed = true
	a.fire_held = true
	p.step(TICK, a)
	p.step(TICK, ip())


func hold_fire(p, ticks: int) -> void:
	var a := ip()
	a.fire_pressed = true
	a.fire_held = true
	p.step(TICK, a)
	for i in range(ticks - 1):
		var h := ip()
		h.fire_held = true
		p.step(TICK, h)


func press_slice(p) -> void:
	var a := ip()
	a.slice_pressed = true
	p.step(TICK, a)


func press_edge(p, field: String) -> void:
	var a := ip()
	a.set(field, true)
	p.step(TICK, a)


func press_ult(p) -> void:
	var a := ip()
	a.ult_pressed = true
	p.step(TICK, a)


func count_proj(w, kind: String) -> int:
	var n := 0
	for pr in w.projectiles:
		if pr.kind == kind:
			n += 1
	return n


func _initialize() -> void:
	test_core()
	test_movement_bending()
	test_attacks()
	test_melee()
	test_fighters()
	test_bot_modes()
	test_defense()
	test_ultimates()
	test_terrain()
	test_earth()
	test_destruction()
	test_healing()
	test_bots_and_vitals()
	test_fuzz()
	print("")
	print("ALL PASSED" if failures == 0 else "%d FAILURE(S)" % failures)
	quit(1 if failures > 0 else 0)


func test_melee() -> void:
	# with chi, a tap is the bending move; with none it is a melee strike
	var r := fresh()
	var w = r[0]
	var p = r[1]
	var b = add_bot(w, p.pos.x, p.pos.z - 2.0)
	p.chi = 0.0
	tap_fire(p)
	ok(has_event(p, "melee") and count_proj(w, "punch") == 0, "no chi: LMB is a melee strike, not an air punch")
	ok(b.hp < C.BOT_HP and p.chi > 0.0, "the strike hurts the bot and gives chi back (hp %.0f, chi %.1f)" % [b.hp, p.chi])
	# the combo chains and finishes with a bigger hit
	r = fresh(); w = r[0]; p = r[1]
	b = add_bot(w, p.pos.x, p.pos.z - 2.0)
	p.chi = 0.0
	var hp_before: float = b.hp
	var dmg: Array = []
	for k in range(3):
		var hp0: float = b.hp
		tap_fire(p)
		dmg.append(hp0 - b.hp)
		b.stun = 0.0
		run_ticks(p, 36, func(): return ip())
	ok(dmg[2] > dmg[0] + 3.0 and dmg[0] > 0.0, "three-hit combo finishes harder (%.0f, %.0f, %.0f)" % [dmg[0], dmg[1], dmg[2]])
	# right click with no chi is the heavy strike
	r = fresh(); w = r[0]; p = r[1]
	b = add_bot(w, p.pos.x, p.pos.z - 2.5)
	p.chi = 0.0
	press_edge(p, "slice_pressed")
	ok(has_event(p, "melee") and b.hp < C.BOT_HP - 12.0 and b.vel.length() > 5.0, "no chi: RMB is a heavy strike with knockback (hp %.0f)" % b.hp)
	# out of reach is a miss
	r = fresh(); w = r[0]; p = r[1]
	b = add_bot(w, p.pos.x, p.pos.z - 9.0)
	p.chi = 0.0
	tap_fire(p)
	ok(b.hp == C.BOT_HP and has_event(p, "melee"), "a bot out of reach is missed")
	# earth hits harder
	r = fresh(); w = r[0]; p = r[1]
	go_earth(p)
	b = add_bot(w, p.pos.x, p.pos.z - 2.0)
	p.chi = 0.0
	tap_fire(p)
	ok(C.BOT_HP - b.hp >= 9.0, "earth melee hits for %.0f" % (C.BOT_HP - b.hp))
	# with enough chi nothing changes
	r = fresh(); w = r[0]; p = r[1]
	b = add_bot(w, p.pos.x, p.pos.z - 9.0)
	tap_fire(p)
	ok(count_proj(w, "punch") == 1 and not has_event(p, "melee"), "with chi the tap is still an air punch")


func test_fighters() -> void:
	var r := fresh()
	var w = r[0]
	var p = r[1]
	var b = add_bot(w, p.pos.x, p.pos.z - 6.0)
	b.fighter = true
	b.home = b.pos
	var d0: float = b.pos.distance_to(p.pos)
	run_ticks(p, 120, func(): return ip())
	ok(b.pos.distance_to(p.pos) < d0 - 2.0 or p.hp < C.PLAYER_HP, "a fighter bot closes in on a nearby player (%.1f -> %.1f m)" % [d0, b.pos.distance_to(p.pos)])
	run_ticks(p, 360, func(): return ip())
	ok(p.hp < C.PLAYER_HP and has_wevent(w, "bot_swing"), "and strikes with a wind-up (hp %.0f)" % p.hp)
	# a far bot stays put
	r = fresh(); w = r[0]; p = r[1]
	b = add_bot(w, p.pos.x, p.pos.z - 40.0)
	b.fighter = true
	b.home = b.pos
	run_ticks(p, 240, func(): return ip())
	ok(b.pos.distance_to(Vector3(p.pos.x, b.pos.y, p.pos.z - 40.0)) < 8.0, "a distant bot does not leave its post")


func test_bot_modes() -> void:
	var r := fresh(true)
	var w = r[0]
	var p = r[1]
	var n0: int = w.bots.size()
	w.set_bot_mode("benders", "air", p.pos, p.yaw)
	var benders := 0
	for b in w.bots:
		if b.bender:
			benders += 1
	ok(w.bots.size() == n0 and benders == n0, "benders mode keeps the %d bots and makes them all benders" % n0)
	# a grunt bender throws its nation's moves
	w.bots.clear()
	var g = add_bot(w, p.pos.x, p.pos.z - 10.0)
	g.bender = true
	g.fighter = false
	g.nation = "earth"
	g.air_user = false
	g.gcd = 0.1
	run_ticks(p, 600, func(): return ip())
	ok(w.projectiles.size() > 0 or p.hp < C.PLAYER_HP or has_wevent(w, "bot_cast"), "an earth grunt throws rocks at you")
	w.duel_nation = "air"
	w.set_bot_mode("duel", "air", p.pos, p.yaw)
	ok(w.bots.size() == 1 and w.bots[0].nation == "air", "the duel enemy can be chosen: air vs an air player")
	w.duel_nation = "auto"
	w.set_bot_mode("fighters")
	ok(w.bots.size() == n0 and not w.bots[0].bender, "fighters mode restores the plain bots")

	# a duel round ends on a kill and resets cleanly
	r = fresh(true); w = r[0]; p = r[1]
	w.set_bot_mode("duel", "air", p.pos, p.yaw)
	p.respawn()
	w.bots[0].hp = 1.0
	w.damage_bot(w.bots[0], 50.0, Vector3.ZERO, false)
	ok(w.duel_round_over, "killing the duel enemy flags the round as over")
	w.reset_bots()
	ok(not w.duel_round_over and w.bots[0].alive and w.bots[0].hp == w.bots[0].max_hp, "reset brings the duelist back at full health")
	var d0: int = p.deaths
	p.take_damage(9999.0)
	ok(p.deaths == d0 + 1, "dying is counted so a duel can reset")

	# the duelist: one bot, the opposite nation, full kit
	for nation in ["earth", "air"]:
		r = fresh(true); w = r[0]; p = r[1]
		var el: String = "air" if nation == "earth" else "earth"
		if el == "earth":
			go_earth(p)
		w.set_bot_mode("duel", el, p.pos, p.yaw)
		ok(w.bots.size() == 1 and w.bots[0].boss and w.bots[0].nation == nation and w.bots[0].max_hp > 300.0, "duel mode: one %s boss against the %s player" % [nation, el])
		p.respawn()
		var sep: float = Vector2(p.pos.x - w.bots[0].pos.x, p.pos.z - w.bots[0].pos.z).length()
		ok(sep > 200.0, "duel start: the two fighters begin on opposite sides of the map (%.0f m apart)" % sep)
		var fv := Vector3(w.bots[0].pos.x - p.pos.x, 0.0, w.bots[0].pos.z - p.pos.z).normalized()
		ok(absf(Vector3(-sin(p.yaw), 0.0, -cos(p.yaw)).dot(fv) - 1.0) < 0.02, "and the player starts facing the enemy")
		p.respawn()
		# fight on the open meadow, as the original duel test did
		p.pos = w._base_spawn + Vector3(0.0, 0.05, 0.0)
		p.yaw = 0.0
		w.bots[0].pos = w._base_spawn + Vector3(0.0, 0.0, -24.0)
		w.bots[0].pos.y = w.height_at(w.bots[0].pos.x, w.bots[0].pos.z)
		w.bots[0].home = w.bots[0].pos
		var seen := {}
		var hp_min: float = p.hp
		for k in range(120 * 90):
			p.step(TICK, ip())
			for ev in w.events:
				if ev["type"] == "bot_cast":
					seen[ev["kind"]] = true
			w.events.clear()
			hp_min = minf(hp_min, p.hp)
			if p.hp < 40.0:
				p.hp = 100.0
			if not finite(p):
				break
		var boss = w.bots[0]
		print("   ", nation, " duelist used: ", seen.keys(), " cds ", boss.cds.keys().size(), " player hp low ", hp_min)
		ok(finite(p) and hp_min < 95.0, "the %s duelist actually hurts you (lowest hp %.0f)" % [nation, hp_min])
		ok(seen.size() >= 3, "and uses a spread of moves (%d kinds)" % seen.size())


# ------------------------------------------------------------------ core movement

func test_core() -> void:
	var r := fresh()
	var w = r[0]
	var p = r[1]
	ok(p.on_ground and absf(p.pos.y - w.height_at(p.pos.x, p.pos.z)) < 1e-4, "idle grounded on flat")

	r = fresh(); p = r[1]
	run_ticks(p, 360, func(): return inp(0, 1, true))
	ok(absf(p.speed() - 8.5 * C.AIR_SPEED_MULT) < 0.2, "airbender sprint reaches ~%.1f (got %.2f)" % [8.5 * C.AIR_SPEED_MULT, p.speed()])
	r = fresh(); p = r[1]
	run_ticks(p, 240, func(): return inp(0, 1))
	ok(absf(p.speed() - 5.0 * C.AIR_SPEED_MULT) < 0.2, "airbender walk ~%.1f (got %.2f)" % [5.0 * C.AIR_SPEED_MULT, p.speed()])

	r = fresh(); p = r[1]
	p.yaw = PI / 2.0
	run_ticks(p, 240, func(): return inp(0, 1, true))
	var before: float = p.speed()
	p.step(TICK, inp(0, 1, true, true))
	ok(p.sliding, "slide starts")
	ok(p.speed() > before, "slide boosts (%.1f -> %.1f)" % [before, p.speed()])
	var t := 0
	while p.sliding and t < 600:
		p.step(TICK, inp(0, 0, false, true))
		t += 1
	ok(not p.sliding and t > 60 and t < 400, "slide ends naturally after %.2fs" % (t / 120.0))

	r = fresh(); p = r[1]
	p.step(TICK, inp(0, 0, false, false, false, true))
	ok(not p.on_ground, "jump leaves ground")
	var max_y := 0.0
	var n := 0
	while not p.on_ground and n < 600:
		p.step(TICK, inp())
		max_y = maxf(max_y, p.pos.y)
		n += 1
	ok(p.on_ground and max_y > 1.3 and max_y < 2.1, "jump apex %.2f then lands" % max_y)

	r = fresh(); p = r[1]
	p.yaw = PI / 2.0
	run_ticks(p, 240, func(): return inp(0, 1, true))
	p.step(TICK, inp(0, 1, true, true))
	run_ticks(p, 20, func(): return inp(0, 0, false, true))
	var s: float = p.speed()
	p.step(TICK, inp(0, 0, false, true, false, true))
	run_ticks(p, 30, func(): return inp(0, 0, false, true))
	ok(not p.on_ground and p.speed() > s - 0.5, "slide-jump keeps speed %.1f -> %.1f" % [s, p.speed()])

	r = fresh(); p = r[1]
	p.pos.x = 5.0
	p.pos.z = 0.0
	p.yaw = -PI / 2.0
	n = 0
	while n < 700 and p.pos.x < 17.5:
		p.step(TICK, inp(0, 1, true))
		n += 1
	ok(p.on_ground and absf(p.pos.y - 3.15) < 0.4, "climbs stairs to platform, y=%.2f x=%.1f" % [p.pos.y, p.pos.x])

	r = fresh(); p = r[1]
	p.pos.x = 10.0
	p.pos.z = 8.0
	p.yaw = PI
	n = 0
	while p.pos.z < 12.2 and n < 600:
		p.step(TICK, inp(0, 1))
		n += 1
	var mant := false
	var done := false
	p.step(TICK, inp(0, 1, false, false, true, true))
	n = 0
	while n < 600 and not done:
		p.step(TICK, inp(0, 1, false, false, true))
		if not p.mantle.is_empty():
			mant = true
		if mant and p.mantle.is_empty():
			done = true
		n += 1
	ok(mant, "mantle triggered on the 3.2 m earth ridge")
	ok(done and p.on_ground and absf(p.pos.y - 3.2) < 0.3 and p.pos.z > 14.3 and p.pos.z < 17.0,
			"ended on top y=%.2f z=%.2f speed=%.1f" % [p.pos.y, p.pos.z, p.speed()])

	var w2 := WorldScript.new(1337)
	w2.bots.clear()
	p = SimScript.new(w2)
	p.pos = Vector3(52.0, w2.height_at(52.0, -8.0), -8.0)
	p.yaw = -PI / 2.0
	run_ticks(p, 30, func(): return inp())
	run_ticks(p, 150, func(): return inp(0, 1, true))
	var sp0: float = p.speed()
	p.step(TICK, inp(0, 1, false, true))
	var peak: float = p.speed()
	n = 0
	while p.sliding and n < 900:
		p.step(TICK, inp(0, 0, false, true))
		peak = maxf(peak, p.speed())
		n += 1
	print("   hill: sprint %.1f, peak slide %.1f" % [sp0, peak])
	ok(peak > sp0 * 1.15 and finite(p), "downhill slide gains speed")


# ------------------------------------------------------------------ gust / glide / scooter

func test_movement_bending() -> void:
	var r := fresh()
	var p = r[1]
	p.step(TICK, inp(0, 0, false, false, false, true))
	run_ticks(p, 40, func(): return inp())
	var chi_before: float = p.chi
	p.step(TICK, inp(0, 0, false, false, false, true))
	ok(has_event(p, "gust") and p.vel.y >= C.GUST_UP - 0.5, "gust jump fires in mid-air (vy=%.1f)" % p.vel.y)
	ok(absf(chi_before - p.chi - C.GUST_COST) < 0.5, "gust costs %.0f chi" % C.GUST_COST)
	p.events.clear()
	p.step(TICK, inp(0, 0, false, false, false, true))
	ok(not has_event(p, "gust"), "gust has a cooldown")

	r = fresh(); p = r[1]
	p.chi = 5.0
	p.step(TICK, inp(0, 0, false, false, false, true))
	run_ticks(p, 40, func(): return inp())
	p.events.clear()
	p.step(TICK, inp(0, 0, false, false, false, true))
	ok(not has_event(p, "gust"), "gust blocked without chi")

	r = fresh(); p = r[1]
	p.step(TICK, inp(0, 0, false, false, false, true))
	run_ticks(p, 10, func(): return inp())
	p.events.clear()
	p.step(TICK, inp(0, 0, false, false, false, true))
	ok(not has_event(p, "gust"), "second quick press right after jump does not waste a gust")

	r = fresh(); p = r[1]
	p.yaw = PI / 2.0
	var fwd := Vector3(-sin(p.yaw), 0.0, -cos(p.yaw))
	p.step(TICK, inp(0, 1, true, false, false, true))
	run_ticks(p, 40, func(): return inp(0, 1))
	var h0: float = p.speed()
	p.step(TICK, inp(0, 1, false, false, false, true))
	var along: float = p.vel.x * fwd.x + p.vel.z * fwd.z
	ok(p.speed() > h0 - 0.01 and along > 0.0, "gust pushes toward steering (%.1f -> %.1f)" % [h0, p.speed()])

	# gust chain: how high can chi alone take you?
	r = fresh(); p = r[1]
	p.step(TICK, inp(0, 0, false, false, false, true))
	var top := 0.0
	for k in range(160):
		var press := (k % 30 == 29)
		p.step(TICK, inp(0, 0, false, false, false, press))
		top = maxf(top, p.pos.y)
	print("   jump + gust chain tops out at %.1f m (air bomb needs %.0f m; the temple summit is %.1f m)" % [top, C.BOMB_MIN_HEIGHT, r[0].summit.y])

	var fall_time_plain := 0.0
	var fall_time_glide := 0.0
	for mode in [false, true]:
		r = fresh(); p = r[1]
		p.pos.y += 25.0
		p.on_ground = false
		var ticks := 0
		var min_vy := 0.0
		while not p.on_ground and ticks < 3000:
			p.step(TICK, inp(0, 0, false, false, mode))
			min_vy = minf(min_vy, p.vel.y) if ticks > 120 else min_vy
			ticks += 1
		if mode:
			fall_time_glide = ticks / 120.0
			ok(min_vy > -C.GLIDE_FALL - 0.6, "glide clamps fall speed (min vy %.2f)" % min_vy)
		else:
			fall_time_plain = ticks / 120.0
	ok(fall_time_glide > fall_time_plain * 1.8, "glide stays up much longer (%.1fs vs %.1fs)" % [fall_time_glide, fall_time_plain])
	ok(p.chi < C.CHI_MAX, "glide drains chi")

	r = fresh(); p = r[1]
	p.pos.y += 30.0
	p.on_ground = false
	p.vel = Vector3(0, 0, -10.0)
	run_ticks(p, 240, func(): return inp(0, 1, false, false, true))
	ok(p.gliding and p.speed() >= 9.5, "glide keeps momentum (%.1f m/s)" % p.speed())

	r = fresh(); p = r[1]
	var i := inp(0, 1)
	i.scooter_pressed = true
	p.step(TICK, i)
	ok(p.scooter, "scooter toggles on")
	ok(absf(p.eye_height() - C.EYE_STAND) < 0.001, "scooter keeps a standing eye height (bubble is visible below)")
	run_ticks(p, 240, func(): return inp(0, 1))
	ok(p.speed() > 13.5 and p.speed() < 16.5, "scooter cruises ~15 m/s (got %.1f)" % p.speed())
	ok(p.chi < C.CHI_MAX - 15.0, "scooter drains chi (%.0f left)" % p.chi)
	var laps := 0
	while p.scooter and laps < 120 * 30:
		p.yaw += 0.01
		p.step(TICK, inp(0, 1))
		laps += 1
	ok(not p.scooter and p.chi <= 0.5 and laps < 120 * 30, "scooter ends when chi runs out (after %.1fs more)" % (laps / 120.0))
	r = fresh(); p = r[1]
	p.chi = 5.0
	var i2 := inp()
	i2.scooter_pressed = true
	p.step(TICK, i2)
	ok(not p.scooter, "scooter needs minimum chi")

	var w2 := WorldScript.new(1337)
	w2.bots.clear()
	p = SimScript.new(w2)
	p.pos = Vector3(52.0, w2.height_at(52.0, -8.0), -8.0)
	p.yaw = PI / 2.0
	run_ticks(p, 30, func(): return inp())
	var i3 := inp(0, 1)
	i3.scooter_pressed = true
	p.step(TICK, i3)
	var scoot_peak := 0.0
	for k in range(480):
		p.step(TICK, inp(0, 1))
		scoot_peak = maxf(scoot_peak, p.speed())
	print("   scooter downhill peak %.1f" % scoot_peak)
	ok(scoot_peak > 15.5 and scoot_peak <= C.SCOOTER_MAX_SPEED + 0.5 and finite(p), "scooter gains speed downhill, capped")

	r = fresh(); p = r[1]
	p.chi = 20.0
	p.chi_delay = 0.0
	run_ticks(p, 120, func(): return inp())
	ok(p.chi > 40.0, "chi regenerates on ground (%.0f)" % p.chi)


# ------------------------------------------------------------------ left click, right click

func test_attacks() -> void:
	# --- Air Punch (tap)
	var r := fresh()
	var w = r[0]
	var p = r[1]
	var b = add_bot(w, 0.0, -4.0)                 # 8 m in front of the spawn (player faces -z)
	var chi0: float = p.chi
	tap_fire(p)
	ok(has_event(p, "punch") and count_proj(w, "punch") == 1, "tap = air punch projectile")
	ok(absf(chi0 - p.chi - C.PUNCH_COST) < 4.0, "punch costs %.0f chi" % C.PUNCH_COST)
	run_ticks(p, 50, func(): return ip())
	ok(absf(b.hp - (C.BOT_HP - C.PUNCH_DAMAGE)) < 0.01, "punch hits bot for %.0f (hp %.0f)" % [C.PUNCH_DAMAGE, b.hp])
	ok(b.pos.z < -4.2, "punch knocks the bot back (z -4.0 -> %.1f)" % b.pos.z)
	ok(p.ult > 0.0 and has_wevent(w, "bot_hit"), "damage dealt feeds the ultimate meter and emits an event")

	r = fresh(); w = r[0]; p = r[1]
	tap_fire(p)
	tap_fire(p)
	ok(count_proj(w, "punch") == 1, "punch has a short cooldown")
	run_ticks(p, 30, func(): return ip())
	tap_fire(p)
	ok(count_proj(w, "punch") >= 1 and p.chi < C.CHI_MAX - 2.0 * C.PUNCH_COST + 0.5, "punches work again after the cooldown")

	# --- Charged blast (hold, release)
	r = fresh(); w = r[0]; p = r[1]
	b = add_bot(w, 0.0, -4.0)
	hold_fire(p, 160)
	ok(p.charging and p.charge >= 0.999, "holding charges the blast to full (charge %.2f)" % p.charge)
	ok(absf((C.CHI_MAX - p.chi) - C.CHARGE_DRAIN * C.CHARGE_TIME) < 12.0, "full charge costs ~%.0f chi (spent %.1f)" % [C.CHARGE_DRAIN * C.CHARGE_TIME, C.CHI_MAX - p.chi])
	p.step(TICK, ip())                                  # release
	var expect := C.BLAST_DAMAGE_FULL * (1.0 - 0.5 * 8.0 / C.BLAST_RANGE_FULL)
	ok(has_event(p, "blast") and absf(b.hp - (C.BOT_HP - expect)) < 1.0, "full blast hits for ~%.0f (hp %.1f)" % [expect, b.hp])
	ok(b.vel.length() > 15.0, "full blast launches the bot (%.1f m/s)" % b.vel.length())
	ok(not p.charging and p.charge == 0.0, "charge resets after firing")

	r = fresh(); w = r[0]; p = r[1]
	hold_fire(p, 60)
	ok(p.charging and p.charge > 0.2 and p.charge < 0.32, "half-second hold gives a partial charge (%.2f)" % p.charge)

	r = fresh(); w = r[0]; p = r[1]
	p.chi = 10.0
	hold_fire(p, 240)
	ok(p.chi >= 0.0 and p.charge < 0.9, "charging stops when chi runs out (charge %.2f, chi %.1f)" % [p.charge, p.chi])

	r = fresh(); w = r[0]; p = r[1]
	p.pitch = -1.2
	hold_fire(p, 160)
	p.step(TICK, ip())
	ok(p.vel.y > 8.0 and not p.on_ground, "charged blast at your feet launches you (vy=%.1f)" % p.vel.y)

	# --- Air Slice
	r = fresh(); w = r[0]; p = r[1]
	var b1 = add_bot(w, 0.0, -4.0)
	var b2 = add_bot(w, 0.0, -12.0)
	chi0 = p.chi
	press_slice(p)
	ok(count_proj(w, "slice") == 1 and has_event(p, "slice"), "right click throws an air slice")
	ok(absf(chi0 - p.chi - C.SLICE_COST) < 0.1, "slice costs %.0f chi" % C.SLICE_COST)
	press_slice(p)
	ok(count_proj(w, "slice") == 1, "slice has a cooldown")
	run_ticks(p, 140, func(): return ip())
	ok(absf(b1.hp - (C.BOT_HP - C.SLICE_DAMAGE)) < 0.01 and absf(b2.hp - (C.BOT_HP - C.SLICE_DAMAGE)) < 0.01,
			"slice pierces: both bots hit exactly once (%.0f, %.0f)" % [b1.hp, b2.hp])
	ok(count_proj(w, "slice") == 0, "slice expires")

	r = fresh(); w = r[0]; p = r[1]
	p.pos = Vector3(2.0, w.height_at(2.0, 8.0), 8.0)
	p.yaw = PI                                              # facing +z, toward the 2.2 m wall at z=14
	var behind = add_bot(w, 2.0, 20.0)
	press_slice(p)
	run_ticks(p, 140, func(): return ip())
	ok(behind.hp == C.BOT_HP and count_proj(w, "slice") == 0, "slice is stopped by a wall")


# ------------------------------------------------------------------ shield, suction

func test_defense() -> void:
	# --- Air Shield: reflects bolts back at the shooter
	var r := fresh()
	var w = r[0]
	var p = r[1]
	var shooter = add_bot(w, 0.0, -10.0)
	var from: Vector3 = shooter.pos + Vector3(0, 1.4, 0)
	var to: Vector3 = p.pos + Vector3(0, 1.0, 0)
	w.spawn_proj("bolt", "enemy", from, (to - from).normalized() * C.BOT_BOLT_SPEED, C.BOT_BOLT_LIFE,
			C.BOT_BOLT_RADIUS, C.BOT_BOLT_DAMAGE, 0.0, false, 0.0, shooter)
	run_ticks(p, 120, func(): return ip())
	ok(absf(p.hp - (C.PLAYER_HP - C.BOT_BOLT_DAMAGE)) < 0.01, "bolt without a shield hurts (hp %.0f)" % p.hp)

	r = fresh(); w = r[0]; p = r[1]
	shooter = add_bot(w, 0.0, -10.0)
	from = shooter.pos + Vector3(0, 1.4, 0)
	to = p.pos + Vector3(0, 1.0, 0)
	w.spawn_proj("bolt", "enemy", from, (to - from).normalized() * C.BOT_BOLT_SPEED, C.BOT_BOLT_LIFE,
			C.BOT_BOLT_RADIUS, C.BOT_BOLT_DAMAGE, 0.0, false, 0.0, shooter)
	var chi0: float = p.chi
	var held := func():
		var a := ip()
		a.shield_held = true
		return a
	run_ticks(p, 60, held)
	ok(p.shield_on, "holding E raises the shield")
	run_ticks(p, 120, held)
	ok(p.hp == C.PLAYER_HP, "shield stops the bolt (hp %.0f)" % p.hp)
	ok(has_wevent(w, "deflect"), "bolt is deflected")
	var expect_hit := C.BOT_BOLT_DAMAGE * C.SHIELD_REFLECT_MULT
	ok(absf(shooter.hp - (C.BOT_HP - expect_hit)) < 0.01, "reflected bolt hits the shooter for %.1f (hp %.1f)" % [expect_hit, shooter.hp])
	ok(absf((chi0 - p.chi) - C.SHIELD_DRAIN * 3.0 / 2.0) < 2.5, "shield drains ~%.0f chi/s (spent %.1f in 1.5 s)" % [C.SHIELD_DRAIN, chi0 - p.chi])
	run_ticks(p, 20, func(): return ip())
	ok(not p.shield_on, "shield drops when E is released")

	r = fresh(); p = r[1]
	p.chi = 5.0
	run_ticks(p, 10, held)
	ok(not p.shield_on, "shield needs minimum chi")

	# --- Air Suction: drags bots toward you
	r = fresh(); w = r[0]; p = r[1]
	var target = add_bot(w, 0.0, -8.0)                      # 12 m ahead
	var side = add_bot(w, 0.0, 12.5)                        # 8.5 m behind (outside the cone, clear of the wall line)
	var d0: float = target.pos.distance_to(p.pos)
	var side_start: Vector3 = side.pos
	chi0 = p.chi
	var pull := func():
		var a := ip()
		a.suction_held = true
		return a
	run_ticks(p, 240, pull)
	var d1: float = target.pos.distance_to(p.pos)
	ok(p.suction_on and d1 < 5.0, "suction drags the bot in (%.1f m -> %.1f m)" % [d0, d1])
	ok(target.hp == C.BOT_HP, "suction does no damage")
	ok(side.pos.distance_to(side_start) < 0.5, "bots outside the cone are not pulled")
	ok(absf((chi0 - p.chi) - C.SUCTION_DRAIN * 2.0) < 2.5, "suction drains ~%.0f chi/s (spent %.1f in 2 s)" % [C.SUCTION_DRAIN, chi0 - p.chi])
	run_ticks(p, 10, func(): return ip())
	ok(not p.suction_on, "suction stops when F is released")


# ------------------------------------------------------------------ ultimates

func test_ultimates() -> void:
	# --- Air Breath
	var r := fresh()
	var w = r[0]
	var p = r[1]
	var near = add_bot(w, 0.0, -6.0)                        # 10 m
	var far = add_bot(w, 0.0, -16.0)                        # 20 m
	var off = add_bot(w, 10.0, -8.0)                        # 12 m ahead, 10 m to the side (outside the cone)
	press_ult(p)
	ok(p.breath_t == 0.0 and p.ult < C.ULT_MAX, "ultimate does nothing without a full meter")
	p.ult = C.ULT_MAX
	press_ult(p)
	ok(p.breath_t > 0.0 and p.state_name() == "AIR BREATH" and p.ult < 1.0, "full meter on the ground fires Air Breath and empties the meter")
	ok(has_event(p, "breath_start"), "breath_start event")
	run_ticks(p, int(C.BREATH_DURATION * 120.0) + 20, func(): return ip())
	ok(not near.alive and not far.alive, "breath kills bots at 10 m and 20 m (hp left %.0f / %.0f)" % [near.hp, far.hp])
	ok(off.hp == C.BOT_HP, "bots outside the cone are untouched")
	ok(p.breath_t == 0.0 and has_event(p, "breath_end"), "breath ends after %.1fs" % C.BREATH_DURATION)

	r = fresh(); w = r[0]; p = r[1]
	p.ult = C.ULT_MAX
	p.pos.y += 4.0                                          # airborne but low: still the breath
	p.on_ground = false
	press_ult(p)
	ok(p.breath_t > 0.0 and p.slam.is_empty(), "airborne but low (4 m) fires the breath, not the bomb")

	# --- Air Bomb
	r = fresh(); w = r[0]; p = r[1]
	var b5 = add_bot(w, 5.0, 4.0)
	var b9 = add_bot(w, 9.0, 4.0)
	var bfar = add_bot(w, -30.0, 4.0)
	p.pos.y += 15.0
	p.on_ground = false
	p.ult = C.ULT_MAX
	ok(p.ult_kind() == "bomb", "high in the air the ultimate becomes the Air Bomb")
	press_ult(p)
	ok(not p.slam.is_empty() and p.state_name() == "AIR BOMB" and has_event(p, "bomb_wind"), "bomb starts with a wind-up")
	ok(p.ult < 1.0, "bomb spends the ultimate meter")
	var hp_before: float = p.hp
	p.take_damage(50.0)
	ok(p.hp == hp_before, "you cannot be hurt during the bomb")
	var n := 0
	var dive_seen := false
	while not p.slam.is_empty() and n < 600:
		p.step(TICK, ip())
		if has_event(p, "bomb_dive"):
			dive_seen = true
		n += 1
	ok(dive_seen and p.on_ground and p.slam.is_empty(), "bomb dives and lands (%.2fs)" % (n / 120.0))
	var k := clampf((15.0 - C.BOMB_MIN_HEIGHT) / 20.0, 0.0, 1.0)
	var rad := C.BOMB_RADIUS * (0.7 + 0.3 * k)
	var dmg := C.BOMB_DAMAGE * (0.8 + 0.2 * k)
	var e5 := dmg * (1.0 - 0.6 * 5.0 / rad)
	ok(has_wevent(w, "slam") and has_event(p, "bomb"), "landing emits slam events")
	ok(b5.hp < C.BOT_HP - 0.5 * e5 and b9.hp < C.BOT_HP and b5.hp < b9.hp, "AOE damage falls off with distance (hp %.0f at 5 m, %.0f at 9 m, expected ~%.0f at 5 m)" % [b5.hp, b9.hp, e5])
	ok(bfar.hp == C.BOT_HP, "bot outside the blast radius (%.1f m) is untouched" % rad)
	ok(p.ult > 5.0, "damage dealt by the bomb recharges the meter (%.0f)" % p.ult)
	p.take_damage(10.0)
	ok(p.hp < hp_before, "vulnerable again after landing")

	# the Air Temple mountain is the intended way up there
	r = fresh(); w = r[0]; p = r[1]
	p.pos = Vector3(w.summit.x, w.summit.y + 0.05, w.summit.z)
	p.ult = C.ULT_MAX
	p.step(TICK, ip())
	ok(p.on_ground and p.ult_kind() == "breath", "standing on the summit (%.1f m): ultimate is the breath" % w.summit.y)
	p.pos.x += 22.0                                         # step off the side, far above the slope below
	p.on_ground = false
	run_ticks(p, 10, func(): return ip())
	ok(not p.on_ground and p.height_above_ground() >= C.BOMB_MIN_HEIGHT and p.ult_kind() == "bomb",
			"stepping off the summit: ultimate becomes the bomb (%.1f m up)" % p.height_above_ground())


# ------------------------------------------------------------------ terrain

func press_key(p, which: String) -> void:
	var a := ip()
	if which == "e":
		a.shield_held = true
	else:
		a.suction_held = true
	p.step(TICK, a)
	p.step(TICK, ip())


func go_earth(p) -> void:
	var a := ip()
	a.element_pressed = "earth"
	p.step(TICK, a)


func flat_test_ground(w) -> void:
	w.terrain.flatten(0.0, 40.0, 28.0, 34.0, 0.0)       # wipes the ridges near z=16 too: a clean arena


func test_terrain() -> void:
	var w := WorldScript.new(1337)
	w.bots.clear()
	var t = w.terrain
	var N: int = t.N
	ok(absf(t.height_at(12.0, -7.0) - t.h[(-7 + int(t.HALF)) * N + (12 + int(t.HALF))]) < 1e-4, "height_at hits the grid height at a vertex")
	var tri_ok := true
	for k in range(60):
		var x := 3.2 + k * 1.37
		var z := -40.0 + k * 0.91
		var ix := int(floor(x + t.HALF))
		var iz := int(floor(z + t.HALF))
		var fx: float = x + t.HALF - ix
		var fz: float = z + t.HALF - iz
		var h0: float = t.h[iz * N + ix]
		var h1: float = t.h[iz * N + ix + 1]
		var h2: float = t.h[(iz + 1) * N + ix]
		var h3: float = t.h[(iz + 1) * N + ix + 1]
		var want: float = h0 + fx * (h1 - h0) + fz * (h2 - h0) if fx + fz <= 1.0 else h3 + (1.0 - fx) * (h2 - h3) + (1.0 - fz) * (h1 - h3)
		if absf(want - t.height_at(x, z)) > 1e-3:
			tri_ok = false
	ok(tri_ok, "height_at interpolates exactly over the triangles the renderer draws")
	ok(w.height_at(spawn_x(), 4.0) < 0.01 and absf(w.height_at(0.0, 4.0)) < 0.5, "start zone is flat")
	ok(w.summit.y > 22.0, "the Air Temple summit is %.1f m up" % w.summit.y)
	var hills := 0
	for k in range(30):
		var q := Vector2(-16.0 - 9.0 * (k % 5), -10.0)
		hills += 1 if w.height_at(q.x, q.y) > 1.5 else 0
	ok(hills >= 25, "the pillar chain is now a chain of hills")

	# walls: a steep hill cannot be walked up
	flat_test_ground(w)
	w.terrain.raise_mound(0.0, 40.0, 2.0, 1.5, 6.0)
	var p := SimScript.new(w)
	p.pos = Vector3(0.0, 0.0, 30.0)
	p.yaw = PI
	run_ticks(p, 30, func(): return ip())
	run_ticks(p, 480, func(): return inp(0, 1, true))
	ok(p.pos.z < 37.5 and p.pos.y < 1.5 and finite(p), "a 6 m steep hill is a wall on foot (z=%.1f y=%.1f)" % [p.pos.z, p.pos.y])

	# a gentle hill can be run up
	w = WorldScript.new(1337)
	w.bots.clear()
	flat_test_ground(w)
	w.terrain.raise_mound(0.0, 40.0, 2.0, 9.0, 4.0)
	p = SimScript.new(w)
	p.pos = Vector3(0.0, 0.0, 28.0)
	p.yaw = PI
	run_ticks(p, 30, func(): return ip())
	var top_y := 0.0
	for k in range(720):
		p.step(TICK, inp(0, 1, true))
		top_y = maxf(top_y, p.pos.y)
	ok(top_y > 3.0 and finite(p), "a gentle 4 m hill is walkable to the top (reached y=%.1f)" % top_y)

	# sliding down it gains speed
	p.pos = Vector3(0.0, 4.2, 40.0)
	p.vel = Vector3.ZERO
	p.yaw = 0.0
	var gain := 0.0
	run_ticks(p, 20, func(): return inp(0, 1, true))
	p.step(TICK, inp(0, 1, false, true))
	for k in range(200):
		p.step(TICK, inp(0, 0, false, true))
		gain = maxf(gain, p.speed())
	ok(gain > 9.0 and finite(p), "sliding down a hill builds speed (%.1f m/s)" % gain)

	# a slope past the walkable limit dumps you downhill
	w = WorldScript.new(1337)
	w.bots.clear()
	flat_test_ground(w)
	w.terrain.raise_mound(0.0, 40.0, 0.5, 1.8, 6.0)
	p = SimScript.new(w)
	p.pos = Vector3(0.0, w.height_at(0.0, 40.0), 40.0)
	p.vel = Vector3.ZERO
	p.on_ground = true
	run_ticks(p, 240, func(): return ip())
	ok(p.pos.distance_to(Vector3(0.0, 0.0, 40.0)) > 0.8 and finite(p), "too steep to stand on: you slip off (now %.1f m from the top)" % Vector2(p.pos.x, p.pos.z - 40.0).length())

	# terrain edits mark the render chunks that changed
	w = WorldScript.new(1337)
	w.terrain.take_dirty()
	w.crater(Vector3(-50.0, 0.0, -50.0), 3.0, 1.0)
	var keys: Array = w.terrain.take_dirty()
	ok(keys.has(7 * w.terrain.NCHUNK + 7) and keys.size() <= 4, "a crater marks only its own render chunks dirty (%s)" % str(keys))

	# raised ground has a ceiling, dug ground has a floor
	w.terrain.raise_mound(30.0, -60.0, 3.0, 3.0, 500.0)
	ok(w.height_at(30.0, -60.0) <= w.terrain.base_at(30.0, -60.0) + C_MAX_RAISE() + 0.01, "spires stop at the maximum height")
	for k in range(10):
		w.terrain.carve_crater(0.0, 40.0, 4.0, 3.0)
	ok(w.height_at(0.0, 40.0) >= w.terrain.base_at(0.0, 40.0) - 3.5 - 0.01, "craters have a floor (%.2f)" % w.height_at(0.0, 40.0))


func spawn_x() -> float:
	return 0.0


func C_MAX_RAISE() -> float:
	return 45.0


# ------------------------------------------------------------------ earthbending

func test_earth() -> void:
	# --- element switch
	var r := fresh()
	var w = r[0]
	var p = r[1]
	ok(p.element == "air", "you start as an airbender")
	go_earth(p)
	ok(p.element == "earth" and has_event(p, "element"), "pressing 2 switches to earth")
	p.step(TICK, inp(0, 0, false, false, false, true))
	run_ticks(p, 40, func(): return inp())
	p.events.clear()
	p.step(TICK, inp(0, 0, false, false, false, true))
	ok(not has_event(p, "gust"), "an earthbender has no gust jump")
	var sc := inp()
	sc.scooter_pressed = true
	run_ticks(p, 200, func(): return inp())
	p.step(TICK, sc)
	ok(not p.scooter, "no air scooter in earth mode")

	# --- rock throw
	r = fresh(); w = r[0]; p = r[1]
	go_earth(p)
	var b = add_bot(w, 0.0, -4.0)
	var chi0: float = p.chi
	tap_fire(p)
	ok(count_proj(w, "rock") == 1 and has_event(p, "rock"), "tap = rock throw")
	ok(absf(chi0 - p.chi - C.ROCK_COST) < 0.1, "rock costs %.0f chi" % C.ROCK_COST)
	run_ticks(p, 60, func(): return ip())
	ok(b.hp < C.BOT_HP - C.ROCK_DAMAGE + 0.5, "rock hits the bot (hp %.0f)" % b.hp)
	ok(has_wevent(w, "proj_hit"), "rock impact event")

	r = fresh(); w = r[0]; p = r[1]
	go_earth(p)
	p.pitch = -0.3
	var before_min := 0.0
	tap_fire(p)
	run_ticks(p, 60, func(): return ip())
	var low := 0.0
	for k in range(40):
		low = minf(low, w.height_at(0.0, 3.0 - k * 0.1))
	ok(low < -0.5 and has_wevent(w, "rock_burst"), "a rock that hits the ground digs a crater (%.2f m)" % low)

	# --- earth wave (hold + release)
	r = fresh(); w = r[0]; p = r[1]
	go_earth(p)
	var bw = add_bot(w, 0.0, -10.0)
	var bside = add_bot(w, 9.0, -10.0)
	hold_fire(p, 160)
	ok(p.charging and p.charge >= 0.999, "holding charges the earth wave")
	p.step(TICK, ip())
	ok(has_event(p, "wave") and w.jobs.size() >= 1, "release sends an earth wave")
	run_ticks(p, 90, func(): return ip())
	ok(w.height_at(0.0, -10.0) > 2.5 and w.height_at(0.0, -25.0) > 2.5, "the wave leaves a ridge of earth along its path (%.1f / %.1f m)" % [w.height_at(0.0, -10.0), w.height_at(0.0, -25.0)])
	ok(bw.hp < C.BOT_HP - 30.0, "the wave hurts the bot it passes under (hp %.0f)" % bw.hp)
	ok(bside.hp == C.BOT_HP, "a bot beside the wave is untouched")
	ok(w.jobs.size() == 0, "the wave job finishes")

	# --- earth skate (Q): ride a slab over the ground
	r = fresh(); w = r[0]; p = r[1]
	go_earth(p)
	chi0 = p.chi
	press_edge(p, "scooter_pressed")
	ok(p.skating and not p.scooter and p.state_name() == "EARTH SKATE", "Q starts the earth skate (not the air scooter)")
	var top_sp := 0.0
	for k in range(240):
		p.step(TICK, inp(0, 1, true))
		top_sp = maxf(top_sp, p.speed())
	ok(top_sp > C.SPRINT_SPEED + 3.0 and finite(p), "skating is faster than sprinting (%.1f vs %.1f m/s)" % [top_sp, C.SPRINT_SPEED])
	ok(p.chi < chi0 - 4.0, "skating drains chi slowly (%.0f -> %.0f)" % [chi0, p.chi])
	press_edge(p, "scooter_pressed")
	ok(not p.skating, "Q again stops skating")
	r = fresh(); w = r[0]; p = r[1]
	press_edge(p, "scooter_pressed")
	ok(p.scooter and not p.skating, "as an airbender Q is still the air scooter")

	# --- air scooter wall run: enough speed takes a steep wall, a slow scooter cannot
	for case in [["fast", 20.0, true], ["slow", 3.0, false]]:
		var wr_w := WorldScript.new(1337)
		wr_w.bots.clear()
		wr_w.terrain.flatten(0.0, 40.0, 28.0, 34.0, 0.0)
		wr_w.earth_wall_at(Vector2(0.0, 40.0), Vector2(0.0, 1.0), 6.5, 5.5)
		for k in range(60):
			wr_w.update_combat(TICK, null)
		var wp = SimScript.new(wr_w)
		wp.pos = Vector3(0.0, 0.05, 40.0 - float(case[1]))
		wp.yaw = PI
		run_ticks(wp, 30, func(): return ip())
		press_edge(wp, "scooter_pressed")
		var wr_top := 0.0
		var saw_wr := false
		for k in range(600):
			wp.step(TICK, inp(0, 1))
			wr_top = maxf(wr_top, wp.pos.y)
			saw_wr = saw_wr or wp.wallrun
		if bool(case[2]):
			ok(wr_top > 5.0 and finite(wp), "air scooter at speed runs up a 5.5 m wall (top %.1f, wall run %s)" % [wr_top, saw_wr])
		else:
			ok(not saw_wr and finite(wp), "a scooter starting right at the wall is too slow to wall run")

	# --- earth elevator: hold Space against a wall and ride up it
	r = fresh(); w = r[0]; p = r[1]
	flat_test_ground(w)
	w.terrain.raise_mound(0.0, 40.0, 3.0, 1.2, 13.0)
	go_earth(p)
	p.pos = Vector3(0.0, 0.05, 34.0)
	p.yaw = PI
	run_ticks(p, 30, func(): return ip())
	var climb_top := 0.0
	var saw_elev := false
	var elev_chi0: float = p.chi
	var first := true
	for k in range(420):
		var ei := inp(0, 1, true, false, true, first)
		first = false
		p.step(TICK, ei)
		climb_top = maxf(climb_top, p.pos.y)
		if p.elevating:
			saw_elev = true
	ok(saw_elev and p.pos.y > 11.5 and finite(p), "Space against a 13 m wall rides the elevator to the top (y=%.1f)" % p.pos.y)
	ok(p.chi < elev_chi0 - 3.0, "the elevator costs chi (%.0f -> %.0f)" % [elev_chi0, p.chi])
	r = fresh(); w = r[0]; p = r[1]
	flat_test_ground(w)
	w.terrain.raise_mound(0.0, 40.0, 3.0, 1.2, 13.0)
	p.pos = Vector3(0.0, 0.05, 34.0)
	p.yaw = PI
	run_ticks(p, 30, func(): return ip())
	var air_top := 0.0
	first = true
	for k in range(420):
		p.step(TICK, inp(0, 1, true, false, true, first))
		first = false
		air_top = maxf(air_top, p.pos.y)
	ok(air_top < 6.0, "an airbender cannot scale the same wall (best %.1f m)" % air_top)

	# --- earth armor (V)
	r = fresh(); w = r[0]; p = r[1]
	go_earth(p)
	chi0 = p.chi
	var plain_sp := 0.0
	for k in range(200):
		p.step(TICK, inp(0, 1, true))
		plain_sp = maxf(plain_sp, p.speed())
	p.pos = w.spawn + Vector3(0, 0.05, 0)
	p.vel = Vector3.ZERO
	run_ticks(p, 120, func(): return ip())
	chi0 = p.chi
	press_edge(p, "armor_pressed")
	ok(p.armor_on and absf(chi0 - p.chi - C.ARMOR_COST) < 0.6 and has_event(p, "armor_on"), "V gathers earth armor (costs %.0f)" % C.ARMOR_COST)
	var armor_sp := 0.0
	for k in range(200):
		p.step(TICK, inp(0, 1, true))
		armor_sp = maxf(armor_sp, p.speed())
	ok(armor_sp < plain_sp * 0.85, "armor slows you down (%.1f vs %.1f m/s)" % [armor_sp, plain_sp])
	p.pos = w.spawn + Vector3(0, 0.05, 0)
	p.vel = Vector3.ZERO
	p.hp = C.PLAYER_HP
	p.hp_delay = 99.0
	p.take_damage(10.0)
	ok(absf((C.PLAYER_HP - p.hp) - 10.0 * (1.0 - C.ARMOR_SOAK)) < 0.01 and absf(p.armor_hp - (C.ARMOR_HP - 10.0 * C.ARMOR_SOAK)) < 0.5, "armor soaks %.0f%% of a hit (took %.1f)" % [C.ARMOR_SOAK * 100.0, C.PLAYER_HP - p.hp])
	var hits := 0
	while p.armor_on and hits < 40:
		p.take_damage(20.0)
		hits += 1
	ok(not p.armor_on and has_event(p, "armor_break"), "armor breaks after enough hits (%d)" % hits)
	run_ticks(p, 120 * 6, func(): return ip())
	ok(p.armor_hp > 20.0 and p.armor_hp < C.ARMOR_HP, "broken armor slowly rebuilds (%.0f)" % p.armor_hp)
	press_edge(p, "armor_pressed")
	ok(p.armor_on, "you can gather it again")
	var sw2 := ip()
	sw2.element_pressed = "air"
	p.step(TICK, sw2)
	ok(not p.armor_on, "switching nation drops the armor")

	# --- the nation can only change when it is safe to
	r = fresh(); w = r[0]; p = r[1]
	ok(p.can_switch_element(), "you can pick a nation normally")

	# --- earth wall: big, permanent, blocks bolts
	r = fresh(); w = r[0]; p = r[1]
	go_earth(p)
	var shooter = add_bot(w, 0.0, -9.0)
	press_key(p, "e")
	run_ticks(p, 45, func(): return ip())
	ok(w.height_at(0.0, -1.5) > C.WALL_HEIGHT - 1.0, "E raises a wall in front of you (%.1f m)" % w.height_at(0.0, -1.5))
	ok(w.height_at(6.0, -1.5) > 3.5 and w.height_at(-6.0, -1.5) > 3.5, "and it is wide: %.0f m across" % (C.WALL_HALF_WIDTH * 2.0))
	ok(w.walls.size() == 1 and w.terrain.pinned.size() > 20, "the finished wall is pinned (%d cells)" % w.terrain.pinned.size())
	var from: Vector3 = shooter.pos + Vector3(0, 1.4, 0)
	var to: Vector3 = p.pos + Vector3(0, 1.0, 0)
	w.spawn_proj("bolt", "enemy", from, (to - from).normalized() * C.BOT_BOLT_SPEED, C.BOT_BOLT_LIFE,
			C.BOT_BOLT_RADIUS, C.BOT_BOLT_DAMAGE, 0.0, false, 0.0, shooter)
	run_ticks(p, 120, func(): return ip())
	ok(p.hp == C.PLAYER_HP and count_proj(w, "bolt") == 0, "the wall stops the bolt (hp %.0f)" % p.hp)
	var wall_before: float = w.height_at(0.0, -1.5)
	run_ticks(p, 120 * 45, func(): return ip())
	ok(w.height_at(0.0, -1.5) > wall_before - 0.05, "the wall never sinks back (%.1f m after 45 s)" % w.height_at(0.0, -1.5))

	# --- grab the wall and carry it as a shield
	var chi_g: float = p.chi
	press_edge(p, "grab_pressed")
	ok(not w.held.is_empty() and w.walls.size() == 0 and has_event(p, "grab"), "G picks the wall up")
	ok(w.height_at(0.0, -1.5) < 1.0, "the wall is gone from the ground (%.1f m)" % w.height_at(0.0, -1.5))
	run_ticks(p, 10, func(): return ip())
	var held_c: Vector3 = w.held["c"]
	ok(absf(held_c.z - (p.pos.z - C.HELD_DIST)) < 0.3, "the slab follows you (%.1f m ahead)" % (p.pos.z - held_c.z))
	var sp_held := 0.0
	for k in range(200):
		p.step(TICK, inp(0, -1, true))
		sp_held = maxf(sp_held, p.speed())
	ok(sp_held < C.SPRINT_SPEED * 0.9, "carrying it slows you (%.1f m/s)" % sp_held)
	p.pos = Vector3(0.0, w.height_at(0.0, 4.0) + 0.05, 4.0)
	p.vel = Vector3.ZERO
	p.yaw = 0.0
	run_ticks(p, 10, func(): return ip())
	shooter.pos = Vector3(0.0, w.height_at(0.0, -9.0), -9.0)
	from = shooter.pos + Vector3(0, 1.4, 0)
	to = p.pos + Vector3(0, 1.0, 0)
	var hp0: float = float(w.held["hp"])
	w.spawn_proj("bolt", "enemy", from, (to - from).normalized() * C.BOT_BOLT_SPEED, C.BOT_BOLT_LIFE,
			C.BOT_BOLT_RADIUS, C.BOT_BOLT_DAMAGE, 0.0, false, 0.0, shooter)
	run_ticks(p, 120, func(): return ip())
	ok(p.hp == C.PLAYER_HP and not w.held.is_empty() and float(w.held["hp"]) < hp0, "the carried slab takes the bolt (slab hp %.0f -> %.0f, yours %.0f)" % [hp0, float(w.held["hp"]), p.hp])
	var broke := false
	for k in range(60):
		w.spawn_proj("bolt", "enemy", from, (to - from).normalized() * C.BOT_BOLT_SPEED, C.BOT_BOLT_LIFE,
				C.BOT_BOLT_RADIUS, C.BOT_BOLT_DAMAGE * 2.0, 0.0, false, 0.0, shooter)
		run_ticks(p, 40, func(): return ip())
		if w.held.is_empty():
			broke = true
			break
	ok(broke and has_wevent(w, "held_break") and p.hp == C.PLAYER_HP, "the slab breaks after enough hits (until it breaks your hp is untouched)")

	# --- plant it back
	r = fresh(); w = r[0]; p = r[1]
	go_earth(p)
	press_key(p, "e")
	run_ticks(p, 45, func(): return ip())
	press_edge(p, "grab_pressed")
	ok(not w.held.is_empty(), "grab again")
	press_edge(p, "grab_pressed")
	run_ticks(p, 60, func(): return ip())
	ok(w.held.is_empty() and w.walls.size() == 1 and w.height_at(0.0, -1.5) > 3.0, "G again plants it as a new wall (%.1f m)" % w.height_at(0.0, -1.5))
	r = fresh(); w = r[0]; p = r[1]
	go_earth(p)
	press_edge(p, "grab_pressed")
	ok(w.held.is_empty(), "G with no wall nearby does nothing")

	# --- earth pillar at the crosshair
	r = fresh(); w = r[0]; p = r[1]
	go_earth(p)
	p.pitch = -0.16
	var bp = add_bot(w, 0.0, -6.0)
	chi0 = p.chi
	press_key(p, "f")
	ok(w.jobs.size() == 1 and absf(chi0 - p.chi - C.PILLAR_COST) < 0.1, "F raises a pillar where you aim (costs %.0f)" % C.PILLAR_COST)
	run_ticks(p, 60, func(): return ip())
	ok(w.height_at(0.0, -6.0) > 5.5, "the pillar is %.1f m tall" % w.height_at(0.0, -6.0))
	ok(bp.hp <= C.BOT_HP - C.PILLAR_BOT_DAMAGE + 0.01, "the bot on it is hurt (hp %.0f)" % bp.hp)
	ok(bp.pos.y > 1.0, "and thrown up with it (y=%.1f)" % bp.pos.y)

	# --- pillar under your own feet launches you
	r = fresh(); w = r[0]; p = r[1]
	go_earth(p)
	p.pitch = -1.5
	press_key(p, "f")
	var peak := 0.0
	var launched := false
	for k in range(120):
		p.step(TICK, ip())
		peak = maxf(peak, p.pos.y)
		if has_event(p, "launched"):
			launched = true
	ok(launched and peak > 6.0 and finite(p), "a pillar under your feet throws you up (peak %.1f m)" % peak)

	# --- RMB boulder: pulled from the ground first, then thrown
	r = fresh(); w = r[0]; p = r[1]
	go_earth(p)
	p.pitch = -0.15
	var bi := ip()
	bi.slice_pressed = true
	p.step(TICK, bi)
	ok(not p.boulder_pull.is_empty() and has_event(p, "boulder_pull") and w.projectiles.size() == 0, "RMB first pulls a boulder out of the ground")
	run_ticks(p, 30, func(): return ip())
	ok(w.projectiles.size() == 0, "still held mid-pull")
	run_ticks(p, 40, func(): return ip())
	var boulders := 0
	for pr in w.projectiles:
		if pr.kind == "boulder":
			boulders += 1
	ok(boulders == 1 and p.boulder_pull.is_empty() and has_event(p, "boulder"), "then it is thrown along your sight line")

	# --- earth charge takes earth from around you
	r = fresh(); w = r[0]; p = r[1]
	go_earth(p)
	var ch := ip()
	ch.fire_pressed = true
	ch.fire_held = true
	p.step(TICK, ch)
	for k in range(120):
		var ch2 := ip()
		ch2.fire_held = true
		p.step(TICK, ch2)
	ok(p.charging and has_event(p, "earth_take"), "holding LMB as earth pulls earth out of the ground around you")

	# --- ultimate on the ground: Earth Clap
	r = fresh(); w = r[0]; p = r[1]
	go_earth(p)
	var c1 = add_bot(w, 0.0, -14.0)
	var c2 = add_bot(w, 2.0, -14.5)
	var c4 = add_bot(w, 15.0, -14.0)
	var cfar = add_bot(w, -40.0, 30.0)
	p.pitch = -0.095
	p.ult = C.ULT_MAX
	ok(p.ult_kind() == "clap", "earth ultimate on the ground is the Earth Clap")
	press_ult(p)
	ok(w.jobs.size() == 1 and has_event(p, "clap") and p.ult < 15.0, "X calls the slabs and empties the meter (the rising pages already feed a little back)")
	run_ticks(p, 70, func(): return ip())
	ok(has_wevent(w, "clap_rise") and w.height_at(C.CLAP_GAP, -14.0) < 2.0, "the pages open from the ground without reshaping the terrain")
	ok(c1.alive and c2.alive, "with the enemies still between the pages")
	run_ticks(p, 80, func(): return ip())
	ok(has_wevent(w, "clap_rise") and has_wevent(w, "clap_slam"), "rise and slam events")
	ok(not c1.alive and not c2.alive, "the slabs slam together and crush what is between them")
	ok(c4.hp == C.BOT_HP and cfar.hp == C.BOT_HP, "bots outside are untouched")
	ok(w.jobs.size() == 0, "the book finishes closing and the job ends")
	ok(finite(p) and p.pos.distance_to(Vector3(0.0, 0.0, 4.0)) < 3.0, "you are not caught up in it")

	# --- ultimate in the air: Earthquake dive (and the 8 m threshold)
	r = fresh(); w = r[0]; p = r[1]
	go_earth(p)
	var q1 = add_bot(w, 0.0, -6.0)
	var q2 = add_bot(w, 6.0, -8.0)
	var qfar = add_bot(w, -40.0, 30.0)
	p.ult = C.ULT_MAX
	p.pos.y += 7.0
	p.on_ground = false
	p.step(TICK, ip())
	ok(p.ult_kind() == "clap", "7 m up is not high enough: still the clap")
	p.pos.y = w.height_at(p.pos.x, p.pos.z) + 9.0
	p.vel = Vector3.ZERO
	p.step(TICK, ip())
	ok(p.ult_kind() == "quake" and not p.on_ground, "9 m up the earth ultimate becomes the Earthquake dive")
	press_ult(p)
	ok(not p.slam.is_empty() and p.state_name() == "EARTHQUAKE DIVE" and p.ult < 1.0, "X starts the dive and empties the meter")
	var set_el := ip()
	set_el.element_pressed = "air"
	p.step(TICK, set_el)
	ok(p.element == "earth", "you cannot switch element mid-dive")
	var landed := false
	var nn := 0
	while not p.slam.is_empty() and nn < 600:
		p.step(TICK, ip())
		nn += 1
	landed = has_event(p, "quake_land")
	ok(landed and p.quake_t > 0.0 and p.state_name() == "EARTHQUAKE", "landing starts the earthquake (%.2f s dive)" % (nn / 120.0))
	var t0 := Time.get_ticks_msec()
	var lowest := 0.0
	var highest := 0.0
	for k in range(int((C.QUAKE_DURATION + 0.5) * 120.0)):
		p.step(TICK, ip())
		lowest = minf(lowest, p.pos.y)
		highest = maxf(highest, p.pos.y)
	print("   earthquake simulated in %d ms (3.7 s of game time)" % (Time.get_ticks_msec() - t0))
	ok(not q1.alive and not q2.alive, "the quake kills the bots around you")
	ok(qfar.hp == C.BOT_HP, "a bot outside the radius is untouched")
	ok(p.quake_t == 0.0 and has_event(p, "quake_end"), "the quake ends")
	var rumpled := 0
	var t = w.terrain
	var N: int = t.N
	var in_range := true
	for iz in range(160, 240):
		for ix in range(160, 240):
			var gi: int = iz * N + ix
			if absf(t.h[gi] - t.built[gi]) > 0.3:
				rumpled += 1
			if t.h[gi] < t.base[gi] - 3.5 - 0.01 or t.h[gi] > t.base[gi] + 45.01:
				in_range = false
	ok(rumpled > 200 and in_range, "the ground is left rumpled but inside its limits (%d cells moved)" % rumpled)
	ok(finite(p) and highest < 14.0, "you ride out the quake (y range %.1f .. %.1f)" % [lowest, highest])

	# --- bots thrown by earth take landing damage; airbender bots cushion the fall
	r = fresh(); w = r[0]; p = r[1]
	var f1 = add_bot(w, 10.0, 10.0)
	var f2 = add_bot(w, 14.0, 10.0)
	var f3 = add_bot(w, 18.0, 10.0)
	f2.air_user = true
	for fb in [f1, f2, f3]:
		fb.pos.y += 12.0
		fb.on_ground = false
	f1.fall_armed = true
	f2.fall_armed = true
	run_ticks(p, 200, func(): return ip())
	ok(f1.hp < C.BOT_HP - 15.0 and has_wevent(w, "bot_fall"), "a bot thrown by earth is hurt when it lands (hp %.0f)" % f1.hp)
	ok(f2.hp == C.BOT_HP and has_wevent(w, "bot_cushion"), "an airbender bot cushions the fall with air (hp %.0f)" % f2.hp)
	ok(f3.hp == C.BOT_HP, "a bot that was not thrown by earth takes no landing damage")
	f2.pos.y += 12.0
	f2.on_ground = false
	f2.fall_armed = true
	run_ticks(p, 200, func(): return ip())
	ok(f2.hp < C.BOT_HP - 15.0, "the cushion needs time to recharge (hp %.0f)" % f2.hp)


# ------------------------------------------------------------------ destruction

func test_destruction() -> void:
	# bomb crater, with a floor
	var r := fresh()
	var w = r[0]
	var p = r[1]
	p.pos.y += 15.0
	p.on_ground = false
	p.ult = C.ULT_MAX
	press_ult(p)
	var n := 0
	while not p.slam.is_empty() and n < 600:
		p.step(TICK, ip())
		n += 1
	var base_y: float = w.terrain.base_at(p.pos.x, p.pos.z)
	ok(has_wevent(w, "crater"), "the air bomb opens a crater")
	ok(w.height_at(p.pos.x, p.pos.z) <= base_y - 3.0 and w.height_at(p.pos.x, p.pos.z) >= base_y - 3.51,
			"crater is deep but stops at the floor (%.2f m below natural ground)" % (base_y - w.height_at(p.pos.x, p.pos.z)))
	ok(p.on_ground and absf(p.pos.y - w.height_at(p.pos.x, p.pos.z)) < 0.01, "you land on the crater floor")

	# charged blast scours the ground it hits
	r = fresh(); w = r[0]; p = r[1]
	p.pitch = -0.25
	var spot_z: float = 4.0 - 6.3
	var h_before: float = w.height_at(0.0, spot_z)
	hold_fire(p, 160)
	p.step(TICK, ip())
	var h_after: float = w.height_at(0.0, spot_z)
	ok(h_before - h_after > 1.5 and has_wevent(w, "crater"), "a full blast digs where it lands (%.2f -> %.2f)" % [h_before, h_after])

	# a quick blast does not
	r = fresh(); w = r[0]; p = r[1]
	p.pitch = -0.25
	h_before = w.height_at(0.0, spot_z)
	hold_fire(p, 30)
	p.step(TICK, ip())
	ok(absf(w.height_at(0.0, spot_z) - h_before) < 0.01, "a barely charged blast leaves the ground alone")

	# slices cut earth walls
	r = fresh(); w = r[0]; p = r[1]
	go_earth(p)
	press_key(p, "e")
	run_ticks(p, 45, func(): return ip())
	var wall_h: float = w.height_at(0.0, -1.5)
	var sw := ip()
	sw.element_pressed = "air"
	p.step(TICK, sw)
	press_slice(p)
	run_ticks(p, 60, func(): return ip())
	var cut_h: float = w.height_at(0.0, -1.5)
	ok(wall_h > 4.4 and wall_h - cut_h > 1.0, "an air slice cuts into an earth wall (%.1f -> %.1f m)" % [wall_h, cut_h])

	# blown-away hills: repeated impacts flatten a pillar all the way down to the floor
	r = fresh(); w = r[0]; p = r[1]
	w.earth_pillar(Vector3(0.0, 0.0, -20.0))
	for k in range(60):
		w.update_combat(TICK, null)
	var tall: float = w.height_at(0.0, -20.0)
	for k in range(10):
		w.crater(Vector3(0.0, 0.0, -20.0), 4.0, 2.5)
	ok(tall > 5.5 and w.height_at(0.0, -20.0) <= w.terrain.base_at(0.0, -20.0) - 3.4, "a 6.5 m pillar can be destroyed completely (%.1f -> %.1f)" % [tall, w.height_at(0.0, -20.0)])


# ------------------------------------------------------------------ bots, vitals

func test_healing() -> void:
	var r := fresh()
	var w = r[0]
	var p = r[1]
	var t = w.terrain
	var x := 0.0
	var z := -20.0
	var orig: float = t.height_at(x, z)
	w.crater(Vector3(x, orig, z), 4.0, 2.5)
	var dug: float = t.height_at(x, z)
	ok(orig - dug > 2.0, "setup: a crater %.1f m deep" % (orig - dug))
	run_ticks(p, int(C.HEAL_DELAY_DUG * 120.0 * 0.6), func(): return ip())
	ok(absf(t.height_at(x, z) - dug) < 0.05, "a fresh crater does not heal straight away")
	run_ticks(p, int(C.HEAL_DELAY_DUG * 120.0 * 0.6) + 120 * 6, func(): return ip())
	var mid: float = t.height_at(x, z)
	ok(mid > dug + 0.3 and mid < orig - 0.2, "then it fills in slowly (%.2f -> %.2f of %.2f)" % [dug, mid, orig])
	run_ticks(p, 120 * 60, func(): return ip())
	ok(absf(t.height_at(x, z) - orig) < 0.05, "and ends up exactly as the level was (%.2f vs %.2f)" % [t.height_at(x, z), orig])
	ok(t.active.size() == 0, "healed cells drop out of the work list")

	# raised earth settles back down
	var base_h: float = t.height_at(6.0, -20.0)
	t.raise_mound(6.0, -20.0, 2.0, 3.0, base_h + 5.0)
	var up: float = t.height_at(6.0, -20.0)
	ok(up > base_h + 4.0, "setup: a spire %.1f m tall" % (up - base_h))
	run_ticks(p, 120 * 12, func(): return ip())
	ok(t.height_at(6.0, -20.0) > up - 0.05, "raised earth stays up for a while")
	run_ticks(p, 120 * 70, func(): return ip())
	ok(t.height_at(6.0, -20.0) < base_h + 0.1, "then it sinks back (%.2f -> %.2f)" % [up, t.height_at(6.0, -20.0)])

	# re-editing a cell restarts its timer
	w.crater(Vector3(x, t.height_at(x, z), z), 4.0, 2.0)
	run_ticks(p, 120 * 8, func(): return ip())
	var d2: float = t.height_at(x, z)
	w.crater(Vector3(x, d2, z), 4.0, 0.5)
	var d3: float = t.height_at(x, z)
	run_ticks(p, 120 * 8, func(): return ip())
	ok(absf(t.height_at(x, z) - d3) < 0.05, "digging again restarts the healing delay")

	# the player standing in a healing crater is carried up with the ground
	w = WorldScript.new(1337)
	w.bots.clear()
	p = SimScript.new(w)
	p.pos = Vector3(0.0, w.height_at(0.0, -20.0), -20.0)
	for k in range(30):
		p.step(TICK, ip())
	w.crater(Vector3(0.0, w.height_at(0.0, -20.0), -20.0), 3.0, 2.0)
	run_ticks(p, 120 * 40, func(): return ip())
	ok(p.on_ground and absf(p.pos.y - w.height_at(0.0, -20.0)) < 0.2 and finite(p), "standing in a healing crater you rise with the ground (y=%.2f)" % p.pos.y)


func test_bots_and_vitals() -> void:
	# bots wander and stay sane
	var w := WorldScript.new(1337)
	var moved := 0
	var finite_ok := true
	for i in range(120 * 12):
		w.update_combat(TICK, null)
	for b in w.bots:
		if b.pos.distance_to(b.home) > 0.5:
			moved += 1
		if not finite_v(b.pos) or absf(b.pos.x) > 200.0 or b.pos.y < -60.0:
			finite_ok = false
	ok(w.bots.size() >= 8 and moved >= 5 and finite_ok, "%d bots wander around their homes without escaping (%d moved)" % [w.bots.size(), moved])

	# death + respawn
	var r := fresh()
	w = r[0]
	var p = r[1]
	var b = add_bot(w, 0.0, -6.0)
	w.damage_bot(b, 500.0, Vector3(0, 6, 0))
	ok(not b.alive and has_wevent(w, "bot_die"), "bot dies at 0 hp")
	run_ticks(p, 120 * 3, func(): return ip())
	ok(not b.alive, "bot stays down for a while")
	run_ticks(p, 120 * 2, func(): return ip())
	ok(b.alive and b.hp == C.BOT_HP and b.pos.distance_to(b.home) < 0.5 and has_wevent(w, "bot_respawn"), "bot respawns at home with full hp")

	# damage dealt fills the ultimate meter
	r = fresh(); w = r[0]; p = r[1]
	b = add_bot(w, 0.0, -6.0)
	var u0: float = p.ult
	w.damage_bot(b, 60.0, Vector3.ZERO)
	p.step(TICK, ip())
	ok(p.ult - u0 >= 60.0 * C.ULT_PER_DAMAGE - 0.01 and w.dealt == 0.0, "60 damage dealt adds %.0f ult (%.1f)" % [60.0 * C.ULT_PER_DAMAGE, p.ult - u0])

	# bots shoot back
	r = fresh(true); w = r[0]; p = r[1]
	var max_bolts := 0
	var lowest := C.PLAYER_HP
	for i in range(120 * 12):
		p.step(TICK, ip())
		max_bolts = maxi(max_bolts, count_proj(w, "bolt"))
		lowest = minf(lowest, p.hp)
	ok(max_bolts > 0 and lowest < C.PLAYER_HP, "bots fire bolts at the player (max %d in flight, hp dipped to %.0f)" % [max_bolts, lowest])

	# vitals
	r = fresh(); w = r[0]; p = r[1]
	p.take_damage(30.0)
	ok(absf(p.hp - 70.0) < 0.01 and has_event(p, "hurt"), "player takes damage")
	run_ticks(p, 120 * 3, func(): return ip())
	ok(absf(p.hp - 70.0) < 0.01, "no regeneration during the %.0f s delay" % C.HP_REGEN_DELAY)
	run_ticks(p, 120 * 5, func(): return ip())
	ok(p.hp > 75.0, "health regenerates afterwards (%.0f)" % p.hp)
	p.take_damage(500.0)
	ok(has_event(p, "died") and p.hp == C.PLAYER_HP and p.pos.distance_to(w.spawn) < 1.0, "dying respawns you at full health")


# ------------------------------------------------------------------ fuzz

func test_fuzz() -> void:
	var w := WorldScript.new(1337)
	var p := SimScript.new(w)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var bad := ""
	for t in range(120 * 120):
		if t % 90 == 0:
			p.yaw += (rng.randf() - 0.5) * 3.0
			p.pitch = clampf(p.pitch + (rng.randf() - 0.5) * 1.5, -1.5, 1.5)
		var i := inp(float(rng.randi_range(-1, 1)), 1.0 if rng.randf() < 0.8 else -1.0, true,
				rng.randf() < 0.2, rng.randf() < 0.6, rng.randf() < 0.04)
		i.scooter_pressed = rng.randf() < 0.004
		i.fire_pressed = rng.randf() < 0.02
		i.fire_held = rng.randf() < 0.5
		i.slice_pressed = rng.randf() < 0.02
		i.barrage_pressed = rng.randf() < 0.02
		i.grab_pressed = rng.randf() < 0.01
		i.armor_pressed = rng.randf() < 0.01
		i.shield_held = rng.randf() < 0.3
		i.suction_held = rng.randf() < 0.3
		i.ult_pressed = rng.randf() < 0.004
		if rng.randf() < 0.004:
			i.element_pressed = "earth" if rng.randf() < 0.5 else "air"
		if rng.randf() < 0.002:
			p.ult = C.ULT_MAX
		if rng.randf() < 0.0005:
			p.pos.y += 15.0                                 # throw the player high so bombs happen too
			p.on_ground = false
		p.step(TICK, i)
		p.events.clear()
		w.events.clear()
		if not finite(p) or p.pos.y < -60.0 or absf(p.pos.x) > 200.0 or absf(p.pos.z) > 200.0:
			bad = "player state at tick %d pos=%s vel=%s" % [t, p.pos, p.vel]
		elif p.chi < -0.001 or p.chi > p.chi_cap() + 0.001 or p.hp <= 0.0 or p.hp > 100.001 or p.ult < -0.001 or p.ult > 100.001:
			bad = "vitals at tick %d chi=%.1f hp=%.1f ult=%.1f" % [t, p.chi, p.hp, p.ult]
		else:
			for b in w.bots:
				if not finite_v(b.pos) or not finite_v(b.vel) or absf(b.pos.x) > 200.0 or absf(b.pos.z) > 200.0 or b.pos.y < -80.0:
					bad = "bot at tick %d pos=%s vel=%s" % [t, b.pos, b.vel]
					break
		if bad != "":
			print("   " + bad)
			break
	ok(bad == "", "fuzz 2 min with every ability, bots, bolts and bombs: all finite, in bounds, vitals in range")
