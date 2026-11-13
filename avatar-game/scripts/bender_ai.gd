extends RefCounted
## Brains for bender bots. "Grunts" (benders mode) throw a couple of basic moves; the duelist (duel mode)
## uses its whole nation kit: air = punch, slice, blast, gust, shield, suction, scooter, breath ult;
## earth = rock, boulder, barrage, pillar, wall, armor, skate, clap ult; water = shards, whip, jet, ice wall, heal, skate, octopus ult.
## Everything here only acts through the world (projectiles, events, direct damage to the player).

const C = preload("res://scripts/config.gd")


static func _cd(b, key: String) -> float:
	return float(b.cds.get(key, 0.0))


static func _set_cd(b, key: String, v: float) -> void:
	b.cds[key] = v


static func _cast(w, b, kind: String) -> void:
	w.events.append({"type": "bot_cast", "bot": b, "kind": kind, "pos": b.pos + Vector3(0.0, 1.2, 0.0)})


static func _aim(b, pl, speed: float) -> Vector3:
	var origin: Vector3 = b.pos + Vector3(0.0, 1.4, 0.0)
	var target: Vector3 = pl.pos + Vector3(0.0, 1.0, 0.0)
	var t := origin.distance_to(target) / maxf(speed, 1.0)
	target += Vector3(pl.vel.x, 0.0, pl.vel.z) * t * 0.55
	return (target - origin).normalized()


static func think(w, b, pl, dt: float) -> void:
	if not b.bender:
		return
	b.armor_t = maxf(0.0, b.armor_t - dt)
	b.shield_t = maxf(0.0, b.shield_t - dt)
	b.scoot_t = maxf(0.0, b.scoot_t - dt)
	b.gcd = maxf(0.0, b.gcd - dt)
	for k in b.cds.keys():
		b.cds[k] = maxf(0.0, float(b.cds[k]) - dt)
	if b.nation == "fire":                                # Inner Fire: falls when it has not attacked for a moment
		b.heat_idle += dt
		if b.heat_idle >= C.HEAT_IDLE and b.heat > 0.0:
			b.heat = maxf(0.0, b.heat - C.HEAT_DECAY * dt)
	if pl == null:
		return
	if b.frozen_t > 0.0:                                  # frozen solid in ice: no moves, no channels
		b.ai_move = Vector3.ZERO
		return
	if b.light_t > 0.0 and not w.bolt_duel.is_empty() and w.bolt_duel["from_player"] and w.bolt_duel["bot"] == b:
		for a in b.pending:                                   # the player's bolt is waiting for an answer: fire back at once
			if a["kind"] == "lightning":
				a["t"] = minf(float(a["t"]), 0.12)
	_run_channels(w, b, pl, dt)
	_run_pending(w, b, pl, dt)
	if b.light_t > 0.0:                                   # standing focused, charging lightning
		b.ai_move = Vector3.ZERO
		return
	if b.stun > 0.0:
		b.ai_move = Vector3.ZERO
		return
	var origin: Vector3 = b.pos + Vector3(0.0, 1.4, 0.0)
	var to: Vector3 = pl.pos + Vector3(0.0, 1.0, 0.0) - origin
	var dist := to.length()
	_steer(w, b, pl, to, dist, dt)
	if dist > (60.0 if b.boss else 30.0) or b.gcd > 0.0 or b.breath_t > 0.0:
		return
	var dir := to / maxf(dist, 0.01)
	if w.raycast_solid(origin + dir * 0.8, dir, maxf(dist - 1.0, 0.1))["hit"]:
		return
	if b.boss:
		if b.nation == "air":
			_air_duelist(w, b, pl, dist)
		elif b.nation == "water":
			_water_duelist(w, b, pl, dist)
		elif b.nation == "fire":
			_fire_duelist(w, b, pl, dist)
		else:
			_earth_duelist(w, b, pl, dist)
	else:
		_grunt(w, b, pl, dist)


# ---- movement for the duelist: hold a preferred range, strafe, and find a way over or around the terrain
static func _steer(w, b, pl, to: Vector3, dist: float, dt: float) -> void:
	if not b.boss:
		return
	var flat := Vector3(to.x, 0.0, to.z)
	if flat.length() < 0.1:
		b.ai_move = Vector3.ZERO
		return
	var fwd := flat.normalized()
	var side := Vector3(-fwd.z, 0.0, fwd.x)
	var lo := 7.0 if b.nation == "air" else (8.0 if b.nation == "water" else (3.5 if b.nation == "fire" else 12.0))
	var hi := 14.0 if b.nation == "air" else (16.0 if b.nation == "water" else (6.5 if b.nation == "fire" else 19.0))
	var radial := 0.0
	if dist > hi:
		radial = 1.0
	elif dist < lo:
		radial = -1.0
	b.strafe_t -= dt
	if b.strafe_t <= 0.0:
		b.strafe_t = randf_range(1.2, 2.6)
		b.strafe_dir = -b.strafe_dir if randf() < 0.7 else b.strafe_dir
	var sp: float = 10.5 if b.scoot_t > 0.0 else 4.6
	if dist > 60.0:
		sp = 9.0                                          # crossing the map: run, don't stroll
	if dist < 2.4:
		radial = 0.0                                      # close enough to trade blows: stand and fight
	if b.nation == "fire" and b.heat >= C.BOT_FIRE_BACKOFF_HEAT:
		radial = -1.0                                     # nearly overheated: back off and cool down
	var want: Vector3 = fwd * radial + side * b.strafe_dir * 0.8
	if want.length() < 0.05:
		b.ai_move = Vector3.ZERO
		b.nav_t = 0.0
		return
	var following := false
	if radial > 0.0 and dist > 20.0:
		var pd: Vector3 = _path_dir(w, b, pl, dt)           # far away: follow a planned route round lakes and cliffs
		if pd != Vector3.ZERO:
			want = pd
			following = true
	var dir: Vector3 = _pick_heading(w, b, want.normalized(), following)
	b.ai_move = dir * sp * minf(1.0, want.length())
	_unstick(w, b, dir, sp, dt)


# Direction to the next waypoint of a route to the player (re-planned every second or so); zero when there is no route.
static func _path_dir(w, b, pl, dt: float) -> Vector3:
	b.path_t -= dt
	var goal := Vector2(pl.pos.x, pl.pos.z)
	if b.path_t <= 0.0 or goal.distance_to(b.path_goal) > 10.0:
		b.path = w.get_nav().find(Vector2(b.pos.x, b.pos.z), goal)
		b.path_t = 1.2
		b.path_goal = goal
	var here := Vector2(b.pos.x, b.pos.z)
	while b.path.size() > 1 and here.distance_to(b.path[0]) < 4.0:
		b.path.remove_at(0)
	if b.path.is_empty():
		return Vector3.ZERO
	var tgt: Vector2 = b.path[0]
	if b.path.size() > 1 and here.distance_to(tgt) < 9.0:
		tgt = b.path[1]
	var d := tgt - here
	if d.length() < 0.5:
		return Vector3.ZERO
	d = d.normalized()
	return Vector3(d.x, 0.0, d.y)


# Can the duelist walk along `c`? 1 = yes, 2 = only by hopping a ledge, 0 = no (cliff, deep water it is not already in, a big drop).
static func _walkable(w, b, c: Vector3) -> int:
	var h0: float = w.height_at(b.pos.x, b.pos.z)
	var p1: Vector3 = b.pos + c * 1.1
	var p2: Vector3 = b.pos + c * 2.8
	var h1: float = w.height_at(p1.x, p1.z)
	var h2: float = w.height_at(p2.x, p2.z)
	if h0 - h2 > 4.5:
		return 0
	var in_water: bool = w.terrain.water_depth_at(b.pos.x, b.pos.z) > 0.6
	if not in_water and (w.terrain.water_depth_at(p1.x, p1.z) > 0.9 or w.terrain.water_depth_at(p2.x, p2.z) > 0.9):
		return 0
	if h1 - h0 <= 1.2 and h2 - h0 <= 3.3:
		return 1
	if h1 - h0 <= 2.0 and h2 - h0 <= 3.6:
		return 2
	return 0


# The wanted heading if it is clear (or only a hop away), otherwise the nearest clear one (the side that last worked first).
static func _pick_heading(w, b, dir: Vector3, follow := false) -> Vector3:
	var r: int = _walkable(w, b, dir)
	if r == 1:
		return dir
	if r == 2 or follow:
		b.hop_want = true            # on a planned route: hop what is in the way instead of wandering off it
		return dir
	for ang in [25.0, 50.0, 80.0, 115.0, 150.0]:
		for sgn in [b.nav_sign, -b.nav_sign]:
			var c: Vector3 = dir.rotated(Vector3.UP, deg_to_rad(float(ang)) * float(sgn))
			if _walkable(w, b, c) == 1:
				b.nav_sign = float(sgn)
				return c
	return dir


# Not getting anywhere? Switch the way round and hop (a gust for air, a stomp for earth) over what is in the way.
static func _unstick(w, b, dir: Vector3, sp: float, dt: float) -> void:
	b.hop_cd = maxf(0.0, b.hop_cd - dt)
	if not b.on_ground or b.stun > 0.0 or b.breath_t > 0.0:
		b.nav_t = 0.0
		return
	if b.hop_want and b.hop_cd <= 0.0:
		b.hop_want = false
		_hop(w, b, dir)
		return
	b.hop_want = false
	if b.nav_t <= 0.0:
		b.nav_pos = b.pos
		b.nav_t = 0.7
		return
	b.nav_t -= dt
	if b.nav_t > 0.0:
		return
	var moved: float = Vector2(b.pos.x - b.nav_pos.x, b.pos.z - b.nav_pos.z).length()
	b.nav_pos = b.pos
	b.nav_t = 0.7
	if moved >= sp * 0.7 * 0.3:
		b.hop_n = 0
		return
	b.nav_sign = -b.nav_sign
	b.strafe_dir = -b.strafe_dir
	if b.hop_cd <= 0.0:
		_hop(w, b, dir)


static func _hop(w, b, dir: Vector3) -> void:
	b.hop_cd = 1.2
	b.hop_n = mini(b.hop_n + 1, 5)
	b.vel.y = 10.5 + 1.0 * float(b.hop_n - 1)          # each failed hop in a row is a bigger one
	b.vel.x = dir.x * 6.5
	b.vel.z = dir.z * 6.5
	b.on_ground = false
	_cast(w, b, "gust" if b.nation == "air" else "stomp")


# ---- scheduled follow-ups (telegraphed attacks land later so the player can react)
static func _run_pending(w, b, pl, dt: float) -> void:
	var i: int = b.pending.size() - 1
	while i >= 0:
		var a: Dictionary = b.pending[i]
		a["t"] = float(a["t"]) - dt
		if float(a["t"]) <= 0.0:
			b.pending.remove_at(i)
			_fire_pending(w, b, pl, a)
		i -= 1


static func _fire_pending(w, b, pl, a: Dictionary) -> void:
	match String(a["kind"]):
		"boulder":
			var d := _aim(b, pl, C.BOULDER_SPEED)
			var p = w.spawn_proj("boulder", "enemy", b.pos + Vector3(0.0, 1.5, 0.0) + d * 1.6, d * C.BOULDER_SPEED + Vector3(0.0, 1.5, 0.0),
					C.BOULDER_LIFE, C.BOULDER_RADIUS, 26.0, C.BOULDER_KNOCKBACK, false, 0.0, b)
			p.grav = C.BOULDER_GRAVITY
			_cast(w, b, "throw")
		"pillar":
			var at: Vector3 = a["at"]
			w.earth_pillar(at)
			var flat := Vector2(pl.pos.x - at.x, pl.pos.z - at.z).length()
			if flat < 3.4 and pl.pos.y - at.y < 3.0:
				pl.take_damage(22.0)
				pl.vel.y = 12.0
				pl.on_ground = false
		"blast":
			var d2: Vector3 = (pl.pos + Vector3(0, 1, 0) - (b.pos + Vector3(0, 1.4, 0))).normalized()
			if b.pos.distance_to(pl.pos) < 9.0:
				pl.take_damage(12.0)
				pl.vel += Vector3(d2.x, 0.0, d2.z) * 15.0 + Vector3.UP * 4.0
				pl.on_ground = false
			w.events.append({"type": "bot_blast", "pos": b.pos + Vector3(0, 1.4, 0), "dir": d2})
			_cast(w, b, "thrust")
		"lightning":
			b.light_t = 0.0
			fire_bot_lightning(w, b, pl, a["dir"])
		"fkick":                                          # the axe kick lands where the lunge ended
			var kd: Vector3 = pl.pos - b.pos
			var kfl := Vector2(kd.x, kd.z).length()
			if b.alive and kfl <= C.FKICK_REACH + 0.8 and absf(kd.y) < 2.2:
				pl.take_damage(C.BOT_KICK_DAMAGE)
				w.roll_burn_player(pl)
				pl.vel += Vector3(kd.x, 0.0, kd.z).normalized() * C.FKICK_KNOCK + Vector3.UP * 4.0
				pl.on_ground = false
			w.events.append({"type": "bot_kick", "pos": b.pos + Vector3(0.0, 1.0, 0.0), "dir": Vector3(-sin(b.yaw), 0.0, -cos(b.yaw))})
		"clap_rise":
			w.events.append({"type": "clap_rise", "pos": a["pos"], "dir": a["dir"], "gap": C.CLAP_GAP})
		"clap_slam":
			var c: Vector3 = a["pos"]
			var d3: Vector3 = a["dir"]
			var rel: Vector3 = pl.pos - c
			var along := rel.x * d3.x + rel.z * d3.z
			var lat := rel.x * (-d3.z) + rel.z * d3.x
			var hit := absf(lat) <= C.CLAP_PAGE - 1.0 and absf(along) <= C.CLAP_HALF_LEN + 1.5
			if hit:
				pl.take_damage(70.0, true)
				pl.vel.y = 8.0
				pl.on_ground = false
			w.events.append({"type": "clap_slam", "pos": c, "dir": d3, "hits": 1 if hit else 0, "len": C.CLAP_HALF_LEN})


# ---- channels (breath, suction)
static func _run_channels(w, b, pl, dt: float) -> void:
	if b.suck_t > 0.0:
		b.suck_t -= dt
		var v: Vector3 = b.pos - pl.pos
		v.y = 0.0
		if v.length() < 22.0 and v.length() > 1.5:
			pl.vel += v.normalized() * 30.0 * dt
		if b.suck_t <= 0.0:
			b.pending.append({"kind": "blast", "t": 0.1})
	if b.light_t > 0.0:
		b.light_t -= dt
	if b.jet_t > 0.0:                                    # a water jet: shoves the player back and hurts a little
		b.jet_t -= dt
		var jo: Vector3 = b.pos + Vector3(0.0, 1.4, 0.0)
		var jto: Vector3 = pl.pos + Vector3(0, 1, 0) - jo
		var jdir := Vector3(-sin(b.yaw), 0.0, -cos(b.yaw))
		if jto.length() < 17.0 and jdir.dot(Vector3(jto.x, 0.0, jto.z).normalized()) > 0.9:
			pl.take_damage(16.0 * dt)
			pl.vel += jdir * 24.0 * dt
		w.events.append({"type": "bot_jet", "pos": jo + jdir * 0.8, "dir": jdir})
	if b.octo_t > 0.0:                                   # octopus form: long water arms lash out at the player
		b.octo_t -= dt
		b.octo_hit_t -= dt
		var oo: Vector3 = b.pos + Vector3(0.0, 1.4, 0.0)
		var oto: Vector3 = pl.pos + Vector3(0, 1, 0) - oo
		if b.octo_hit_t <= 0.0 and oto.length() < 16.0 and not w.raycast_solid(oo + oto.normalized() * 0.8, oto.normalized(), maxf(oto.length() - 1.0, 0.1))["hit"]:
			b.octo_hit_t = 0.9
			pl.take_damage(20.0, true)
			var away := Vector3(oto.x, 0.0, oto.z).normalized()
			pl.vel += away * 10.0 + Vector3.UP * 3.0
			pl.on_ground = false
			w.events.append({"type": "bot_whip", "from": oo, "to": pl.pos + Vector3(0, 1, 0), "big": true})
	if b.breath_t > 0.0:
		b.breath_t -= dt
		var origin: Vector3 = b.pos + Vector3(0.0, 1.4, 0.0)
		var to: Vector3 = pl.pos + Vector3(0, 1, 0) - origin
		var dir := Vector3(-sin(b.yaw), 0.0, -cos(b.yaw))
		if to.length() < 22.0 and dir.dot(Vector3(to.x, 0.0, to.z).normalized()) > 0.8:
			pl.take_damage(38.0 * dt, true)
			pl.vel += dir * 26.0 * dt
		w.events.append({"type": "bot_breath", "pos": origin + dir * 0.8, "dir": dir})


# ---- grunts
static func _grunt(w, b, pl, dist: float) -> void:
	if dist > 26.0 or dist < 2.5:
		return
	b.gcd = randf_range(1.4, 2.8)
	var origin: Vector3 = b.pos + Vector3(0.0, 1.4, 0.0)
	if b.nation == "fire":
		if dist < 7.0 and _cd(b, "whip") <= 0.0:
			_fburst(w, b, pl)
			_set_cd(b, "whip", 2.2)
		else:
			_fpunch(w, b, pl, 6.0)
		return
	if b.nation == "water":
		if dist < 8.0 and _cd(b, "whip") <= 0.0:
			_whip_player(w, b, pl, 8.0)
			_set_cd(b, "whip", 2.0)
		else:
			_shard(w, b, pl, 1)
			_set_cd(b, "shards", 2.2)
		return
	if b.nation == "air":
		if _cd(b, "slice") <= 0.0 and dist > 6.0 and randf() < 0.4:
			var d := _aim(b, pl, C.SLICE_SPEED)
			w.spawn_proj("slice", "enemy", origin + d * 0.9, d * C.SLICE_SPEED, 0.7, C.SLICE_RADIUS * 0.7, 11.0, 6.0, false, 0.95, b)
			_cast(w, b, "slash")
			_set_cd(b, "slice", 5.0)
		elif dist < 15.0:
			var d2 := _aim(b, pl, C.PUNCH_SPEED)
			w.spawn_proj("punch", "enemy", origin + d2 * 0.7, d2 * C.PUNCH_SPEED, C.PUNCH_LIFE, C.PUNCH_RADIUS, 6.0, 5.0, false, 0.0, b)
			_cast(w, b, "punch")
		elif _cd(b, "gust") <= 0.0:
			b.vel.y = 9.0
			b.vel.x += (pl.pos.x - b.pos.x) * 0.2
			_cast(w, b, "gust")
			_set_cd(b, "gust", 6.0)
	else:
		if _cd(b, "boulder") <= 0.0 and dist > 8.0 and randf() < 0.35:
			b.pending.append({"kind": "boulder", "t": 0.55})
			w.events.append({"type": "bot_telegraph", "pos": pl.pos, "radius": 2.0, "dur": 0.6})
			_cast(w, b, "raise")
			_set_cd(b, "boulder", 8.0)
		elif dist < 22.0:
			var d3 := _aim(b, pl, C.ROCK_SPEED)
			var p = w.spawn_proj("rock", "enemy", origin + d3 * 1.0, d3 * C.ROCK_SPEED + Vector3(0.0, 2.5, 0.0), C.ROCK_LIFE,
					C.ROCK_RADIUS, 9.0, 5.0, false, 0.0, b)
			p.grav = C.ROCK_GRAVITY
			_cast(w, b, "throw")


# ---- water helpers
# A quick solid lash that hurts the player if it can reach them.
static func _whip_player(w, b, pl, reach: float, dmg := 11.0) -> void:
	var origin: Vector3 = b.pos + Vector3(0.0, 1.4, 0.0)
	var target: Vector3 = pl.pos + Vector3(0.0, 1.0, 0.0)
	var d := target - origin
	if d.length() <= reach and not w.raycast_solid(origin + d.normalized() * 0.6, d.normalized(), maxf(d.length() - 0.8, 0.1))["hit"]:
		var away := Vector3(d.x, 0.0, d.z).normalized()
		pl.take_damage(dmg)
		pl.vel += away * 6.0 + Vector3.UP * 2.0
		pl.on_ground = false
		w.events.append({"type": "bot_whip", "from": origin, "to": target, "big": false})
	_cast(w, b, "slash")


# A single pointed ice shard, or a fan of five.
static func _shard(w, b, pl, count: int) -> void:
	var origin: Vector3 = b.pos + Vector3(0.0, 1.4, 0.0)
	var base := _aim(b, pl, C.SHARD_SPEED * 0.8)
	var right := base.cross(Vector3.UP)
	right = right.normalized() if right.length() > 0.01 else Vector3.RIGHT
	for k in range(count):
		var dd := (base + right * (float(k) - float(count - 1) * 0.5) * 0.08).normalized()
		w.spawn_proj("shard", "enemy", origin + dd * 1.0, dd * C.SHARD_SPEED * 0.8, C.SHARD_LIFE * 1.6, C.SHARD_RADIUS, 7.0, 3.0, false, 0.0, b)
	_cast(w, b, "thrust")


# ---- fire helpers and the fire duelist
static func _fpunch(w, b, pl, dmg: float) -> void:
	var o: Vector3 = b.pos + Vector3(0.0, 1.4, 0.0)
	var d := _aim(b, pl, C.FPUNCH_SPEED)
	w.spawn_proj("fpunch", "enemy", o + d * 0.8, d * C.FPUNCH_SPEED * 0.6, C.FPUNCH_LIFE * 2.4, C.FPUNCH_RADIUS, dmg, 4.0, false, 0.0, b)
	_cast(w, b, "punch")


# A bot's flame burst: a few slow pellets in a fan (the player can dodge or burn them up).
static func _fburst(w, b, pl) -> void:
	var o: Vector3 = b.pos + Vector3(0.0, 1.4, 0.0)
	var base := _aim(b, pl, C.FBURST_SPEED * 0.6)
	var right := base.cross(Vector3.UP)
	right = right.normalized() if right.length() > 0.01 else Vector3.RIGHT
	for k in range(5):
		var dd := (base + right * (float(k) - 2.0) * 0.07).normalized()
		w.spawn_proj("fpellet", "enemy", o + dd * 0.8, dd * C.FBURST_SPEED * 0.6, C.FBURST_LIFE * 1.6, C.FBURST_RADIUS, C.BOT_BURST_DAMAGE, 2.0, false, 0.0, b)
	_cast(w, b, "thrust")


static func _bot_heat(w, b, h: float) -> void:
	b.heat += h
	b.heat_idle = 0.0
	if b.heat >= C.HEAT_MAX:
		_bot_overheat(w, b)


static func _bot_overheat(w, b) -> void:
	b.heat = C.OVERHEAT_RESET
	b.stun = maxf(b.stun, C.OVERHEAT_TIME)               # overheated: it cannot act for a moment
	b.gcd = C.OVERHEAT_TIME
	w.events.append({"type": "bot_overheat", "pos": b.pos + Vector3(0.0, 1.0, 0.0)})


# The bolt strikes the player. Returns true on a hit (an earth armor soaks it instead).
static func _bolt_player(pl, dir: Vector3, dmg: float) -> bool:
	if pl.armor_on:
		pl.armor_hp = maxf(0.0, pl.armor_hp - C.LIGHT_ARMOR_COST)       # earth armor soaks it
		return false
	pl.take_damage(dmg * (C.LIGHT_WET_MULT if pl.water_depth >= C.SOAK_DEPTH else 1.0), true)
	pl.vel += dir * 8.0 + Vector3.UP * 4.0
	pl.on_ground = false
	return true


# `resolved` = the bolt already waited out a bolt duel window. Otherwise: if the player threw a bolt at this bot while it was
# charging, this bolt throws it back; if the player is charging too, this bolt waits to see whether they answer.
static func fire_bot_lightning(w, b, pl, dir: Vector3, resolved := false) -> void:
	var o: Vector3 = b.pos + Vector3(0.0, 1.4, 0.0)
	var chest: Vector3 = pl.pos + Vector3(0, 1, 0)
	if not resolved:
		if not w.bolt_duel.is_empty() and w.bolt_duel["from_player"] and w.bolt_duel["bot"] == b:
			var bd: Dictionary = w.bolt_duel
			w.bolt_duel = {}
			var rdir: Vector3 = (chest - o).normalized()
			var rhit := _bolt_player(pl, rdir, float(bd["dmg"]))
			w.events.append({"type": "lightning", "from": o, "to": chest, "hit": rhit, "blocked": not rhit})
			w.events.append({"type": "lightning_redirect", "pos": chest})
			return
		if w.bolt_duel.is_empty() and pl.light_t >= C.LIGHT_MIN_CHARGE:
			w.bolt_duel = {"from_player": false, "bot": b, "dir": dir, "dmg": C.BOT_LIGHT_DAMAGE, "t": C.LIGHT_DUEL_WINDOW}
			w.events.append({"type": "lightning_clash", "pos": o})
			return
	var ray: Dictionary = w.raycast_solid(o + dir * 0.5, dir, C.LIGHT_RANGE)
	var reach: float = C.LIGHT_RANGE
	if ray["hit"]:
		reach = o.distance_to(ray["point"])
	var rel: Vector3 = chest - o
	var along := rel.dot(dir)
	var hit := false
	var blocked: bool = bool(ray["hit"])
	var end: Vector3 = o + dir * reach
	if along > 0.5 and along <= reach and (rel - dir * along).length() <= 2.2:
		end = chest
		hit = _bolt_player(pl, dir, C.BOT_LIGHT_DAMAGE)
		blocked = not hit
	w.events.append({"type": "lightning", "from": o, "to": end, "hit": hit, "blocked": blocked})


static func _fire_duelist(w, b, pl, dist: float) -> void:
	var origin: Vector3 = b.pos + Vector3(0.0, 1.4, 0.0)
	b.gcd = randf_range(C.BOT_AI_FIRE_STEP, C.BOT_AI_FIRE_STEP * 2.0)
	if b.ult_charge >= 1.0 and dist < 40.0 and b.light_t <= 0.0:       # lightning: a long, obvious wind-up
		b.ult_charge = 0.0
		b.light_t = C.LIGHT_CHARGE
		var ld: Vector3 = (pl.pos + Vector3(0, 1, 0) - origin).normalized()
		b.pending.append({"kind": "lightning", "t": C.LIGHT_CHARGE, "dir": ld})
		w.events.append({"type": "bot_charge", "pos": b.pos + Vector3(0.0, 1.0, 0.0), "bot": b, "dur": C.LIGHT_CHARGE})
		b.gcd = C.LIGHT_CHARGE + 0.3
		_cast(w, b, "slam")
		return
	if dist < C.RING_RADIUS - 0.5 and _cd(b, "ring") <= 0.0 and b.hp < b.max_hp * 0.75:     # the ring when hurt and you are close
		_set_cd(b, "ring", 9.0)
		b.guard_t = C.RING_GUARD_TIME
		_bot_heat(w, b, C.RING_HEAT)
		if pl.pos.distance_to(b.pos) <= C.RING_RADIUS:
			var away := Vector3(pl.pos.x - b.pos.x, 0.0, pl.pos.z - b.pos.z).normalized()
			pl.take_damage(C.BOT_RING_DAMAGE)
			pl.vel += away * C.RING_KNOCK + Vector3.UP * 3.0
			pl.on_ground = false
		var i: int = w.projectiles.size() - 1
		while i >= 0:
			var p = w.projectiles[i]
			if p.team == "player" and C.PROJ_TOUGHNESS.has(p.kind) and p.pos.distance_to(b.pos + Vector3(0, 1, 0)) <= C.RING_RADIUS:
				w.projectiles.remove_at(i)
			i -= 1
		w.events.append({"type": "fire_ring", "pos": b.pos, "radius": C.RING_RADIUS, "hits": 0})
		_cast(w, b, "slam")
		return
	if dist > 4.0 and dist < 12.0 and _cd(b, "kick") <= 0.0:   # lunge in and kick
		b.scoot_t = C.FKICK_LUNGE_TIME + 0.15
		b.pending.append({"kind": "fkick", "t": 0.45})
		_set_cd(b, "kick", 5.0)
		_bot_heat(w, b, C.FKICK_HEAT)
		_cast(w, b, "thrust")
		return
	if dist > 12.0 and _cd(b, "dash") <= 0.0:             # close in
		b.scoot_t = 0.9
		_set_cd(b, "dash", 4.0)
		_cast(w, b, "thrust")
		return
	if dist < 7.0 and _cd(b, "burst") <= 0.0:
		_fburst(w, b, pl)
		_set_cd(b, "burst", 1.8)
		_bot_heat(w, b, C.FBURST_HEAT)
		return
	if dist > 6.0 and dist < 26.0 and _cd(b, "big") <= 0.0:
		var bd := _aim(b, pl, C.FBIG_SPEED * 0.6)
		w.spawn_proj("fbig", "enemy", origin + bd * 1.0, bd * C.FBIG_SPEED * 0.6, C.FBIG_LIFE * 1.8, C.FBIG_RADIUS, 14.0, 6.0, false, 0.0, b)
		_set_cd(b, "big", 5.0)
		_bot_heat(w, b, C.FBIG_HEAT)
		_cast(w, b, "thrust")
		return
	if dist < 18.0 and _cd(b, "punch") <= 0.0:
		_fpunch(w, b, pl, 8.0)
		_set_cd(b, "punch", 0.7)
		_bot_heat(w, b, C.FPUNCH_HEAT)


# ---- the water duelist: the full kit
static func _water_duelist(w, b, pl, dist: float) -> void:
	b.gcd = randf_range(0.5, 1.0)
	if b.ult_charge >= 1.0 and dist < 24.0:              # octopus form: long arms for a few seconds
		b.ult_charge = 0.0
		b.octo_t = 8.0
		b.octo_hit_t = 0.4
		b.gcd = 1.5
		_cast(w, b, "slam")
		w.events.append({"type": "bot_octo", "pos": b.pos + Vector3(0.0, 1.0, 0.0), "bot": b})
		return
	if b.hp < b.max_hp * 0.5 and _cd(b, "heal") <= 0.0:
		b.hp = minf(b.max_hp, b.hp + float(w._duel_tune["heal_amount"]))
		_set_cd(b, "heal", float(w._duel_tune["heal_cd"]))
		_cast(w, b, "raise")
		w.events.append({"type": "bot_heal", "pos": b.pos + Vector3(0.0, 0.9, 0.0)})
		return
	if b.hp < b.max_hp * 0.8 and dist > 5.0 and _cd(b, "wall") <= 0.0:
		var f := Vector3(pl.pos.x - b.pos.x, 0.0, pl.pos.z - b.pos.z).normalized()
		w.ice_wall(b.pos, f, b)
		_set_cd(b, "wall", 13.0)
		_cast(w, b, "raise")
		return
	if dist < 9.0 and _cd(b, "whip") <= 0.0:
		_whip_player(w, b, pl, 9.0)
		_set_cd(b, "whip", 1.1)
		return
	if dist > 7.0 and dist < 18.0 and _cd(b, "jet") <= 0.0 and randf() < 0.4:
		b.jet_t = 1.3
		_set_cd(b, "jet", 8.0)
		_cast(w, b, "thrust")
		return
	if dist > 16.0 and _cd(b, "skate") <= 0.0:
		b.scoot_t = 3.0
		_set_cd(b, "skate", 9.0)
		return
	if dist < 26.0 and _cd(b, "shards") <= 0.0:
		_shard(w, b, pl, 5)
		_set_cd(b, "shards", 3.4)
		return
	if dist < 24.0 and _cd(b, "bolt") <= 0.0:
		_shard(w, b, pl, 1)
		_set_cd(b, "bolt", 1.3)


# ---- the air duelist: the full kit
static func _air_duelist(w, b, pl, dist: float) -> void:
	var origin: Vector3 = b.pos + Vector3(0.0, 1.4, 0.0)
	b.gcd = randf_range(0.45, 0.9)
	if b.ult_charge >= 1.0 and dist < 20.0:
		b.ult_charge = 0.0
		b.breath_t = 1.7
		b.gcd = 2.2
		_cast(w, b, "thrust")
		return
	if b.hp < b.max_hp * 0.6 and _cd(b, "shield") <= 0.0:
		b.shield_t = 2.6
		_set_cd(b, "shield", 11.0)
		_cast(w, b, "shield")
		return
	if dist < 5.5 and _cd(b, "blast") <= 0.0:
		b.pending.append({"kind": "blast", "t": 0.25})
		_set_cd(b, "blast", 3.0)
		_cast(w, b, "thrust")
		return
	if dist > 7.0 and dist < 18.0 and _cd(b, "suction") <= 0.0 and randf() < 0.35:
		b.suck_t = 1.2
		_set_cd(b, "suction", 9.0)
		_cast(w, b, "thrust")
		return
	if dist > 16.0 and _cd(b, "scoot") <= 0.0:
		b.scoot_t = 3.2
		_set_cd(b, "scoot", 9.0)
		return
	if dist < 12.0 and _cd(b, "gust") <= 0.0 and randf() < 0.5:
		b.vel.y = 11.0
		var side: Vector3 = Vector3(-(pl.pos.z - b.pos.z), 0.0, pl.pos.x - b.pos.x).normalized() * b.strafe_dir * 7.0
		b.vel.x += side.x
		b.vel.z += side.z
		b.on_ground = false
		_set_cd(b, "gust", 4.0)
		_cast(w, b, "gust")
		return
	if dist < 24.0 and _cd(b, "slice") <= 0.0:
		var d := _aim(b, pl, C.SLICE_SPEED)
		w.spawn_proj("slice", "enemy", origin + d * 0.9, d * C.SLICE_SPEED, 0.9, C.SLICE_RADIUS * 0.8, 15.0, 8.0, false, 0.95, b)
		_cast(w, b, "slash")
		_set_cd(b, "slice", 2.4)
		return
	if dist < 20.0:
		var d2 := _aim(b, pl, C.PUNCH_SPEED)
		w.spawn_proj("punch", "enemy", origin + d2 * 0.7, d2 * C.PUNCH_SPEED, C.PUNCH_LIFE * 1.3, C.PUNCH_RADIUS, 7.0, 6.0, false, 0.0, b)
		_cast(w, b, "punch")


# ---- the earth duelist: the full kit
static func _earth_duelist(w, b, pl, dist: float) -> void:
	var origin: Vector3 = b.pos + Vector3(0.0, 1.4, 0.0)
	b.gcd = randf_range(0.55, 1.1)
	if b.ult_charge >= 1.0 and dist < 26.0:
		b.ult_charge = 0.0
		var c := Vector3(pl.pos.x, w.height_at(pl.pos.x, pl.pos.z), pl.pos.z)
		var d := Vector3(pl.pos.x - b.pos.x, 0.0, pl.pos.z - b.pos.z).normalized()
		w.events.append({"type": "clap_start", "pos": c, "dir": d})
		w.events.append({"type": "bot_telegraph", "pos": c, "radius": C.CLAP_PAGE, "dur": 0.85})
		b.pending.append({"kind": "clap_rise", "t": 0.01, "pos": c, "dir": d})
		b.pending.append({"kind": "clap_slam", "t": C.CLAP_RISE + C.CLAP_HOLD + C.CLAP_SLAM * 0.85, "pos": c, "dir": d})
		b.gcd = 2.0
		_cast(w, b, "slam")
		return
	if b.hp < b.max_hp * 0.55 and _cd(b, "armor") <= 0.0:
		b.armor_t = 6.0
		_set_cd(b, "armor", 16.0)
		_cast(w, b, "raise")
		return
	if b.hp < b.max_hp * 0.75 and _cd(b, "wall") <= 0.0 and dist > 6.0:
		var f := Vector2(pl.pos.x - b.pos.x, pl.pos.z - b.pos.z).normalized()
		w.earth_wall_at(Vector2(b.pos.x, b.pos.z) + f * C.WALL_DIST, f, C.WALL_HALF_WIDTH, C.WALL_HEIGHT)
		_set_cd(b, "wall", 15.0)
		_cast(w, b, "stomp")
		return
	if dist < 16.0 and _cd(b, "pillar") <= 0.0:
		var at := Vector3(pl.pos.x + pl.vel.x * 0.5, 0.0, pl.pos.z + pl.vel.z * 0.5)
		at.y = w.height_at(at.x, at.z)
		b.pending.append({"kind": "pillar", "t": 0.75, "at": at})
		w.events.append({"type": "bot_telegraph", "pos": at, "radius": 3.4, "dur": 0.75})
		_set_cd(b, "pillar", 7.0)
		_cast(w, b, "stomp")
		return
	if dist > 18.0 and _cd(b, "skate") <= 0.0:
		b.scoot_t = 3.0
		_set_cd(b, "skate", 9.0)
		return
	if dist < 32.0 and _cd(b, "boulder") <= 0.0:
		b.pending.append({"kind": "boulder", "t": 0.55})
		w.events.append({"type": "bot_telegraph", "pos": pl.pos, "radius": 2.2, "dur": 0.6})
		_set_cd(b, "boulder", 5.0)
		_cast(w, b, "raise")
		return
	if dist < 24.0 and _cd(b, "barrage") <= 0.0:
		var base := _aim(b, pl, C.ROCK_SPEED)
		var right := base.cross(Vector3.UP).normalized()
		for k in range(5):
			var dd := (base + right * (float(k) - 2.0) * 0.07).normalized()
			var p = w.spawn_proj("rock", "enemy", origin + dd * 1.0, dd * C.ROCK_SPEED + Vector3(0.0, 2.0, 0.0), C.ROCK_LIFE,
					C.ROCK_RADIUS, 7.0, 4.0, false, 0.0, b)
			p.grav = C.ROCK_GRAVITY
		_set_cd(b, "barrage", 6.0)
		_cast(w, b, "thrust")
		return
	if dist < 26.0:
		var d4 := _aim(b, pl, C.ROCK_SPEED)
		var p2 = w.spawn_proj("rock", "enemy", origin + d4 * 1.0, d4 * C.ROCK_SPEED + Vector3(0.0, 2.5, 0.0), C.ROCK_LIFE,
				C.ROCK_RADIUS, 11.0, 6.0, false, 0.0, b)
		p2.grav = C.ROCK_GRAVITY
		_cast(w, b, "throw")
