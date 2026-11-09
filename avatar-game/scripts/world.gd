extends RefCounted
## The world: a deformable heightfield (terrain.gd), earthbending jobs, destruction, training bots and
## projectiles. Pure logic, no rendering.

const C = preload("res://scripts/config.gd")
const BenderAI = preload("res://scripts/bender_ai.gd")
const TerrainScript = preload("res://scripts/terrain.gd")

const _OFFS := [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(-1.0, 0.0), Vector2(0.0, 1.0), Vector2(0.0, -1.0)]


class Bot:
	var pos: Vector3
	var vel := Vector3.ZERO
	var home: Vector3
	var hp: float = 100.0
	var alive := true
	var respawn_t := 0.0
	var stun := 0.0
	var frozen_t := 0.0         # frozen solid in ice (waterbending): cannot move or act until it runs out
	var jet_t := 0.0            # a water bot's jet is running
	var octo_t := 0.0           # a water bot is in octopus form
	var octo_hit_t := 0.0
	var wander_to: Vector3
	var wander_t := 0.0
	var fire_cd := 2.0
	var yaw := 0.0
	var flash := 0.0
	var on_ground := false
	var fall_armed := false     # thrown into the air by earthbending: landing hurts
	var air_user := false       # an airbender bot: cushions its fall with an air blast
	var cushion_cd := 0.0
	var bender := false         # uses nation abilities (see bender_ai.gd)
	var boss := false           # the full-kit duelist
	var nation := "earth"
	var max_hp := 100.0
	var armor_t := 0.0
	var shield_t := 0.0
	var scoot_t := 0.0
	var suck_t := 0.0
	var breath_t := 0.0
	var gcd := 1.0
	var ult_charge := 0.0
	var strafe_t := 1.0
	var strafe_dir := 1.0
	var ai_move := Vector3.ZERO
	var cds := {}
	var pending: Array = []
	var fighter := true         # chases and strikes when the player is close
	var melee_cd := 0.0
	var swing_t := -1.0         # >0 while winding up a strike
	var nav_sign := 1.0         # which way round an obstacle the duelist tries first
	var nav_t := 0.0
	var nav_pos := Vector3.ZERO
	var hop_cd := 0.0
	var hop_want := false
	var hop_n := 0
	var path := PackedVector2Array()
	var path_t := 0.0
	var path_goal := Vector2.ZERO

	func _init(p: Vector3) -> void:
		pos = p
		home = p
		wander_to = p
		hp = C.BOT_HP
		max_hp = C.BOT_HP


class Proj:
	var id := 0
	var kind := "punch"      # punch | slice | bolt | rock
	var team := "player"     # player | enemy
	var pos := Vector3.ZERO
	var vel := Vector3.ZERO
	var life := 1.0
	var radius := 0.5
	var damage := 10.0
	var knock := 0.0
	var pierce := false
	var hit: Array = []
	var roll := 0.0
	var grav := 0.0
	var splash := -1.0       # splash damage override (<0 = the kind's default)
	var water := 0.0         # water this projectile carries: it lands on the ground as a puddle where the projectile ends
	var shooter: Bot = null


var seed_value: int = 1337
var size: float = 400.0
var bound: float = 188.0          # invisible arena limit (a little inside the coast of open sea)
var terrain
var bots: Array[Bot] = []
var projectiles: Array[Proj] = []
var walls: Array = []               # standing earth walls that can be grabbed: {a, b}
var held := {}                      # the slab the player is carrying: {c, f, hp, half_w}
var jobs: Array = []                # running earthbending animations (rising spires, waves, quakes)
var ice_walls: Array = []           # standing ice walls: {a, b, orig, ix0.., t}. One hit shatters them
var grabbed: Bot = null             # the enemy held in an octopus arm (Octopus Form, Q)
var grab_t := 0.0
var events: Array = []              # drained by the game each frame (visual / audio cues)
var dealt := 0.0                    # damage dealt by the player since the sim last looked (fills the ult meter)
var summit := Vector3.ZERO          # top of the Air Temple mountain
var temple := Vector2.ZERO
var landmarks: Array[Vector2] = []   # extra tall mountains
var _next_id := 0
var _rng := RandomNumberGenerator.new()
var spawn := Vector3(0.0, 0.0, 4.0)
var spawn_yaw: float = 0.0
var _erode_t := 0.0

var _ground := {"y": 0.0, "nx": 0.0, "ny": 1.0, "nz": 0.0}


func _init(s: int = 1337) -> void:
	seed_value = s
	_rng.seed = s + 99
	terrain = TerrainScript.new()
	terrain.generate(s)
	_build_level()
	terrain.finish_generation()
	for b in bots:
		b.pos.y = height_at(b.pos.x, b.pos.z)
		b.home = b.pos
		b.wander_to = b.pos
	spawn.y = height_at(spawn.x, spawn.z)
	_base_spawn = spawn
	summit.y = height_at(summit.x, summit.z)


# ------------------------------------------------------------------ terrain

func height_at(x: float, z: float) -> float:
	return terrain.height_at(x, z)


func _build_level() -> void:
	# "Stairs": a terraced hill (0.45 m steps you walk up without jumping)
	terrain.raise_terraces(18.0, 0.0, 3.0, 1.2, 0.45, 7, height_at(18.0, 0.0))
	# Pillar chain: five growing hills to climb with jump + mantle
	for i in range(5):
		var x := -16.0 - 9.0 * i
		terrain.raise_mound(x, -10.0, 1.6, 3.0 + 0.6 * i, height_at(x, -10.0) + 2.0 + 1.5 * i, 0.5)
	# Wall line: three ridges (1.2 / 2.2 / 3.2 m) with steep faces: vault and mantle practice
	var wy := [1.2, 2.2, 3.2]
	var wx0 := [-14.0, -2.0, 10.0]
	for k in range(3):
		var xa: float = wx0[k]
		terrain.raise_ridge(xa, 16.0, xa + 8.0, 16.0, 0.8, 1.2, height_at(xa, 16.0) + float(wy[k]),
				height_at(xa + 8.0, 16.0) + float(wy[k]), 0.3)
	# Cliff mesa with a stepping hill: jump off for speed, glide down
	terrain.raise_mound(6.0, -34.0, 5.5, 3.5, height_at(6.0, -34.0) + 6.0, 0.3)
	terrain.raise_mound(6.0, -25.0, 1.3, 2.2, height_at(6.0, -25.0) + 2.4, 0.3)
	# Hills scattered over the whole map, never in water or a river valley
	temple = Vector2(-58.0, 44.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 7
	var placed: Array[Vector2] = [temple]
	var tries := 0
	var hills := 0
	while tries < 700 and hills < 46:
		tries += 1
		var ang := rng.randf() * TAU
		var r := 42.0 + rng.randf() * 130.0
		var x := cos(ang) * r
		var z := sin(ang) * r
		if absf(x) > 170.0 or absf(z) > 170.0 or terrain.water_possible(x, z):
			continue
		if Vector2(x, z).distance_to(temple) < 46.0:
			continue
		var too_close := false
		for q in placed:
			if q.distance_to(Vector2(x, z)) < 26.0:
				too_close = true
				break
		if too_close:
			continue
		placed.append(Vector2(x, z))
		hills += 1
		var rt := 2.0 + rng.randf() * 2.5
		var fl := 4.0 + rng.randf() * 5.0
		var ht := 3.0 + rng.randf() * 7.0
		terrain.raise_mound(x, z, rt, fl, height_at(x, z) + ht, 0.6)
	# Two more tall landmark mountains far from the meadow: climb them for the Air Bomb / Earthquake dive
	var lm := 0
	for a0 in [0.45, 2.2, 3.9, 5.4]:
		if lm >= 2:
			break
		for k in range(12):
			var an: float = float(a0) + 0.21 * float(k)
			var pp := Vector2(cos(an), sin(an)) * (118.0 + 8.0 * float(k % 3))
			var ok := true
			for dx in [-16.0, 0.0, 16.0]:
				for dz in [-16.0, 0.0, 16.0]:
					if terrain.water_possible(pp.x + dx, pp.y + dz) or absf(pp.x + dx) > 172.0 or absf(pp.y + dz) > 172.0:
						ok = false
			if ok and pp.distance_to(temple) > 90.0:
				var pb := height_at(pp.x, pp.y)
				terrain.raise_terraces(pp.x, pp.y, 3.0, 2.2, 1.8, 11, pb)
				terrain.smooth(pp.x, pp.y, 3.0 + 2.2 * 11.0 + 2.0, 2)
				landmarks.append(pp)
				lm += 1
				break
	# Air Temple mountain: stacked terraces ~26 m tall, softened into a hill you can run up (with jumps)
	var tb := height_at(temple.x, temple.y)
	terrain.raise_terraces(temple.x, temple.y, 3.5, 2.5, 2.0, 13, tb)
	terrain.smooth(temple.x, temple.y, 3.5 + 2.5 * 13.0 + 2.0, 2)
	summit = Vector3(temple.x, 0.0, temple.y)
	# Training bots
	for p in [Vector3(0.0, 0.0, -10.0), Vector3(-5.0, 0.0, -8.0), Vector3(5.0, 0.0, -12.0), Vector3(-3.0, 0.0, 9.0),
			Vector3(-8.0, 0.0, 4.0), Vector3(-14.0, 0.0, -2.0), Vector3(10.0, 0.0, -24.0), Vector3(8.0, 0.0, -20.0)]:
		bots.append(Bot.new(p))
	for k in [1, 4, 6]:
		bots[k].air_user = true
	# Bot camps out in the world, on dry ground
	var camps: Array[Vector2] = []
	var ctries := 0
	var crng := RandomNumberGenerator.new()
	crng.seed = seed_value + 13
	while ctries < 400 and camps.size() < 7:
		ctries += 1
		var ca := crng.randf() * TAU
		var cr := 75.0 + crng.randf() * 90.0
		var cp := Vector2(cos(ca), sin(ca)) * cr
		if absf(cp.x) > 165.0 or absf(cp.y) > 165.0 or cp.distance_to(temple) < 30.0:
			continue
		var cok := true
		for dx in [-6.0, 0.0, 6.0]:
			for dz in [-6.0, 0.0, 6.0]:
				if terrain.water_possible(cp.x + dx, cp.y + dz):
					cok = false
		for q in camps:
			if q.distance_to(cp) < 55.0:
				cok = false
		if not cok:
			continue
		camps.append(cp)
		for j in range(4):
			var aa := TAU * float(j) / 4.0 + 0.5
			var nb := Bot.new(Vector3(cp.x + cos(aa) * 4.0, 0.0, cp.y + sin(aa) * 4.0))
			nb.air_user = (j % 3 == 1)
			bots.append(nb)
	# Ponds and small lakes all over the map, the middle included. Never on the start meadow, the duel start pads,
	# a mountain, a bot home or a steep slope.
	var prng := RandomNumberGenerator.new()
	prng.seed = seed_value + 21
	var pond_spots: Array[Vector2] = []
	var ptries := 0
	while ptries < 4000 and pond_spots.size() < C.POND_COUNT:
		ptries += 1
		var pa := prng.randf() * TAU
		var pr := 40.0 + prng.randf() * 110.0
		var pc := Vector2(cos(pa), sin(pa)) * pr
		var prad := 6.0 + prng.randf() * 7.0
		if absf(pc.x) > 155.0 or absf(pc.y) > 155.0 or pc.distance_to(temple) < 55.0 or terrain.water_possible(pc.x, pc.y):
			continue
		if pc.distance_to(Vector2(0.0, 60.0)) < 26.0 or pc.distance_to(Vector2(0.0, -60.0)) < 26.0:
			continue
		var pok := true
		for q in pond_spots:
			if q.distance_to(pc) < 30.0:
				pok = false
		for lmk in landmarks:
			if lmk.distance_to(pc) < 40.0:
				pok = false
		for b1 in bots:
			if Vector2(b1.home.x, b1.home.z).distance_to(pc) < prad + 14.0:
				pok = false
		var hc := height_at(pc.x, pc.y)
		for k in range(8):                               # a flat site: no hill or slope on the rim, no river or sea nearby
			var pa2 := float(k) * TAU / 8.0
			var rp := pc + Vector2(cos(pa2), sin(pa2)) * (prad + 3.0)
			if absf(height_at(rp.x, rp.y) - hc) > 5.0:
				pok = false
		if not pok:
			continue
		terrain.add_pond(pc.x, pc.y, prad, 1.8 + prng.randf() * 1.4)
		pond_spots.append(pc)
	for b0 in bots:
		_default_bots.append({"pos": b0.home, "air": b0.air_user})


# ------------------------------------------------------------------ queries

# Ground under (x, z). Returns a shared scratch dictionary: copy values out immediately.
func ground_at(x: float, z: float, _feet_y: float = 0.0) -> Dictionary:
	var g := _ground
	var e := 0.4
	var h: float = terrain.height_at(x, z)
	var dhx: float = (terrain.height_at(x + e, z) - terrain.height_at(x - e, z)) / (2.0 * e)
	var dhz: float = (terrain.height_at(x, z + e) - terrain.height_at(x, z - e)) / (2.0 * e)
	var l := sqrt(dhx * dhx + 1.0 + dhz * dhz)
	g["y"] = h
	g["nx"] = -dhx / l
	g["ny"] = 1.0 / l
	g["nz"] = -dhz / l
	return g


# Horizontal push that moves a body of this radius out of any terrain wall: ground that stands more than
# a step above the feet is solid. Returns Vector2.ZERO when nothing blocks.
func wall_push(x: float, z: float, feet: float, r: float, step := C.STEP_HEIGHT) -> Vector2:
	var lim := feet + step
	var best := Vector2.ZERO
	var best_d := 0.0
	for o in _OFFS:
		var sx: float = x + o.x * r * 0.9
		var sz: float = z + o.y * r * 0.9
		var hs: float = terrain.height_at(sx, sz)
		if hs <= lim:
			continue
		var g: Vector2 = terrain.gradient_at(sx, sz)
		var gl := g.length()
		var dir := Vector2.ZERO
		if gl > 0.05:
			dir = -g / gl
		else:
			dir = Vector2(-o.x, -o.y)
		if dir == Vector2.ZERO:
			continue
		var dist := minf((hs - lim) / maxf(gl, 0.5) + 0.02, 1.5)
		if dist > best_d:
			best_d = dist
			best = dir * dist
	return best


# p is a PlayerSim (untyped on purpose: keeps the two scripts decoupled). `old` is where it was a tick ago.
func resolve_horizontal(p, old: Vector3) -> void:
	var hc: float = terrain.height_at(p.pos.x, p.pos.z)
	if hc > p.pos.y + 2.5:                       # buried by a rising spire: the surface carries you up
		p.pos.y = hc
		if p.vel.y < 0.0:
			p.vel.y = 0.0
	var climbing: bool = p.get("climbing") == true
	for _i in range(2):
		if climbing:
			break                                  # a fast air scooter runs up steep ground instead of bouncing off it
		var push := wall_push(p.pos.x, p.pos.z, p.pos.y, p.radius)
		if push == Vector2.ZERO:
			break
		p.pos.x += push.x
		p.pos.z += push.y
		var n := push.normalized()
		var into: float = -(p.vel.x * n.x + p.vel.z * n.y)
		if into > 0.0:
			p.vel.x += n.x * into
			p.vel.z += n.y * into
	# Slopes steeper than MAX_WALK_SLOPE cannot be climbed on foot
	var g := ground_at(p.pos.x, p.pos.z)
	var ny: float = g["ny"]
	var slope := sqrt(1.0 - ny * ny) / ny
	if slope > C.MAX_WALK_SLOPE and p.pos.y <= float(g["y"]) + 0.15 and not climbing:
		var dn := Vector2(g["nx"], g["nz"]).normalized()           # downhill
		var up: float = -((p.pos.x - old.x) * dn.x + (p.pos.z - old.z) * dn.y)
		if up > 0.0:
			p.pos.x += dn.x * up
			p.pos.z += dn.y * up
		var upv: float = -(p.vel.x * dn.x + p.vel.z * dn.y)
		if upv > 0.0:
			p.vel.x += dn.x * upv
			p.vel.z += dn.y * upv


func clamp_bounds(p) -> void:
	var b := bound
	if p.pos.x > b:
		p.pos.x = b
		if p.vel.x > 0.0:
			p.vel.x = 0.0
	if p.pos.x < -b:
		p.pos.x = -b
		if p.vel.x < 0.0:
			p.vel.x = 0.0
	if p.pos.z > b:
		p.pos.z = b
		if p.vel.z > 0.0:
			p.vel.z = 0.0
	if p.pos.z < -b:
		p.pos.z = -b
		if p.vel.z < 0.0:
			p.vel.z = 0.0


# Terrain has no overhangs, so there is never a ceiling.
func ceiling_at(_p, _prev_head: float) -> float:
	return 1.0e9


func can_stand(_p) -> bool:
	return true


# Find a ledge in front of the player that can be mantled. Returns {} or {x, y, z}.
# A ledge is a steep face (not walkable) with a walkable top within reach.
func find_ledge(p, fx: float, fz: float) -> Dictionary:
	var r: float = p.radius
	var px: float = p.pos.x
	var py: float = p.pos.y
	var pz: float = p.pos.z
	var ahead := r + 0.3
	var wx := px + fx * ahead
	var wz := pz + fz * ahead
	var dy: float = terrain.height_at(wx, wz) - py
	if dy < C.MANTLE_MIN_HEIGHT or dy > C.MANTLE_REACH:
		return {}
	if terrain.gradient_at(wx, wz).length() <= C.MAX_WALK_SLOPE * 0.9:
		return {}                                   # walkable: just run up it
	var t := ahead
	while t <= ahead + 2.4:
		var qx := px + fx * t
		var qz := pz + fz * t
		var qh: float = terrain.height_at(qx, qz)
		if qh - py >= C.MANTLE_MIN_HEIGHT * 0.7 and qh - py <= C.MANTLE_REACH + 0.5 \
				and terrain.gradient_at(qx, qz).length() < C.MAX_WALK_SLOPE:
			var tx := qx + fx * 0.25
			var tz := qz + fz * 0.25
			return {"x": tx, "y": terrain.height_at(tx, tz), "z": tz}
		t += 0.2
	return {}


# March a ray until it enters terrain. Returns {hit: bool, point: Vector3}.
func raycast_solid(origin: Vector3, dir: Vector3, max_dist: float) -> Dictionary:
	var t := 0.0
	while t <= max_dist:
		var q := origin + dir * t
		if q.y <= terrain.height_at(q.x, q.z):
			return {"hit": true, "point": q}
		t += 0.15
	return {"hit": false, "point": origin + dir * max_dist}


# Where the crosshair lands on the ground: {hit, point (on the surface)}.
func aim_point(origin: Vector3, dir: Vector3, max_dist: float) -> Dictionary:
	var r := raycast_solid(origin, dir, max_dist)
	if r["hit"]:
		var q: Vector3 = r["point"]
		q.y = terrain.height_at(q.x, q.z)
		r["point"] = q
	return r


# ------------------------------------------------------------------ combat: helpers

func inside_solid(q: Vector3) -> bool:
	return q.y <= terrain.height_at(q.x, q.z)


func bot_center(b: Bot) -> Vector3:
	return b.pos + Vector3(0.0, 0.9, 0.0)


# Distance from a point to the bot's capsule axis.
func _bot_dist(b: Bot, q: Vector3) -> float:
	var cy := clampf(q.y, b.pos.y + 0.45, b.pos.y + 1.35)
	return Vector3(q.x - b.pos.x, q.y - cy, q.z - b.pos.z).length()


func spawn_proj(kind: String, team: String, at: Vector3, v: Vector3, life: float, radius: float,
		damage: float, knock: float, pierce := false, roll := 0.0, shooter: Bot = null) -> Proj:
	var p := Proj.new()
	_next_id += 1
	p.id = _next_id
	p.kind = kind
	p.team = team
	p.pos = at
	p.vel = v
	p.life = life
	p.radius = radius
	p.damage = damage
	p.knock = knock
	p.pierce = pierce
	p.roll = roll
	p.shooter = shooter
	projectiles.append(p)
	return p


func damage_bot(b: Bot, dmg: float, knock: Vector3, emit := true) -> void:
	if not b.alive:
		return
	if b.armor_t > 0.0:
		dmg *= 0.3
	b.hp -= dmg
	dealt += dmg
	b.flash = 0.15
	b.stun = maxf(b.stun, 0.35)
	b.vel += knock
	if emit:
		events.append({"type": "bot_hit", "pos": b.pos + Vector3(0.0, 2.1, 0.0), "damage": dmg})
	if b.hp <= 0.0:
		b.alive = false
		b.hp = 0.0
		b.frozen_t = 0.0
		if b == grabbed:
			grabbed = null
		b.respawn_t = C.BOT_RESPAWN
		if b.boss and bot_mode == "duel":
			duel_round_over = true
		events.append({"type": "bot_die", "pos": b.pos + Vector3(0.0, 0.9, 0.0)})


# A short cone in front of the fighter: returns how many bots were struck.
func apply_melee(origin: Vector3, dir: Vector3, reach: float, dmg: float, knock: float, cos_min: float) -> int:
	var hits := 0
	for b in bots:
		if not b.alive:
			continue
		var c := bot_center(b)
		var v := c - origin
		var dist := v.length()
		if dist > reach + C.BOT_RADIUS or dist < 0.01:
			continue
		if dir.dot(v / dist) < cos_min and dist > C.BOT_RADIUS + 0.6:
			continue
		var kdir := Vector3(dir.x, 0.0, dir.z).normalized()
		damage_bot(b, dmg, kdir * knock + Vector3.UP * (2.0 + knock * 0.15))
		hits += 1
		events.append({"type": "melee_hit", "pos": c})
	return hits


func _reflect_at(p: Proj, target: Vector3) -> void:
	p.vel = (target - p.pos).normalized() * p.vel.length() * 1.1
	p.team = "enemy"
	p.damage *= 0.8
	p.life = 2.0
	p.hit.clear()


func _reflect(p: Proj) -> void:
	var tgt: Vector3 = p.pos - p.vel
	if p.shooter != null and p.shooter.alive:
		tgt = bot_center(p.shooter)
	p.vel = (tgt - p.pos).normalized() * p.vel.length() * 1.3
	p.team = "player"
	p.damage *= C.SHIELD_REFLECT_MULT
	p.life = 2.0
	p.hit.clear()
	events.append({"type": "deflect", "pos": p.pos})


# ------------------------------------------------------------------ destruction

# Dig a bowl at `at` (the y is ignored: it sits on the surface). Returns how much ground was removed.
func crater(at: Vector3, r: float, depth: float) -> float:
	var removed: float = terrain.carve_crater(at.x, at.z, r, depth)
	if removed > 0.4:
		events.append({"type": "crater", "pos": Vector3(at.x, terrain.height_at(at.x, at.z), at.z), "radius": r, "amount": removed})
	return removed


func cut_groove(from: Vector3, dir: Vector3, length: float, half_width: float, depth: float) -> float:
	var d := Vector2(dir.x, dir.z)
	if d.length() < 0.01:
		return 0.0
	d = d.normalized()
	var removed: float = terrain.cut_line(from.x, from.z, from.x + d.x * length, from.z + d.y * length, half_width, depth)
	if removed > 0.4:
		events.append({"type": "crater", "pos": Vector3(from.x, terrain.height_at(from.x, from.z), from.z),
				"radius": half_width * 2.0, "amount": removed})
	return removed


# ------------------------------------------------------------------ combat: area attacks

# Instant cone. power 0 = tap-sized blast, 1 = fully charged. Returns bots hit.
func apply_blast(origin: Vector3, dir: Vector3, power: float = 0.0) -> int:
	var rng_range := lerpf(C.BLAST_RANGE, C.BLAST_RANGE_FULL, power)
	var cone := lerpf(C.BLAST_CONE_COS, C.BLAST_CONE_COS_FULL, power)
	var impulse := lerpf(C.BLAST_IMPULSE, C.BLAST_IMPULSE_FULL, power)
	var dmg := lerpf(C.BLAST_DAMAGE, C.BLAST_DAMAGE_FULL, power)
	var hits := 0
	for b in bots:
		if not b.alive:
			continue
		var rel := bot_center(b) - origin
		var dist := rel.length()
		if dist < 0.01 or dist > rng_range:
			continue
		if rel.normalized().dot(dir) < cone:
			continue
		var fall := 1.0 - 0.5 * dist / rng_range
		damage_bot(b, dmg * fall, dir * impulse * fall + Vector3.UP * 4.0)
		hits += 1
	for p in projectiles:
		if p.team != "enemy":
			continue
		var rel2 := p.pos - origin
		var d2 := rel2.length()
		if d2 > 0.01 and d2 <= rng_range and rel2.normalized().dot(dir) >= cone:
			p.vel = dir * p.vel.length() * 1.3
			p.team = "player"
			p.life = 2.0
			p.hit.clear()
			events.append({"type": "deflect", "pos": p.pos})
	if power >= C.BLAST_CRATER_MIN_CHARGE:          # a strong blast scours the ground it hits
		var ray := aim_point(origin, dir, minf(rng_range, C.BLAST_CRATER_RANGE))
		if ray["hit"]:
			crater(ray["point"], C.BLAST_CRATER_RADIUS + 3.2 * power, C.BLAST_CRATER_DEPTH + 2.0 * power)
	return hits


# Radial shockwave (air bomb landing).
func apply_slam(center: Vector3, radius: float, dmg: float, knock: float) -> int:
	var hits := 0
	for b in bots:
		if not b.alive:
			continue
		var rel := bot_center(b) - center
		var dist := rel.length()
		if dist > radius:
			continue
		var fall := 1.0 - 0.6 * dist / radius
		var dir := Vector3(rel.x, 0.0, rel.z)
		dir = dir.normalized() if dir.length() > 0.01 else Vector3.UP
		damage_bot(b, dmg * fall, (dir + Vector3.UP * 0.8) * knock * fall)
		hits += 1
	var i := projectiles.size() - 1
	while i >= 0:
		if projectiles[i].team == "enemy" and projectiles[i].pos.distance_to(center) <= radius:
			projectiles.remove_at(i)
		i -= 1
	events.append({"type": "slam", "pos": center, "radius": radius})
	break_ice_walls_near(center, radius * 0.5)
	crater(center, C.BOMB_CRATER_RADIUS * radius / C.BOMB_RADIUS, C.BOMB_CRATER_DEPTH)
	return hits


# Dragon's Breath: called every tick while the stream is active. Also scours the ground it sweeps over.
func apply_breath(origin: Vector3, dir: Vector3, dt: float) -> int:
	var hits := 0
	for b in bots:
		if not b.alive:
			continue
		var rel := bot_center(b) - origin
		var dist := rel.length()
		if dist < 0.01 or dist > C.BREATH_RANGE:
			continue
		if rel.normalized().dot(dir) < C.BREATH_CONE_COS:
			continue
		var fall := 1.0 - 0.4 * dist / C.BREATH_RANGE
		damage_bot(b, C.BREATH_DAMAGE_PER_SEC * dt * fall, Vector3.ZERO, false)
		b.vel += (dir * C.BREATH_PUSH + Vector3.UP * 14.0) * dt * fall
		b.stun = maxf(b.stun, 0.25)
		hits += 1
	var i := projectiles.size() - 1
	while i >= 0:
		var p := projectiles[i]
		if p.team == "enemy":
			var rel2 := p.pos - origin
			var d2 := rel2.length()
			if d2 > 0.01 and d2 <= C.BREATH_RANGE and rel2.normalized().dot(dir) >= C.BREATH_CONE_COS:
				projectiles.remove_at(i)
		i -= 1
	_erode_t += dt
	if _erode_t >= C.BREATH_ERODE_STEP:
		_erode_t = 0.0
		for yaw_off in [0.0, 0.22, -0.22]:
			var d: Vector3 = dir.rotated(Vector3.UP, yaw_off)
			var ray := aim_point(origin, d, C.BREATH_RANGE)
			if ray["hit"]:
				var q: Vector3 = ray["point"]
				terrain.carve_crater(q.x, q.z, C.BREATH_ERODE_RADIUS, C.BREATH_ERODE_DEPTH)
	return hits


# Air Suction: called every tick while the pull is active. Drags bots to a spot in front of the player.
func apply_suction(origin: Vector3, dir: Vector3, dt: float) -> int:
	var hits := 0
	var hold := origin + dir * C.SUCTION_HOLD_DIST
	for b in bots:
		if not b.alive:
			continue
		var rel := bot_center(b) - origin
		var dist := rel.length()
		if dist < 0.01 or dist > C.SUCTION_RANGE:
			continue
		if rel.normalized().dot(dir) < C.SUCTION_CONE_COS:
			continue
		var to := hold - bot_center(b)
		var d := to.length()
		var want := Vector3.ZERO
		if d > 0.6:
			want = to / d * minf(C.SUCTION_PULL_SPEED, d * 6.0)
		b.vel = b.vel.lerp(want, 1.0 - exp(-9.0 * dt))
		b.stun = maxf(b.stun, 0.2)
		hits += 1
	return hits


# ------------------------------------------------------------------ earthbending

func _bots_in_circle(c: Vector3, r: float) -> Array:
	var out: Array = []
	for b in bots:
		if b.alive and Vector2(b.pos.x - c.x, b.pos.z - c.z).length() <= r:
			out.append(b)
	return out


# A spire of earth bursts up at `at`. Anything standing on it is thrown into the air.
func earth_pillar(at: Vector3, height: float = C.PILLAR_HEIGHT, dur: float = C.PILLAR_DUR) -> void:
	var gy: float = terrain.height_at(at.x, at.z)
	jobs.append({"kind": "mound", "cx": at.x, "cz": at.z, "r_top": C.PILLAR_R_TOP, "r_flank": C.PILLAR_R_FLANK,
			"y0": gy, "y1": gy + height, "t": 0.0, "dur": dur, "rough": 0.45, "orig": terrain.h.duplicate()})
	for b in _bots_in_circle(at, C.PILLAR_R_TOP + C.PILLAR_R_FLANK * 0.6):
		damage_bot(b, C.PILLAR_BOT_DAMAGE, Vector3.ZERO)
	events.append({"type": "earth_rise", "pos": Vector3(at.x, gy, at.z), "radius": C.PILLAR_R_TOP + C.PILLAR_R_FLANK})


# A wall across your path: permanent, blocks bolts, can be climbed, cut with slices or blown apart.
# G picks it up as a shield.
func earth_wall(origin: Vector3, fwd: Vector3) -> void:
	var f := Vector2(fwd.x, fwd.z).normalized()
	earth_wall_at(Vector2(origin.x, origin.z) + f * C.WALL_DIST, f, C.WALL_HALF_WIDTH, C.WALL_HEIGHT)


func earth_wall_at(c: Vector2, f: Vector2, half_w: float, height: float) -> void:
	var perp := Vector2(-f.y, f.x)
	var a := c - perp * half_w
	var b := c + perp * half_w
	var ha: float = terrain.height_at(a.x, a.y)
	var hb: float = terrain.height_at(b.x, b.y)
	jobs.append({"kind": "ridge", "a": a, "b": b, "w_top": C.WALL_W_TOP, "w_flank": C.WALL_W_FLANK,
			"ya0": ha, "ya1": ha + height, "yb0": hb, "yb1": hb + height,
			"t": 0.0, "dur": C.WALL_DUR, "rough": 0.25, "orig": terrain.h.duplicate(), "pin": true})
	events.append({"type": "earth_rise", "pos": Vector3(c.x, terrain.height_at(c.x, c.y), c.y), "radius": half_w})


# Pick up the nearest standing wall as a shield. Returns true when one was grabbed.
func grab_wall(near: Vector3) -> bool:
	if not held.is_empty():
		return false
	var best := -1
	var best_d := C.WALL_GRAB_RANGE
	var q := Vector2(near.x, near.z)
	for k in range(walls.size()):
		var w: Dictionary = walls[k]
		var a: Vector2 = w["a"]
		var b: Vector2 = w["b"]
		var ab := b - a
		var t := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var cp := a + ab * t
		var d := (q - cp).length()
		if d < best_d and terrain.pinned_near(cp.x, cp.y, 1.5):
			best_d = d
			best = k
	if best < 0:
		return false
	var w2: Dictionary = walls[best]
	var a2: Vector2 = w2["a"]
	var b2: Vector2 = w2["b"]
	terrain.release_ridge(a2.x, a2.y, b2.x, b2.y, C.WALL_W_TOP + C.WALL_W_FLANK + 0.5)
	walls.remove_at(best)
	held = {"c": near, "f": Vector2(0.0, -1.0), "hp": C.HELD_HP, "half_w": C.HELD_HALF_WIDTH}
	events.append({"type": "wall_grab", "pos": Vector3((a2.x + b2.x) * 0.5, terrain.height_at((a2.x + b2.x) * 0.5, (a2.y + b2.y) * 0.5), (a2.y + b2.y) * 0.5),
			"radius": C.WALL_HALF_WIDTH})
	return true


# Put the carried slab back into the ground in front of you. A battered slab makes a smaller wall.
func plant_wall(origin: Vector3, fwd: Vector3) -> bool:
	if held.is_empty():
		return false
	var k := clampf(float(held["hp"]) / C.HELD_HP, 0.25, 1.0)
	held = {}
	var f := Vector2(fwd.x, fwd.z).normalized()
	earth_wall_at(Vector2(origin.x, origin.z) + f * C.WALL_DIST, f, lerpf(3.0, C.WALL_HALF_WIDTH, k), lerpf(3.2, C.WALL_HEIGHT, k))
	return true


# Called by the player every tick while carrying a slab.
func set_held_pose(base: Vector3, f: Vector2) -> void:
	if held.is_empty():
		return
	held["c"] = base
	held["f"] = f


func drop_held() -> void:
	held = {}


# Does the carried slab stop this enemy projectile? Returns true when it did.
func _held_blocks(p: Proj) -> bool:
	if held.is_empty():
		return false
	var c: Vector3 = held["c"]
	var f: Vector2 = held["f"]
	var rel := p.pos - c
	var along := rel.x * f.x + rel.z * f.y
	var lat := rel.x * (-f.y) + rel.z * f.x
	if absf(along) > 0.6 + p.radius or absf(lat) > float(held["half_w"]) + p.radius:
		return false
	if rel.y < -0.4 or rel.y > C.HELD_HEIGHT + 0.2:
		return false
	held["hp"] = float(held["hp"]) - p.damage
	events.append({"type": "held_hit", "pos": p.pos})
	if float(held["hp"]) <= 0.0:
		events.append({"type": "held_break", "pos": c, "dir": Vector3(f.x, 0.0, f.y)})
		held = {}
	return true


# Earth Clap: two slabs open from the ground either side of the target and slam together.
func earth_clap(origin: Vector3, look: Vector3) -> Dictionary:
	var eye := origin + Vector3(0.0, C.EYE_STAND, 0.0)
	var ray := aim_point(eye, look, C.CLAP_RANGE)
	var flat := Vector2(look.x, look.z)
	flat = flat.normalized() if flat.length() > 0.01 else Vector2(0.0, -1.0)
	var c := Vector2(origin.x, origin.z) + flat * C.CLAP_RANGE * 0.6
	if ray["hit"]:
		var rp: Vector3 = ray["point"]
		c = Vector2(rp.x, rp.z)
	var snap: Bot = null
	var snap_d := C.CLAP_SNAP
	for b in bots:
		if not b.alive:
			continue
		var d := Vector2(b.pos.x, b.pos.z).distance_to(c)
		if d < snap_d and Vector2(b.pos.x, b.pos.z).distance_to(Vector2(origin.x, origin.z)) < C.CLAP_RANGE * 1.3:
			snap_d = d
			snap = b
	if snap != null:
		c = Vector2(snap.pos.x, snap.pos.z)
	var o2 := Vector2(origin.x, origin.z)
	var dir := (c - o2)
	if dir.length() < 0.5:
		dir = flat
	dir = dir.normalized()
	if o2.distance_to(c) < C.CLAP_MIN_DIST:
		c = o2 + dir * C.CLAP_MIN_DIST
	var perp := Vector2(-dir.y, dir.x)
	var reach := C.CLAP_HALF_LEN + C.CLAP_GAP + C.CLAP_W_TOP + C.CLAP_W_FLANK + 2.0
	var yref: float = terrain.height_at(c.x, c.y)
	jobs.append({"kind": "clap", "c": c, "d": dir, "perp": perp, "t": 0.0, "yref": yref,
			"rose": false, "slammed": false})
	events.append({"type": "clap_start", "pos": Vector3(c.x, yref, c.y), "dir": Vector3(dir.x, 0.0, dir.y)})
	return {"pos": Vector3(c.x, yref, c.y), "dir": Vector3(dir.x, 0.0, dir.y)}


func _clap_lat_along(b: Bot, j: Dictionary) -> Vector2:
	var c: Vector2 = j["c"]
	var d: Vector2 = j["d"]
	var pp: Vector2 = j["perp"]
	var rel := Vector2(b.pos.x, b.pos.z) - c
	return Vector2(rel.dot(pp), rel.dot(d))


func _step_clap(j: Dictionary, dt: float) -> bool:
	j["t"] = float(j["t"]) + dt
	var t: float = j["t"]
	var rise_end: float = C.CLAP_RISE
	var hold_end: float = rise_end + C.CLAP_HOLD
	var slam_end: float = hold_end + C.CLAP_SLAM
	var c: Vector2 = j["c"]
	var d: Vector2 = j["d"]
	var closing := 0.0
	if t > hold_end:
		closing = minf(1.0, (t - hold_end) / C.CLAP_SLAM)
	# the pages lift out of the ground on either side of the spine
	if not bool(j["rose"]):
		j["rose"] = true
		events.append({"type": "clap_rise", "pos": Vector3(c.x, float(j["yref"]), c.y), "dir": Vector3(d.x, 0.0, d.y), "gap": C.CLAP_GAP})
		for b in bots:
			if not b.alive:
				continue
			var la := _clap_lat_along(b, j)
			if absf(la.y) > C.CLAP_HALF_LEN + 1.0 or absf(la.x) > C.CLAP_PAGE:
				continue
			damage_bot(b, C.CLAP_RISE_DAMAGE, Vector3.UP * 9.0)         # tossed by a rising page
			b.fall_armed = true
			b.stun = maxf(b.stun, 1.1)
	# the book slams shut: whatever is between the pages is crushed
	if t >= hold_end and not bool(j["slammed"]) and closing >= 0.8:
		j["slammed"] = true
		var hits := 0
		for b in bots:
			if not b.alive:
				continue
			var la2 := _clap_lat_along(b, j)
			if absf(la2.x) <= C.CLAP_PAGE - 1.0 and absf(la2.y) <= C.CLAP_HALF_LEN + 1.5:
				damage_bot(b, C.CLAP_DAMAGE, Vector3.UP * C.CLAP_KNOCK_UP)
				hits += 1
		events.append({"type": "clap_slam", "pos": Vector3(c.x, float(j["yref"]), c.y), "dir": Vector3(d.x, 0.0, d.y),
				"hits": hits, "len": C.CLAP_HALF_LEN})
	return t >= slam_end


# A line of earth bursting forward along the ground; it hurts and throws whatever it passes under.
func earth_wave(origin: Vector3, dir: Vector3, power: float) -> void:
	var d := Vector2(dir.x, dir.z)
	if d.length() < 0.01:
		return
	d = d.normalized()
	var o := Vector2(origin.x, origin.z) + d * 2.0
	var length := lerpf(C.WAVE_LEN, C.WAVE_LEN_FULL, power)
	var n := int(length / 0.5) + 1
	var ys := PackedFloat32Array()
	for k in range(n + 1):
		var q := o + d * (k * 0.5)
		ys.append(terrain.height_at(q.x, q.y))
	jobs.append({"kind": "wave", "o": o, "d": d, "len": length, "dist": 0.0, "k": 0, "ys": ys, "hits": [],
			"rise": lerpf(C.WAVE_RISE, C.WAVE_RISE_FULL, power), "dmg": lerpf(C.WAVE_DAMAGE, C.WAVE_DAMAGE_FULL, power),
			"launch": lerpf(C.WAVE_LAUNCH, C.WAVE_LAUNCH_FULL, power), "orig": terrain.h.duplicate()})
	events.append({"type": "earth_wave", "pos": Vector3(o.x, terrain.height_at(o.x, o.y), o.y), "dir": Vector3(d.x, 0.0, d.y)})


func earth_quake(center: Vector3) -> void:
	jobs.append({"kind": "quake", "cx": center.x, "cz": center.z, "t": 0.0, "acc": 0.0, "phase": 0.0})
	events.append({"type": "quake_start", "pos": center, "radius": C.QUAKE_RADIUS})


func _update_jobs(dt: float) -> void:
	var i := jobs.size() - 1
	while i >= 0:
		if _step_job(jobs[i], dt):
			jobs.remove_at(i)
		i -= 1


func _step_job(j: Dictionary, dt: float) -> bool:    # true when finished
	match String(j["kind"]):
		"mound":
			j["t"] = float(j["t"]) + dt
			var u := C.ss(0.0, 1.0, minf(1.0, float(j["t"]) / float(j["dur"])))
			terrain.raise_mound(j["cx"], j["cz"], j["r_top"], j["r_flank"], lerpf(float(j["y0"]), float(j["y1"]), u),
					j["rough"], j["orig"])
			return float(j["t"]) >= float(j["dur"])
		"ridge":
			j["t"] = float(j["t"]) + dt
			var u2 := C.ss(0.0, 1.0, minf(1.0, float(j["t"]) / float(j["dur"])))
			var a: Vector2 = j["a"]
			var b: Vector2 = j["b"]
			terrain.raise_ridge(a.x, a.y, b.x, b.y, j["w_top"], j["w_flank"],
					lerpf(float(j["ya0"]), float(j["ya1"]), u2), lerpf(float(j["yb0"]), float(j["yb1"]), u2), j["rough"], j["orig"])
			if float(j["t"]) >= float(j["dur"]):
				if bool(j.get("pin", false)):
					terrain.pin_ridge(a.x, a.y, b.x, b.y, float(j["w_top"]) + float(j["w_flank"]), 0.8)
					walls.append({"a": a, "b": b})
				return true
			return false
		"wave":
			var d: Vector2 = j["d"]
			var o: Vector2 = j["o"]
			var length: float = j["len"]
			var nd := minf(length, float(j["dist"]) + C.WAVE_SPEED * dt)
			var ys: PackedFloat32Array = j["ys"]
			while int(j["k"]) * 0.5 <= nd and int(j["k"]) < ys.size():
				var k: int = j["k"]
				var q := o + d * (k * 0.5)
				terrain.raise_mound(q.x, q.y, 0.7, 1.5, ys[k] + float(j["rise"]), 0.2, j["orig"])
				for bt in bots:
					if bt.alive and not (j["hits"] as Array).has(bt) \
							and Vector2(bt.pos.x - q.x, bt.pos.z - q.y).length() < C.WAVE_HIT_RADIUS:
						(j["hits"] as Array).append(bt)
						damage_bot(bt, float(j["dmg"]), Vector3(d.x, 0.0, d.y) * 6.0 + Vector3.UP * float(j["launch"]) * 0.6)
						bt.fall_armed = true
				if k % 4 == 0:
					events.append({"type": "earth_rise", "pos": Vector3(q.x, ys[k], q.y), "radius": 2.0})
				j["k"] = k + 1
			j["dist"] = nd
			return nd >= length
		"icewall":
			j["t"] = float(j["t"]) + dt
			var ui := C.ss(0.0, 1.0, minf(1.0, float(j["t"]) / float(j["dur"])))
			var ia: Vector2 = j["a"]
			var ib: Vector2 = j["b"]
			terrain.raise_ridge(ia.x, ia.y, ib.x, ib.y, j["w_top"], j["w_flank"],
					lerpf(float(j["ya0"]), float(j["ya1"]), ui), lerpf(float(j["yb0"]), float(j["yb1"]), ui), 0.0, j["orig"])
			if float(j["t"]) >= float(j["dur"]):
				_register_ice_wall(j)
				return true
			return false
		"tide":
			return _step_tide(j, dt)
		"clap":
			return _step_clap(j, dt)
		"quake":
			j["t"] = float(j["t"]) + dt
			j["acc"] = float(j["acc"]) + dt
			var c := Vector3(j["cx"], 0.0, j["cz"])
			if float(j["acc"]) >= C.QUAKE_STEP:
				j["acc"] = 0.0
				var ph1: float = minf(float(j["t"]), C.QUAKE_DURATION) * 3.0
				terrain.heave(c.x, c.z, C.QUAKE_RADIUS, C.QUAKE_AMOUNT, float(j["phase"]), ph1)
				j["phase"] = ph1
			for bt in bots:
				if bt.alive and Vector2(bt.pos.x - c.x, bt.pos.z - c.z).length() <= C.QUAKE_RADIUS:
					damage_bot(bt, C.QUAKE_DPS * dt, Vector3.ZERO, false)
					bt.stun = maxf(bt.stun, 0.3)
					if bt.on_ground and _rng.randf() < dt * 2.5:
						bt.vel.y = 6.5
						bt.vel.x += _rng.randf_range(-2.0, 2.0)
						bt.vel.z += _rng.randf_range(-2.0, 2.0)
			return float(j["t"]) >= C.QUAKE_DURATION
	return true


# ------------------------------------------------------------------ combat: per-tick update

# player is the PlayerSim (or null in tests that only care about bots).
func update_combat(dt: float, player) -> void:
	_update_jobs(dt)
	terrain.heal(dt)
	terrain.tick_water(dt)
	_update_ice_walls(dt)
	_update_bots(dt, player)
	_update_projectiles(dt, player)
	if player != null:                      # the duel enemy's ultimate fills from the damage it deals to you
		var taken: float = player.hurt_acc
		player.hurt_acc = 0.0
		if taken > 0.0:
			for b in bots:
				if b.boss:
					b.ult_charge = minf(1.0, b.ult_charge + taken / C.BOT_ULT_DAMAGE)


func _bot_collide(b: Bot) -> void:
	for _i in range(2):
		var push := wall_push(b.pos.x, b.pos.z, b.pos.y, C.BOT_RADIUS, 1.7 if b.boss else C.STEP_HEIGHT)
		if push == Vector2.ZERO:
			return
		b.pos.x += push.x
		b.pos.z += push.y
		var n := push.normalized()
		var into: float = -(b.vel.x * n.x + b.vel.z * n.y)
		if into > 0.0:
			b.vel.x += n.x * into
			b.vel.z += n.y * into


func _update_bots(dt: float, player) -> void:
	for b in bots:
		b.flash = maxf(0.0, b.flash - dt)
		if not b.alive:
			b.respawn_t -= dt
			if b.respawn_t <= 0.0:
				b.alive = true
				b.hp = b.max_hp
				b.armor_t = 0.0
				b.shield_t = 0.0
				b.pending.clear()
				b.breath_t = 0.0
				b.suck_t = 0.0
				b.pos = b.home
				b.pos.y = height_at(b.home.x, b.home.z)
				b.vel = Vector3.ZERO
				b.stun = 0.0
				b.frozen_t = 0.0
				b.jet_t = 0.0
				b.octo_t = 0.0
				b.fire_cd = _rng.randf_range(C.BOT_FIRE_MIN, C.BOT_FIRE_MAX)
				events.append({"type": "bot_respawn", "pos": b.pos + Vector3(0.0, 0.9, 0.0)})
			continue
		b.stun = maxf(0.0, b.stun - dt)

		# held in an octopus arm: the arm carries it in front of the player until it is thrown or the time runs out
		if b == grabbed and player != null:
			grab_t -= dt
			var hold: Vector3 = player.pos + Vector3(0.0, player.eye_height(), 0.0) + player.look_dir() * C.OCTO_HOLD_DIST
			b.pos = Vector3(hold.x, maxf(hold.y - 0.9, height_at(hold.x, hold.z)), hold.z)
			b.vel = Vector3.ZERO
			b.stun = maxf(b.stun, 0.3)
			b.on_ground = false
			if grab_t <= 0.0:
				events.append({"type": "octo_drop", "pos": b.pos})
				grabbed = null
			continue

		if b.frozen_t > 0.0:                    # frozen solid: it stays where it is
			b.frozen_t = maxf(0.0, b.frozen_t - dt)
			b.stun = maxf(b.stun, 0.2)
			b.vel.x = 0.0
			b.vel.z = 0.0
			if b.frozen_t <= 0.0:
				events.append({"type": "unfreeze", "pos": b.pos + Vector3(0.0, 0.9, 0.0), "bot": b})

		# ground that rose under the bot carries it, or throws it when it rises fast
		var gy0: float = terrain.height_at(b.pos.x, b.pos.z)
		if b.pos.y < gy0 - 0.02:
			var dy := gy0 - b.pos.y
			b.pos.y = gy0
			if dy / dt > C.LIFT_LAUNCH_RATE and not terrain.ice_at(b.pos.x, b.pos.z):
				b.vel.y = maxf(b.vel.y, minf(dy / dt, C.LIFT_LAUNCH_MAX))
				b.on_ground = false

		# wander around home
		var move := Vector3.ZERO
		if b.stun <= 0.0 and b.on_ground:
			b.wander_t -= dt
			if b.wander_t <= 0.0:
				b.wander_to = b.home + Vector3(_rng.randf_range(-6.0, 6.0), 0.0, _rng.randf_range(-6.0, 6.0))
				if terrain.water_depth_at(b.wander_to.x, b.wander_to.z) > 0.9:
					b.wander_to = b.home
				b.wander_t = _rng.randf_range(2.0, 4.0)
			var to := b.wander_to - b.pos
			to.y = 0.0
			if to.length() > 0.5:
				move = to.normalized() * C.BOT_WANDER_SPEED
			if player != null and C.BOT_ATTACKS and b.fighter and b.swing_t < 0.0:
				var pv: Vector3 = player.pos - b.pos
				pv.y = 0.0
				var away_home := Vector2(b.pos.x - b.home.x, b.pos.z - b.home.z).length()
				if pv.length() < C.BOT_CHASE_RANGE and away_home < C.BOT_LEASH and terrain.water_depth_at(b.pos.x, b.pos.z) < 0.9:
					move = Vector3.ZERO if pv.length() < 1.7 else pv.normalized() * C.BOT_CHASE_SPEED
			if b.boss and player != null:
				move = b.ai_move
		if b.on_ground:
			if b.stun > 0.0:
				var f := maxf(0.0, 1.0 - 3.0 * dt)
				b.vel.x *= f
				b.vel.z *= f
			else:
				var k := 1.0 - exp(-6.0 * dt)
				b.vel.x = lerpf(b.vel.x, move.x, k)
				b.vel.z = lerpf(b.vel.z, move.z, k)

		# airbender bots break their own fall with a burst of air
		if b.fall_armed and b.air_user and b.cushion_cd <= 0.0 and not b.on_ground and b.vel.y < -7.0 \
				and b.pos.y - terrain.height_at(b.pos.x, b.pos.z) < C.CUSHION_HEIGHT:
			b.vel.y = -1.5
			b.vel.x *= 0.4
			b.vel.z *= 0.4
			b.cushion_cd = C.CUSHION_COOLDOWN
			b.fall_armed = false
			events.append({"type": "bot_cushion", "pos": b.pos})

		# physics
		b.vel.y -= C.GRAVITY * dt
		b.vel = b.vel.limit_length(70.0)
		b.pos += b.vel * dt
		_bot_collide(b)
		b.pos.x = clampf(b.pos.x, -bound, bound)
		b.pos.z = clampf(b.pos.z, -bound, bound)
		var gy := height_at(b.pos.x, b.pos.z)
		var bdepth: float = terrain.water_depth_at(b.pos.x, b.pos.z)
		if bdepth >= C.SWIM_DEPTH:                  # deep water: bots tread water, no fall damage
			var surf: float = terrain.surface_at(b.pos.x, b.pos.z)
			if b.pos.y < surf - 1.0 or b.vel.y < 0.0:
				if b.pos.y <= surf - 1.0 + 0.5:
					b.pos.y = lerpf(b.pos.y, surf - 1.0, minf(1.0, 8.0 * dt))
					b.vel.y = 0.0
					b.vel.x *= 0.9
					b.vel.z *= 0.9
					if b.fall_armed:
						events.append({"type": "splash", "pos": Vector3(b.pos.x, surf, b.pos.z), "big": true})
					b.fall_armed = false
					gy = b.pos.y
		b.on_ground = false
		if b.pos.y <= gy:
			b.pos.y = gy
			if b.fall_armed and b.vel.y < -C.FALL_SAFE_SPEED:
				var fd := minf(C.FALL_DAMAGE_MAX, (-b.vel.y - C.FALL_SAFE_SPEED) * C.FALL_DAMAGE_PER_MS)
				events.append({"type": "bot_fall", "pos": b.pos, "damage": fd})
				damage_bot(b, fd, Vector3.ZERO)
			if b.vel.y < 0.0:
				b.fall_armed = false
			if b.vel.y < 0.0:
				b.vel.y = 0.0
			b.on_ground = true
		if b.pos.y < -30.0:
			b.pos = b.home
			b.vel = Vector3.ZERO

		# face + shoot the player
		if player != null:
			var dx: float = player.pos.x - b.pos.x
			var dz: float = player.pos.z - b.pos.z
			b.yaw = atan2(-dx, -dz)
			if C.BOT_ATTACKS and b.stun <= 0.0 and not b.bender:
				b.fire_cd -= dt
				if b.fire_cd <= 0.0:
					_bot_try_fire(b, player)
			_bot_melee(b, player, dt, dx, dz)
			BenderAI.think(self, b, player, dt)


func _bot_melee(b: Bot, player, dt: float, dx: float, dz: float) -> void:
	b.melee_cd = maxf(0.0, b.melee_cd - dt)
	if not C.BOT_ATTACKS or not b.fighter:
		return
	if b.stun > 0.0:
		b.swing_t = -1.0                                  # a hit interrupts the wind-up
		return
	var flat := sqrt(dx * dx + dz * dz)
	if b.swing_t < 0.0:
		if b.melee_cd <= 0.0 and flat <= C.BOT_MELEE_RANGE and absf(player.pos.y - b.pos.y) < 2.2:
			b.swing_t = C.BOT_MELEE_WINDUP
			events.append({"type": "bot_swing", "pos": b.pos + Vector3(0.0, 1.2, 0.0), "bot": b})
		return
	b.swing_t -= dt
	if b.swing_t <= 0.0:
		b.swing_t = -1.0
		b.melee_cd = C.BOT_MELEE_COOLDOWN
		if flat <= C.BOT_MELEE_HIT_RANGE and absf(player.pos.y - b.pos.y) < 2.4:
			var away := Vector3(dx, 0.0, dz).normalized()
			player.vel += away * C.BOT_MELEE_PUSH + Vector3.UP * 1.5
			player.take_damage(C.BOT_MELEE_DAMAGE)
			events.append({"type": "bot_melee_hit", "pos": player.pos + Vector3(0.0, 1.2, 0.0)})


func _bot_try_fire(b: Bot, player) -> void:
	var origin := b.pos + Vector3(0.0, 1.4, 0.0)
	var target: Vector3 = player.pos + Vector3(0.0, 1.0, 0.0)
	var d := target - origin
	var dist := d.length()
	if dist > C.BOT_SIGHT or dist < 2.0:
		b.fire_cd = 0.6
		return
	var dir := d / dist
	if raycast_solid(origin + dir * 0.8, dir, dist - 1.0)["hit"]:
		b.fire_cd = 0.6
		return
	spawn_proj("bolt", "enemy", origin + dir * 0.8, dir * C.BOT_BOLT_SPEED, C.BOT_BOLT_LIFE,
			C.BOT_BOLT_RADIUS, C.BOT_BOLT_DAMAGE, 0.0, false, 0.0, b)
	b.fire_cd = _rng.randf_range(C.BOT_FIRE_MIN, C.BOT_FIRE_MAX)
	events.append({"type": "bot_fire", "pos": origin, "bot": b})


# What a projectile does when it runs into the ground.
func _terrain_impact(p: Proj) -> void:
	var surf := Vector3(p.pos.x, terrain.height_at(p.pos.x, p.pos.z), p.pos.z)
	match p.kind:
		"slice":
			cut_groove(surf, p.vel.normalized(), C.SLICE_CUT_LENGTH, C.SLICE_CUT_WIDTH, C.SLICE_CUT_DEPTH)
		"punch":
			crater(surf, 1.0, 0.3)
		"rock":
			crater(surf, C.ROCK_CRATER_RADIUS, C.ROCK_CRATER_DEPTH)
			_rock_splash(p, surf)
		"boulder":
			crater(surf, C.BOULDER_CRATER_RADIUS, C.BOULDER_CRATER_DEPTH)
			_rock_splash(p, surf)


func _rock_splash(p: Proj, at: Vector3) -> void:
	var big := p.kind == "boulder"
	var radius: float = C.BOULDER_SPLASH if big else C.ROCK_SPLASH
	var dmg: float = C.BOULDER_SPLASH_DAMAGE if big else C.ROCK_SPLASH_DAMAGE
	if p.splash >= 0.0:
		dmg = p.splash
	var knock: float = C.BOULDER_KNOCKBACK if big else C.ROCK_KNOCKBACK
	for b in bots:
		if not b.alive or p.hit.has(b):
			continue
		var rel := bot_center(b) - at
		var dist := rel.length()
		if dist <= radius:
			var dir := Vector3(rel.x, 0.0, rel.z)
			dir = dir.normalized() if dir.length() > 0.01 else Vector3.UP
			damage_bot(b, dmg * (1.0 - 0.5 * dist / radius), (dir + Vector3.UP * 0.7) * knock)
	events.append({"type": "rock_burst", "pos": at, "radius": radius})


func _update_projectiles(dt: float, player) -> void:
	var i := projectiles.size() - 1
	while i >= 0:
		var p := projectiles[i]
		p.life -= dt
		var remove := p.life <= 0.0
		if not remove:
			if p.grav > 0.0:
				p.vel.y -= p.grav * dt
			p.pos += p.vel * dt
			if (p.kind == "rock" or p.kind == "boulder" or p.kind == "bolt") and p.pos.y < terrain.surface_at(p.pos.x, p.pos.z) and terrain.water_depth_at(p.pos.x, p.pos.z) > 0.4:
				remove = true
				events.append({"type": "splash", "pos": Vector3(p.pos.x, terrain.surface_at(p.pos.x, p.pos.z), p.pos.z), "big": p.kind == "boulder"})
			elif inside_solid(p.pos):
				remove = true
				events.append({"type": "proj_hit", "pos": p.pos, "kind": p.kind})
				var iced := break_ice_walls_near(p.pos, 0.4 + p.radius) > 0     # an ice wall takes the hit and shatters
				if not iced and (p.team == "player" or p.kind == "rock" or p.kind == "boulder"):
					_terrain_impact(p)
			elif p.team == "player":
				for b in bots:
					if not b.alive or p.hit.has(b):
						continue
					if _bot_dist(b, p.pos) <= C.BOT_RADIUS + p.radius:
						if b.shield_t > 0.0 and player != null:
							_reflect_at(p, player.pos + Vector3(0.0, 1.0, 0.0))
							events.append({"type": "deflect", "pos": p.pos})
							break
						damage_bot(b, p.damage, p.vel.normalized() * p.knock + Vector3.UP * 3.0)
						p.hit.append(b)
						events.append({"type": "proj_hit", "pos": p.pos, "kind": p.kind})
						if p.kind == "rock" or p.kind == "boulder":
							_rock_splash(p, p.pos)
						if p.kind == "boulder":
							crater(Vector3(p.pos.x, terrain.height_at(p.pos.x, p.pos.z), p.pos.z), C.BOULDER_CRATER_RADIUS, C.BOULDER_CRATER_DEPTH)
						if not p.pierce:
							remove = true
							break
			elif player != null:
				var chest: Vector3 = player.pos + Vector3(0.0, 1.0, 0.0)
				if _held_blocks(p):
					remove = true
				elif player.shield_on and p.pos.distance_to(chest) <= C.SHIELD_RADIUS:
					_reflect(p)
				else:
					var ph: float = player.height
					var cy := clampf(p.pos.y, player.pos.y + 0.3, player.pos.y + ph - 0.3)
					var dd := Vector3(p.pos.x - player.pos.x, p.pos.y - cy, p.pos.z - player.pos.z).length()
					if dd <= 0.4 + p.radius:
						player.take_damage(p.damage)
						if p.knock > 0.0:
							player.vel += p.vel.normalized() * p.knock * 0.5 + Vector3.UP * 1.5
							player.on_ground = false
						remove = true
						events.append({"type": "proj_hit", "pos": p.pos, "kind": p.kind})
		if remove:
			if p.water > 0.0:                                     # the water it carried lands here, ready to be gathered again
				deposit_water(Vector3(p.pos.x, terrain.height_at(p.pos.x, p.pos.z), p.pos.z), p.water)
			projectiles.remove_at(i)
		i -= 1


# ------------------------------------------------------------------ waterbending

# Water you can bend from right now: under your feet, close by, or along your line of sight. Returns {found, point}.
# Looking is free: nothing is ever taken from the map's water.
func find_water(feet: Vector3, origin: Vector3, look: Vector3, reach: float, near: float) -> Dictionary:
	if terrain.water_depth_at(feet.x, feet.z) > 0.05 or terrain.ice_at(feet.x, feet.z):
		return {"found": true, "point": Vector3(feet.x, terrain.surface_at(feet.x, feet.z), feet.z)}
	var np = terrain.nearest_water(feet.x, feet.z, near)
	if np != null:
		return {"found": true, "point": np}
	var t := 1.0
	while t <= reach:
		var q := origin + look * t
		if q.y <= terrain.height_at(q.x, q.z):
			break
		if terrain.water_depth_at(q.x, q.z) > 0.12 and q.y <= terrain.surface_at(q.x, q.z) + 0.6:
			return {"found": true, "point": Vector3(q.x, terrain.surface_at(q.x, q.z), q.z)}
		t += 0.6
	return {"found": false, "point": feet}


# A lash of water along a line: everything within `width` of the segment origin .. origin + dir * reach is struck.
func apply_whip(origin: Vector3, dir: Vector3, reach: float, width: float, dmg: float, knock: float) -> int:
	var hits := 0
	for b in bots:
		if not b.alive:
			continue
		var c := bot_center(b)
		var rel := c - origin
		var along := rel.dot(dir)
		if along < 0.0 or along > reach + C.BOT_RADIUS:
			continue
		if (rel - dir * along).length() > width + C.BOT_RADIUS:
			continue
		if raycast_solid(origin + dir * 0.5, dir, maxf(along - 0.5, 0.1))["hit"]:
			continue
		var kdir := Vector3(dir.x, 0.0, dir.z).normalized()
		damage_bot(b, dmg, kdir * knock + Vector3.UP * (2.0 + knock * 0.15))
		hits += 1
		events.append({"type": "melee_hit", "pos": c})
	return hits


# Water Jet: called every tick while the stream runs. It hurts a little and shoves enemies (and bolts) back.
func apply_jet(origin: Vector3, dir: Vector3, dt: float) -> int:
	var hits := 0
	var push := Vector3(dir.x, 0.0, dir.z).normalized()
	for b in bots:
		if not b.alive:
			continue
		var rel := bot_center(b) - origin
		var dist := rel.length()
		if dist < 0.01 or dist > C.JET_RANGE or rel.normalized().dot(dir) < C.JET_CONE_COS:
			continue
		var fall := 1.0 - 0.4 * dist / C.JET_RANGE
		damage_bot(b, C.JET_DPS * dt * fall, Vector3.ZERO, false)
		b.vel += (push * C.JET_PUSH + Vector3.UP * 8.0) * dt * fall
		b.stun = maxf(b.stun, 0.25)
		hits += 1
	var i := projectiles.size() - 1
	while i >= 0:
		var p := projectiles[i]
		if p.team == "enemy":
			var rel2 := p.pos - origin
			var d2 := rel2.length()
			if d2 > 0.01 and d2 <= C.JET_RANGE and rel2.normalized().dot(dir) >= C.JET_CONE_COS:
				projectiles.remove_at(i)
		i -= 1
	return hits


func freeze_bot(b: Bot, secs: float) -> void:
	if not b.alive:
		return
	b.frozen_t = maxf(b.frozen_t, secs)
	b.stun = maxf(b.stun, secs)
	b.vel.x = 0.0
	b.vel.z = 0.0
	b.swing_t = -1.0
	b.breath_t = 0.0
	b.suck_t = 0.0
	b.jet_t = 0.0
	b.octo_t = 0.0
	b.pending.clear()
	events.append({"type": "freeze", "pos": b.pos + Vector3(0.0, 0.9, 0.0), "bot": b, "time": secs})


# E: an ice wall rises in front of you. Used on an enemy about 6 ft in front of you it freezes them instead.
# Returns "freeze", "wall" or "".
func ice_wall(origin: Vector3, fwd: Vector3, caster: Bot = null) -> String:
	var f := Vector2(fwd.x, fwd.z)
	f = f.normalized() if f.length() > 0.01 else Vector2(0.0, -1.0)
	var froze := 0
	for b in bots:
		if not b.alive or b == caster:
			continue
		var rel := Vector2(b.pos.x - origin.x, b.pos.z - origin.z)
		var dist := rel.length()
		if dist > C.ICE_FREEZE_RANGE + C.BOT_RADIUS or absf(b.pos.y - origin.y) > 2.2:
			continue
		if dist > 0.4 and rel.normalized().dot(f) < C.ICE_FREEZE_COS:
			continue
		freeze_bot(b, C.ICE_FREEZE_TIME)
		froze += 1
	if froze > 0:
		return "freeze"
	var c := Vector2(origin.x, origin.z) + f * C.ICE_WALL_DIST
	var perp := Vector2(-f.y, f.x)
	var a := c - perp * C.ICE_WALL_HALF_WIDTH
	var b2 := c + perp * C.ICE_WALL_HALF_WIDTH
	var ha: float = terrain.height_at(a.x, a.y)
	var hb: float = terrain.height_at(b2.x, b2.y)
	jobs.append({"kind": "icewall", "a": a, "b": b2, "w_top": 0.7, "w_flank": 0.9,
			"ya0": ha, "ya1": ha + C.ICE_WALL_HEIGHT, "yb0": hb, "yb1": hb + C.ICE_WALL_HEIGHT,
			"t": 0.0, "dur": C.ICE_WALL_DUR, "orig": terrain.h.duplicate()})
	events.append({"type": "ice_wall_rise", "pos": Vector3(c.x, terrain.height_at(c.x, c.y), c.y), "a": a, "b": b2})
	return "wall"


func _register_ice_wall(j: Dictionary) -> void:
	var a: Vector2 = j["a"]
	var b: Vector2 = j["b"]
	var reach: float = float(j["w_top"]) + float(j["w_flank"]) + 1.0
	var ix0 := int(floor((minf(a.x, b.x) - reach + TerrainScript.HALF) / TerrainScript.CELL))
	var ix1 := int(ceil((maxf(a.x, b.x) + reach + TerrainScript.HALF) / TerrainScript.CELL))
	var iz0 := int(floor((minf(a.y, b.y) - reach + TerrainScript.HALF) / TerrainScript.CELL))
	var iz1 := int(ceil((maxf(a.y, b.y) + reach + TerrainScript.HALF) / TerrainScript.CELL))
	terrain.tint_wall_cells(j["orig"], ix0, iz0, ix1, iz1)
	ice_walls.append({"a": a, "b": b, "orig": j["orig"], "ix0": ix0, "ix1": ix1, "iz0": iz0, "iz1": iz1,
			"t": C.ICE_WALL_LIFE, "w": float(j["w_top"]) + float(j["w_flank"])})


func _update_ice_walls(dt: float) -> void:
	var k := ice_walls.size() - 1
	while k >= 0:
		ice_walls[k]["t"] = float(ice_walls[k]["t"]) - dt
		if float(ice_walls[k]["t"]) <= 0.0:
			_shatter_ice_wall(k, false)
		k -= 1


func _shatter_ice_wall(k: int, struck: bool) -> void:
	var w: Dictionary = ice_walls[k]
	var a: Vector2 = w["a"]
	var b: Vector2 = w["b"]
	terrain.shatter_wall(w["orig"], w["ix0"], w["iz0"], w["ix1"], w["iz1"])
	var mid := (a + b) * 0.5
	events.append({"type": "ice_shatter", "pos": Vector3(mid.x, terrain.height_at(mid.x, mid.y), mid.y), "a": a, "b": b, "struck": struck})
	ice_walls.remove_at(k)


# Anything that lands within `radius` of an ice wall breaks it (one hit). Returns how many walls shattered.
func break_ice_walls_near(center: Vector3, radius: float) -> int:
	if ice_walls.is_empty():
		return 0
	var n := 0
	var q := Vector2(center.x, center.z)
	var k := ice_walls.size() - 1
	while k >= 0:
		var a: Vector2 = ice_walls[k]["a"]
		var b: Vector2 = ice_walls[k]["b"]
		var ab := b - a
		var t := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		if (q - (a + ab * t)).length() <= float(ice_walls[k]["w"]) + radius:
			_shatter_ice_wall(k, true)
			n += 1
		k -= 1
	return n


# Water a waterbender spent lands on the ground here as a puddle that stays for a while: it can be gathered again, and
# it counts as water for free moves. `amount` is the pouch it cost, so a bigger move leaves a bigger puddle.
func deposit_water(at: Vector3, amount: float) -> void:
	if amount < C.PUDDLE_MIN_AMOUNT or absf(at.x) > 195.0 or absf(at.z) > 195.0:
		return
	var r := clampf(0.9 + amount * 0.04, 0.9, 2.4)
	var depth := clampf(0.22 + amount * 0.008, 0.22, 0.5)
	if terrain.flood_disc(at.x, at.z, r, depth, C.PUDDLE_LIFE) > 0:
		events.append({"type": "puddle", "pos": Vector3(at.x, terrain.surface_at(at.x, at.z), at.z), "radius": r})


# Unfreeze: the ice around a point turns back into water. Returns how many vertices thawed.
func thaw_near(c: Vector3, r: float) -> int:
	var n: int = terrain.thaw_area(c.x, c.z, r)
	if n > 0:
		events.append({"type": "thaw", "pos": Vector3(c.x, terrain.surface_at(c.x, c.z), c.z), "radius": r})
	return n


# Ice Skate: water around a point turns to ice. Returns how many vertices froze.
func freeze_water_near(c: Vector3, r: float) -> int:
	var n: int = terrain.freeze_area(c.x, c.z, r)
	if n > 0:
		events.append({"type": "freeze_water", "pos": Vector3(c.x, terrain.surface_at(c.x, c.z), c.z), "radius": r})
	return n


# Hold X near water: the water is pulled up into a huge wave that rolls forward, hurts and shoves what it meets, and
# leaves its water behind (wading depth, staying where it lands). src is where the water was drawn from.
func tidal_wave(origin: Vector3, dir: Vector3, src: Vector3) -> Dictionary:
	var d := Vector2(dir.x, dir.z)
	d = d.normalized() if d.length() > 0.01 else Vector2(0.0, -1.0)
	var o := Vector2(origin.x, origin.z) + d * 2.0
	var k := tide_strength(origin)
	var half := lerpf(C.TIDE_HALF_MIN, C.TIDE_HALF_MAX, k)
	var length := lerpf(C.TIDE_LEN_MIN, C.TIDE_LEN_MAX, k)
	jobs.append({"kind": "tide", "o": o, "d": d, "dist": 0.0, "last": -3.0, "hits": [], "k": k, "half": half, "len": length,
			"dmg": lerpf(C.TIDE_DAMAGE_MIN, C.TIDE_DAMAGE_MAX, k), "depth": lerpf(C.TIDE_FLOOD_MIN, C.TIDE_FLOOD_MAX, k)})
	events.append({"type": "tidal_wave", "pos": Vector3(o.x, terrain.height_at(o.x, o.y), o.y), "dir": Vector3(d.x, 0.0, d.y),
			"src": src, "len": length, "speed": C.TIDE_SPEED, "half": half, "strength": k,
			"radius": lerpf(C.TIDE_BARREL_MIN, C.TIDE_BARREL_MAX, k)})
	return {"strength": k, "len": length, "half": half}


# 0..1: how big a Tidal Wave pulled from here would be. It depends on how much water (or ice) is around you.
func tide_strength(at: Vector3) -> float:
	var amount: float = terrain.water_amount(at.x, at.z, C.TIDE_SOURCE_RADIUS)
	return clampf(sqrt(amount / C.TIDE_SOURCE_FULL), C.TIDE_MIN_STRENGTH, 1.0)


func _step_tide(j: Dictionary, dt: float) -> bool:
	var d: Vector2 = j["d"]
	var o: Vector2 = j["o"]
	var length: float = j["len"]
	var nd := minf(length, float(j["dist"]) + C.TIDE_SPEED * dt)
	var q := o + d * nd
	var half: float = float(j["half"]) * lerpf(1.0, 0.8, nd / length)
	var depth: float = j["depth"]
	while float(j["last"]) + 3.0 <= nd:                  # leave water behind every few metres
		j["last"] = float(j["last"]) + 3.0
		var lq: Vector2 = o + d * float(j["last"])
		terrain.flood_disc(lq.x, lq.y, half, lerpf(depth, depth * C.TIDE_FLOOD_END, float(j["last"]) / length))
	for bt in bots:
		if bt.alive and not (j["hits"] as Array).has(bt) and Vector2(bt.pos.x - q.x, bt.pos.z - q.y).length() < half:
			(j["hits"] as Array).append(bt)
			damage_bot(bt, float(j["dmg"]), Vector3(d.x, 0.0, d.y) * C.TIDE_KNOCK + Vector3.UP * 5.0)
	break_ice_walls_near(Vector3(q.x, 0.0, q.y), half * 0.5)
	j["dist"] = nd
	return nd >= length


# ---- Octopus Form
# Q: grab the nearest enemy in front of you. Returns true when one was caught.
func octo_grab(origin: Vector3, look: Vector3) -> bool:
	if grabbed != null:
		return false
	var best: Bot = null
	var best_d := C.OCTO_GRAB_RANGE
	for b in bots:
		if not b.alive:
			continue
		var rel := bot_center(b) - origin
		var dist := rel.length()
		if dist < 0.01 or dist > best_d or rel.normalized().dot(look) < C.OCTO_GRAB_COS:
			continue
		if raycast_solid(origin + look * 0.5, rel.normalized(), maxf(dist - 0.8, 0.1))["hit"]:
			continue
		best = b
		best_d = dist
	if best == null:
		return false
	grabbed = best
	grab_t = C.OCTO_GRAB_TIME
	best.frozen_t = 0.0
	best.swing_t = -1.0
	best.breath_t = 0.0
	best.suck_t = 0.0
	best.pending.clear()
	events.append({"type": "octo_grab", "pos": bot_center(best), "bot": best})
	return true


# Q again: fling the held enemy the way you are facing.
func octo_throw(look: Vector3) -> void:
	var b := grabbed
	grabbed = null
	if b == null or not b.alive:
		return
	b.vel = look * C.OCTO_THROW_SPEED + Vector3.UP * 5.0
	b.on_ground = false
	b.fall_armed = true
	b.stun = maxf(b.stun, 0.6)
	damage_bot(b, C.OCTO_THROW_DAMAGE, Vector3.ZERO)
	events.append({"type": "octo_throw", "pos": bot_center(b), "dir": look})


func octo_release() -> void:
	grabbed = null


# E: both arms come down from above on a spot in front of you.
func octo_slam(center: Vector3, radius: float, dmg: float) -> int:
	var hits := 0
	for b in bots:
		if not b.alive or b == grabbed:
			continue
		var rel := bot_center(b) - center
		var dist := Vector2(rel.x, rel.z).length()
		if dist > radius or absf(rel.y) > 5.0:
			continue
		var dir := Vector3(rel.x, 0.0, rel.z)
		dir = dir.normalized() if dir.length() > 0.01 else Vector3.UP
		damage_bot(b, dmg * (1.0 - 0.4 * dist / radius), (dir + Vector3.UP * 0.9) * 11.0)
		hits += 1
	break_ice_walls_near(center, radius * 0.5)
	crater(center, 2.6, 0.7)
	events.append({"type": "octo_slam", "pos": center, "radius": radius, "hits": hits})
	return hits


var bot_mode := "fighters"
var bot_nation := "earth"      # the nation of the bots in "benders" mode
var duel_nation := "auto"      # auto = the opposite of the player's nation, or "air" / "earth" / "water"
var _default_bots: Array = []
var _base_spawn := Vector3.ZERO
var duel_round_over := false


# Two dry, gentle spots as far apart as the map allows (player, enemy): opposite sides.
var _sides_cache: Array = []
var _nav = null


func get_nav():
	if _nav == null:
		_nav = preload("res://scripts/nav.gd").new()
		_nav.setup(terrain)
	return _nav


# Two dry spots as far apart as the map allows (player, enemy), joined by a walkable route. Both get a level pad.
func _duel_sides() -> Array:
	if not _sides_cache.is_empty():
		return _sides_cache
	var nav = get_nav()
	var cands: Array[Vector2] = []
	for limit in [8.0]:
		if cands.size() >= 14:
			break
		cands.clear()
		var gx := -160.0
		while gx <= 160.0:
			var gz := -160.0
			while gz <= 160.0:
				var q := Vector2(gx, gz)
				gz += 20.0
				var hq: float = height_at(q.x, q.y)
				var ok: bool = terrain.water_depth_at(q.x, q.y) < 0.05
				var rough := 0.0
				for ring in [5.0, 11.0]:
					for a8 in range(8):
						var o: Vector2 = q + Vector2(cos(float(a8) * TAU / 8.0), sin(float(a8) * TAU / 8.0)) * float(ring)
						if terrain.water_depth_at(o.x, o.y) > 0.05:
							ok = false
						rough = maxf(rough, absf(height_at(o.x, o.y) - hq))
				if ok and rough <= float(limit):
					cands.append(q)
			gx += 20.0
	var pairs: Array = []
	for i in range(cands.size()):
		for j in range(i + 1, cands.size()):
			var dd: float = cands[i].distance_to(cands[j])
			if dd > 120.0:
				pairs.append([dd, i, j])
	pairs.sort_custom(func(a, b): return a[0] > b[0])
	var best: Array = []
	var tried := 0
	for pr in pairs:
		if tried >= 60:
			break
		tried += 1
		var qa: Vector2 = cands[int(pr[1])]
		var qb: Vector2 = cands[int(pr[2])]
		var route: PackedVector2Array = nav.find(qa, qb)
		if route.is_empty():
			continue
		var rlen := 0.0
		var wetn := 0
		var prev := qa
		for wp in route:
			rlen += prev.distance_to(wp)
			prev = wp
			if terrain.water_depth_at(wp.x, wp.y) > 0.9:
				wetn += 1
		if rlen <= float(pr[0]) * 2.6 and float(wetn) <= 0.4 * float(route.size()):
			best = [qa, qb]
			break
	if best.is_empty():
		best = [Vector2(0.0, 60.0), Vector2(0.0, -60.0)]
	else:
		for q in best:
			terrain.make_pad(q.x, q.y, 6.0, 12.0)
	_sides_cache = best
	return best


# fighters: the training dummies that chase and punch. benders: the same bots, each using its nation's basic moves.
# duel: one full-fledged enemy bender (the opposite nation to yours) using its whole kit.
func set_bot_mode(mode: String, player_element := "air", at := Vector3.ZERO, yaw := 0.0) -> void:
	bot_mode = mode
	projectiles.clear()
	bots.clear()
	if mode != "duel":
		spawn = _base_spawn
		spawn_yaw = 0.0
	if mode == "duel":
		# The two fighters start on opposite sides of the map, facing each other across it.
		var sides := _duel_sides()
		var ps: Vector2 = sides[0]
		var es: Vector2 = sides[1]
		spawn = Vector3(ps.x, height_at(ps.x, ps.y), ps.y)
		spawn_yaw = atan2(-(es.x - ps.x), -(es.y - ps.y))
		var pos := Vector3(es.x, height_at(es.x, es.y), es.y)
		var d := Bot.new(pos)
		d.home = pos
		d.wander_to = pos
		d.bender = true
		d.boss = true
		d.nation = duel_nation if duel_nation != "auto" else ("air" if player_element == "earth" else "earth")
		d.air_user = d.nation == "air"
		d.max_hp = 450.0
		d.hp = 450.0
		d.fire_cd = 99999.0
		bots.append(d)
		return
	for e in _default_bots:
		var nb := Bot.new(e["pos"])
		nb.home = nb.pos
		nb.wander_to = nb.pos
		nb.air_user = bool(e["air"])
		if mode == "benders":
			nb.bender = true
			nb.nation = bot_nation
			nb.air_user = bot_nation == "air"
		bots.append(nb)


func reset_bots() -> void:
	projectiles.clear()
	duel_round_over = false
	grabbed = null
	for b in bots:
		b.frozen_t = 0.0
		b.jet_t = 0.0
		b.octo_t = 0.0
		b.pending.clear()
		b.armor_t = 0.0
		b.shield_t = 0.0
		b.scoot_t = 0.0
		b.breath_t = 0.0
		b.gcd = 0.0
		b.ult_charge = 0.0
		for k in b.cds.keys():
			b.cds[k] = 0.0
		b.pos = b.home
		b.pos.y = height_at(b.home.x, b.home.z)
		b.vel = Vector3.ZERO
		b.hp = b.max_hp
		b.alive = true
		b.stun = 0.0
		b.fall_armed = false
		b.cushion_cd = 0.0
		b.fire_cd = _rng.randf_range(C.BOT_FIRE_MIN, C.BOT_FIRE_MAX)
