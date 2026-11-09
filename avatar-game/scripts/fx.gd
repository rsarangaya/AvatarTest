extends Node3D
## Visual effects and per-frame views: bots, projectiles, rings, domes, the scooter bubble,
## shield, charge orb, breath cone. No gameplay logic lives here.

const RigScript = preload("res://scripts/rig.gd")
const C = preload("res://scripts/config.gd")

const AIR := Color(0.86, 0.96, 1.0)
const BOLT := Color(1.0, 0.55, 0.3)
const EARTH := Color(0.62, 0.47, 0.30)
const DUST := Color(0.68, 0.58, 0.44)
const WATER := Color(0.45, 0.78, 1.0)
const ICE := Color(0.82, 0.94, 1.0)
const MAX_DEBRIS := 240
const OCTO_BEADS := 40
const OCTO_LEN := 15.0           # how far the arms are drawn (the hit reach is C.OCTO_REACH)
const WHIP_BEADS := 22

# One shader for every "bubble of moving air": soft rim, scrolling streaks, fadeable.
const BUBBLE_SRC := "
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 tint : source_color = vec4(0.8, 0.95, 1.0, 1.0);
uniform float base_alpha = 0.08;
uniform float rim_alpha = 0.6;
uniform float rim_power = 2.5;
uniform float speed = 3.0;
uniform float stripes = 14.0;
uniform float stripe_alpha = 0.25;
uniform float fade = 1.0;
void fragment() {
	float ndv = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float rim = pow(1.0 - ndv, rim_power);
	float band = sin(UV.x * stripes * 6.2831853 + UV.y * 9.0 - TIME * speed * 6.0);
	band = smoothstep(0.55, 1.0, band);
	ALBEDO = tint.rgb;
	ALPHA = clamp(base_alpha + rim * rim_alpha + band * stripe_alpha * (0.4 + 0.6 * (1.0 - ndv)), 0.0, 0.9) * fade;
}
"

# Billboarded health bar drawn on top of the world.
const BAR_SRC := "
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_test_disabled, shadows_disabled;
uniform float ratio = 1.0;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	float border = step(UV.y, 0.12) + step(0.88, UV.y) + step(UV.x, 0.015) + step(0.985, UV.x);
	vec3 fill = mix(vec3(1.0, 0.3, 0.2), vec3(0.4, 0.9, 0.45), ratio);
	vec3 col = mix(vec3(0.08, 0.06, 0.06), fill, step(UV.x, ratio));
	col = mix(col, vec3(0.0), clamp(border, 0.0, 1.0));
	ALBEDO = col;
	ALPHA = 0.97;
}
"

var world
var sim
var cam: Camera3D

var _bubble_shader := Shader.new()
var _bar_shader := Shader.new()
var _ring_mesh: TorusMesh
var _sphere_mesh: SphereMesh
var _hemi_mesh: SphereMesh
var _crescent_mesh: ArrayMesh
var _effects: Array = []
var _debris: Array = []
var _debris_mesh: BoxMesh
var _debris_mats: Array = []
var _rng := RandomNumberGenerator.new()
var _quake_fx_t := 0.0
var _proj_nodes := {}
var _bot_views := {}
var _time := 0.0

var scooter_shell: MeshInstance3D
var scooter_ball: MeshInstance3D
var shield_node: MeshInstance3D
var charge_orb: MeshInstance3D
var aura: MeshInstance3D
var breath_cone: MeshInstance3D
var breath_core: MeshInstance3D
var skate_slab: MeshInstance3D
var held_node: MeshInstance3D
var foot_rocks: Array = []
var body_rigs: Dictionary = {}
var arm_rigs: Dictionary = {}
var _bot_last_t := 0.0
var charge_rock: MeshInstance3D
var _lump_mesh: SphereMesh
var boulder_node: MeshInstance3D
var _rock_mat: StandardMaterial3D
var _pulls: Array = []
var _stride := 0.0
var _foot_up := 0           # which foot is currently lifted (0 left, 1 right)
var _foot_scale := 0.0
var _pull_t := 0.0
var _claps: Array = []
var armor_plates: Array = []
var _skate_scale := 0.0
var _armor_scale := 0.0
var _slab_dust_t := 0.0
var _held_mat: StandardMaterial3D

# waterbending views
var jet_cone: MeshInstance3D
var jet_core: MeshInstance3D
var octo_arms: Array = []          # two chains of water beads (the octopus arms)
var _octo_scale := 0.0
var _swipe := [0.0, 0.0]           # 1 -> 0 after an arm lashes out
var whip_chains: Array = []        # two solid water whips (alternating), each a chain of beads
var _whip_t := [-1.0, -1.0]        # seconds into each flick (< 0 = idle)
var _whip_side := [-1.0, 1.0]
var _shard_mesh: ArrayMesh
var _shard_mat: StandardMaterial3D
var _beams: Array = []
var _tides: Array = []
var _ice_debris_mats: Array = []
var _slab_mat: StandardMaterial3D
var _ice_slab_mat: StandardMaterial3D
var _jet_t := 0.0
var _heal_fx_t := 0.0
var _ice_dust_t := 0.0

var _scooter_scale := 0.0
var _shield_flash := 0.0
var _suction_t := 0.0
var _breath_t := 0.0
var _wake_t := 0.0
var _trail_t := 0.0
var _charge_t := 0.0


func setup(w, s, c: Camera3D) -> void:
	world = w
	sim = s
	cam = c
	_bubble_shader.code = BUBBLE_SRC
	_bar_shader.code = BAR_SRC
	_ring_mesh = TorusMesh.new()
	_ring_mesh.inner_radius = 0.93
	_ring_mesh.outer_radius = 1.0
	_ring_mesh.rings = 48
	_ring_mesh.ring_segments = 6
	_sphere_mesh = SphereMesh.new()
	_sphere_mesh.radius = 1.0
	_sphere_mesh.height = 2.0
	_sphere_mesh.radial_segments = 40
	_sphere_mesh.rings = 20
	_hemi_mesh = SphereMesh.new()
	_hemi_mesh.radius = 1.0
	_hemi_mesh.height = 1.0
	_hemi_mesh.is_hemisphere = true
	_hemi_mesh.radial_segments = 48
	_hemi_mesh.rings = 16
	_crescent_mesh = _build_crescent()
	_debris_mesh = BoxMesh.new()
	_debris_mesh.size = Vector3.ONE
	for dc in [Color(0.47, 0.34, 0.22), Color(0.40, 0.30, 0.20), Color(0.56, 0.52, 0.46), Color(0.34, 0.30, 0.26)]:
		var m := StandardMaterial3D.new()
		m.albedo_color = dc
		m.roughness = 1.0
		_debris_mats.append(m)

	# Earth: the slab you skate or climb on, the armor plates orbiting you, the carried wall
	var slab_mat := StandardMaterial3D.new()
	slab_mat.albedo_color = Color(0.50, 0.40, 0.30)
	slab_mat.roughness = 1.0
	_slab_mat = slab_mat
	_ice_slab_mat = StandardMaterial3D.new()
	_ice_slab_mat.albedo_color = Color(0.72, 0.89, 0.98, 0.85)
	_ice_slab_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ice_slab_mat.roughness = 0.1
	for ic in [Color(0.80, 0.93, 1.0), Color(0.66, 0.85, 0.97), Color(0.9, 0.97, 1.0)]:
		var im := StandardMaterial3D.new()
		im.albedo_color = ic
		im.roughness = 0.15
		_ice_debris_mats.append(im)
	var slab_mesh := BoxMesh.new()
	slab_mesh.size = Vector3(2.2, 0.32, 2.6)
	skate_slab = MeshInstance3D.new()
	skate_slab.mesh = slab_mesh
	skate_slab.material_override = slab_mat
	skate_slab.visible = false
	add_child(skate_slab)
	_rock_mat = StandardMaterial3D.new()
	_rock_mat.albedo_color = Color(0.46, 0.37, 0.28)
	_rock_mat.roughness = 1.0
	var lump := SphereMesh.new()                     # a faceted lump of rock
	lump.radius = 1.0
	lump.height = 2.0
	lump.radial_segments = 7
	lump.rings = 4
	_lump_mesh = lump
	for k in range(2):
		var fr := MeshInstance3D.new()
		var fm := BoxMesh.new()
		fm.size = Vector3(0.85, 0.34, 1.25)
		fr.mesh = fm
		fr.material_override = slab_mat
		fr.visible = false
		add_child(fr)
		foot_rocks.append(fr)
	charge_rock = MeshInstance3D.new()
	charge_rock.mesh = _lump_mesh
	charge_rock.material_override = _rock_mat
	charge_rock.visible = false
	charge_rock.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(charge_rock)
	boulder_node = MeshInstance3D.new()
	boulder_node.mesh = _lump_mesh
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.5, 0.4, 0.3)
	bmat.roughness = 1.0
	boulder_node.material_override = bmat
	boulder_node.visible = false
	add_child(boulder_node)
	for k in range(10):
		var pm := BoxMesh.new()
		pm.size = Vector3(0.5 + 0.1 * (k % 3), 0.38 + 0.08 * (k % 2), 0.22)
		var plate := MeshInstance3D.new()
		plate.mesh = pm
		plate.material_override = _debris_mats[k % _debris_mats.size()]
		plate.visible = false
		plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(plate)
		armor_plates.append(plate)
	_held_mat = StandardMaterial3D.new()
	_held_mat.albedo_color = Color(0.52, 0.45, 0.36)
	_held_mat.roughness = 1.0
	var held_mesh := BoxMesh.new()
	held_mesh.size = Vector3.ONE
	held_node = MeshInstance3D.new()
	held_node.mesh = held_mesh
	held_node.material_override = _held_mat
	held_node.visible = false
	add_child(held_node)

	# The Air Scooter: a shell around you plus a spinning ball under your feet.
	# Look down while riding and you see the ball and the bubble wall around it.
	scooter_shell = _shell(_sphere_mesh, _bubble(Color(0.75, 0.93, 1.0), 0.05, 0.55, 2.2, 2.0, 10.0, 0.22))
	scooter_ball = _shell(_sphere_mesh, _bubble(Color(0.95, 1.0, 1.0), 0.14, 0.5, 1.6, 5.0, 8.0, 0.6))
	shield_node = _shell(_sphere_mesh, _bubble(Color(0.7, 0.9, 1.0), 0.10, 0.7, 2.2, 1.2, 16.0, 0.22))
	shield_node.scale = Vector3.ONE * C.SHIELD_RADIUS
	charge_orb = _shell(_sphere_mesh, _bubble(Color(0.85, 0.97, 1.0), 0.25, 0.8, 1.5, 6.0, 6.0, 0.6))
	aura = _shell(_sphere_mesh, _bubble(Color(0.9, 0.98, 1.0), 0.12, 0.7, 1.8, 5.0, 10.0, 0.5))
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 1.0
	cone.height = 1.0
	cone.radial_segments = 40
	cone.rings = 1
	breath_cone = _shell(cone, _bubble(Color(0.88, 0.97, 1.0), 0.06, 0.55, 2.0, 3.5, 16.0, 0.42))
	breath_core = _shell(cone, _bubble(Color(1.0, 1.0, 1.0), 0.08, 0.5, 1.6, 6.0, 9.0, 0.6))
	jet_cone = _shell(cone, _bubble(Color(0.4, 0.72, 1.0), 0.16, 0.6, 1.8, 5.0, 14.0, 0.5))
	jet_core = _shell(cone, _bubble(Color(0.75, 0.92, 1.0), 0.2, 0.5, 1.4, 8.0, 8.0, 0.7))
	for side in range(2):                           # the two octopus arms: chains of water beads
		var beads: Array = []
		for k in range(OCTO_BEADS):
			var bead := _shell(_sphere_mesh, _bubble(Color(0.35, 0.68, 1.0), 0.32, 0.7, 1.6, 4.0, 6.0, 0.4))
			beads.append(bead)
		octo_arms.append(beads)
	var whip_mat := _bubble(Color(0.3, 0.62, 1.0), 0.78, 0.9, 1.2, 3.0, 5.0, 0.2)     # an opaque, solid lash
	for side in range(2):
		var wbeads: Array = []
		for k in range(WHIP_BEADS):
			wbeads.append(_shell(_sphere_mesh, whip_mat))
		whip_chains.append(wbeads)
	_build_shard()

	for nat in ["air", "earth", "water"]:
		var br = RigScript.new()
		br.build(nat)
		br.set_view("legs")
		br.visible = false
		add_child(br)
		body_rigs[nat] = br
		var ar = RigScript.new()
		ar.build(nat)
		ar.set_view("arms")
		ar.visible = false
		ar.position = Vector3(0.0, -1.4, -0.3)
		ar.scale = Vector3.ONE * 0.8
		cam.add_child(ar)
		arm_rigs[nat] = ar
	for b in world.bots:
		_bot_views[b] = _build_bot_view(b)
	update_bots()


# ------------------------------------------------------------------ building blocks

func _bubble(tint: Color, base_a: float, rim_a: float, rim_p: float, spd: float, stripes: float, stripe_a: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _bubble_shader
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("base_alpha", base_a)
	m.set_shader_parameter("rim_alpha", rim_a)
	m.set_shader_parameter("rim_power", rim_p)
	m.set_shader_parameter("speed", spd)
	m.set_shader_parameter("stripes", stripes)
	m.set_shader_parameter("stripe_alpha", stripe_a)
	m.set_shader_parameter("fade", 1.0)
	return m


func _flat(color: Color, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	return m


func _inst(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _shell(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := _inst(mesh, mat)
	mi.visible = false
	add_child(mi)
	return mi


# Crescent moon facing the thrower (XY plane, perpendicular to travel), bulging upward, with the
# tips swept back along +Z so it reads as a blade cutting forward. Rolled per throw for a diagonal slash.
func _build_crescent() -> ArrayMesh:
	var radius := 1.65
	var half_angle := 1.15
	var thick := 0.55
	var n := 20
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for k in range(n + 1):
		var t := -1.0 + 2.0 * float(k) / float(n)
		var a := t * half_angle
		var outer := Vector3(sin(a) * radius, cos(a) * radius - radius * 0.62, t * t * 0.55)
		var w := thick * pow(maxf(0.0, 1.0 - t * t), 0.8)
		var inward := Vector3(-sin(a), -cos(a), 0.0)
		verts.append(outer)
		verts.append(outer + inward * w)
		uvs.append(Vector2(float(k) / float(n), 0.0))
		uvs.append(Vector2(float(k) / float(n), 1.0))
	for k in range(n):
		var i0 := k * 2
		idx.append_array(PackedInt32Array([i0, i0 + 1, i0 + 2, i0 + 1, i0 + 3, i0 + 2]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# ------------------------------------------------------------------ rings, domes, labels

# A flat ring that grows (r0 -> r1), optionally travels (at -> to) and fades.
func ring(at: Vector3, normal: Vector3, r1: float, dur: float, delay := 0.0, color := AIR,
		r0 := 0.05, to := Vector3.INF, peak := 0.75, fade_in := false) -> void:
	var mat := _flat(color, 0.0)
	var mi := _inst(_ring_mesh, mat)
	add_child(mi)
	mi.position = at
	mi.quaternion = Quaternion(Vector3.UP, normal.normalized())
	mi.scale = Vector3.ONE * maxf(0.001, r0)
	mi.visible = delay <= 0.0
	_effects.append({"kind": "ring", "node": mi, "mat": mat, "t": -delay, "dur": dur, "from": at, "to": to,
			"has_to": to.is_finite(), "r0": r0, "r1": r1, "peak": peak, "fade_in": fade_in})


# Expanding translucent half-sphere (the Air Bomb shockwave).
func dome(at: Vector3, r1: float, dur: float, tint := Color(0.9, 0.98, 1.0)) -> void:
	var mat := _bubble(tint, 0.1, 0.9, 1.6, 4.0, 12.0, 0.4)
	var mi := _inst(_hemi_mesh, mat)
	add_child(mi)
	mi.position = at
	mi.scale = Vector3.ONE * 0.1
	_effects.append({"kind": "dome", "node": mi, "mat": mat, "t": 0.0, "dur": dur, "from": at, "to": Vector3.INF,
			"has_to": false, "r0": 0.1, "r1": r1, "peak": 1.0, "fade_in": false})


func floating_text(at: Vector3, text: String, color: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.pixel_size = 0.012
	l.font_size = 64
	l.outline_size = 12
	l.modulate = color
	l.outline_modulate = Color(0, 0, 0, 0.85)
	add_child(l)
	l.position = at
	_effects.append({"kind": "label", "node": l, "mat": null, "t": 0.0, "dur": 0.9, "from": at, "to": Vector3.INF,
			"has_to": false, "r0": 1.0, "r1": 1.0, "peak": 1.0, "fade_in": false, "color": color})


func _update_effects(dt: float) -> void:
	var i := _effects.size() - 1
	while i >= 0:
		var e: Dictionary = _effects[i]
		e["t"] = float(e["t"]) + dt
		var node: Node3D = e["node"]
		var u: float = float(e["t"]) / float(e["dur"])
		if u >= 1.0:
			node.queue_free()
			_effects.remove_at(i)
		elif u >= 0.0:
			node.visible = true
			var ease_out := 1.0 - pow(1.0 - u, 2.0)
			var kind: String = e["kind"]
			if kind == "label":
				var from: Vector3 = e["from"]
				node.position = from + Vector3(0.0, 1.6 * ease_out, 0.0)
				var lab := node as Label3D
				var col: Color = e["color"]
				lab.modulate = Color(col.r, col.g, col.b, 1.0 - u * u)
				lab.outline_modulate = Color(0, 0, 0, 0.85 * (1.0 - u * u))
			else:
				var s: float = lerpf(float(e["r0"]), float(e["r1"]), ease_out)
				node.scale = Vector3.ONE * maxf(0.001, s)
				if bool(e["has_to"]):
					var f: Vector3 = e["from"]
					var t: Vector3 = e["to"]
					node.position = f.lerp(t, ease_out)
				var peak: float = e["peak"]
				var a := peak * sin(PI * u) if bool(e["fade_in"]) else peak * (1.0 - u)
				if kind == "ring":
					var m: StandardMaterial3D = e["mat"]
					m.albedo_color.a = a
				else:
					var sm: ShaderMaterial = e["mat"]
					sm.set_shader_parameter("fade", 1.0 - u)
		i -= 1


# Chunks of rock thrown out by earthbending and craters. Cheap boxes with gravity that rest on the ground.
func debris(at: Vector3, count: int, speed: float, size := 0.22, spread := 1.0, up := 1.0, icy := false) -> void:
	var pal: Array = _ice_debris_mats if icy else _debris_mats
	for k in range(count):
		if _debris.size() >= MAX_DEBRIS:
			return
		var mi := MeshInstance3D.new()
		mi.mesh = _debris_mesh
		mi.material_override = pal[_rng.randi() % pal.size()]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var sz := size * _rng.randf_range(0.5, 1.7)
		mi.scale = Vector3(sz, sz * _rng.randf_range(0.6, 1.1), sz * _rng.randf_range(0.7, 1.3))
		add_child(mi)
		var off := Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0)) * spread
		mi.position = at + off + Vector3(0.0, 0.3, 0.0)
		mi.rotation = Vector3(_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU)
		var v := Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(0.7, 1.6) * up, _rng.randf_range(-1.0, 1.0)).normalized() \
				* speed * _rng.randf_range(0.5, 1.0)
		_debris.append({"node": mi, "v": v, "t": 0.0, "life": _rng.randf_range(0.9, 1.6), "base": mi.scale,
				"spin": Vector3(_rng.randf_range(-6.0, 6.0), _rng.randf_range(-6.0, 6.0), _rng.randf_range(-6.0, 6.0))})


func _update_debris(dt: float) -> void:
	var i := _debris.size() - 1
	while i >= 0:
		var d: Dictionary = _debris[i]
		d["t"] = float(d["t"]) + dt
		var node: MeshInstance3D = d["node"]
		if float(d["t"]) >= float(d["life"]):
			node.queue_free()
			_debris.remove_at(i)
		else:
			var v: Vector3 = d["v"]
			if v != Vector3.ZERO:
				v.y -= 20.0 * dt
				node.position += v * dt
				node.rotation += (d["spin"] as Vector3) * dt
				var gy: float = world.height_at(node.position.x, node.position.z)
				if node.position.y < gy + 0.05:
					node.position.y = gy + 0.05
					v = Vector3.ZERO
				d["v"] = v
			var left: float = (float(d["life"]) - float(d["t"])) / 0.35
			if left < 1.0:
				node.scale = (d["base"] as Vector3) * maxf(0.01, left)
		i -= 1


# ------------------------------------------------------------------ events -> visuals

func _rig_event(ev: Dictionary) -> void:
	var ar = arm_rigs[sim.element]
	var br = body_rigs[sim.element]
	match String(ev["type"]):
		"punch":
			ar.trigger("punch", 0.22, 1 if _punch_side else -1)
			_punch_side = not _punch_side
		"slice":
			ar.trigger("slash", 0.3)
		"blast":
			ar.trigger("thrust", 0.38)
		"rock":
			ar.trigger("throw", 0.3)
		"boulder":
			ar.trigger("throw", 0.45)
		"barrage", "wave":
			ar.trigger("thrust", 0.4)
		"wall":
			ar.trigger("raise", 0.5)
		"pillar", "earth_rise":
			if String(ev["type"]) == "pillar":
				ar.trigger("stomp", 0.4)
				br.trigger("stomp", 0.4)
		"gust":
			ar.trigger("gust", 0.3)
		"clap":
			ar.trigger("slam", 0.8)
		"whip":
			ar.trigger("slash", 0.28)
		"shards":
			ar.trigger("thrust", 0.4)
		"ice_wall", "heal":
			ar.trigger("raise", 0.5)
		"octo_swipe":
			ar.trigger("punch", 0.26, -1 if int(ev["side"]) == 0 else 1)
		"octo_slam":
			ar.trigger("slam", 0.7)
		"octo_grab":
			ar.trigger("thrust", 0.3)
		"octo_throw":
			ar.trigger("throw", 0.35)
		"hurt":
			ar.trigger("hurt", 0.25)
		"melee":
			var step: int = int(ev["step"])
			if bool(ev["heavy"]):
				ar.trigger("sweep", 0.45)
				br.trigger("kick", 0.4)
			elif step == 3:
				ar.trigger("punch", 0.3, 1)
				br.trigger("kick", 0.34)
			else:
				ar.trigger("punch", 0.2, -1 if step == 2 else 1)


var _punch_side := true


func on_sim_event(ev: Dictionary, feet: Vector3) -> void:
	_rig_event(ev)
	match String(ev["type"]):
		"gust":
			ring(feet + Vector3(0, 0.15, 0), Vector3.UP, 3.2, 0.45)
			ring(feet + Vector3(0, 0.55, 0), Vector3.UP, 2.2, 0.40, 0.06)
		"skate_on":
			if sim.element == "water":
				ring(feet + Vector3(0, 0.12, 0), Vector3.UP, 2.8, 0.45, 0.0, ICE)
				debris(feet + Vector3(0, 0.2, 0), 8, 5.0, 0.14, 0.8, 1.0, true)
			else:
				ring(feet + Vector3(0, 0.12, 0), Vector3.UP, 2.4, 0.4, 0.0, EARTH)
				debris(feet, 7, 5.0, 0.2)
		"freeze_on":
			ring(feet + Vector3(0, 0.12, 0), Vector3.UP, 3.4, 0.5, 0.0, ICE)
			floating_text(feet + Vector3(0, 2.3, 0), "FREEZE ON", ICE)
		"freeze_off":
			ring(feet + Vector3(0, 0.12, 0), Vector3.UP, 2.6, 0.4, 0.0, WATER)
			floating_text(feet + Vector3(0, 2.3, 0), "THAW", WATER)
		"whip":
			start_whip(bool(ev["flip"]))
			if int(ev["hits"]) > 0:                  # the "blap" where the lash lands
				ring(Vector3(ev["origin"]) + Vector3(ev["dir"]) * (C.WHIP_REACH * 0.8), ev["dir"], 1.6, 0.25, 0.06, WATER, 0.3, Vector3.INF, 0.7)
		"jet_start":
			ring(Vector3(feet) + Vector3(0, 1.4, 0) + sim.look_dir() * 1.2, sim.look_dir(), 0.8, 0.3, 0.0, WATER, 0.2)
		"shards":
			var os: Vector3 = ev["origin"]
			var ds: Vector3 = ev["dir"]
			ring(os + ds * 1.2, ds, 1.0, 0.3, 0.0, ICE, 0.2)
			debris(os + ds * 1.2, 8, 6.0, 0.1, 0.6, 1.0, true)
		"ice_wall":
			if String(ev["what"]) == "freeze":
				ring(feet + Vector3(0, 1.0, 0) + sim.look_dir() * 1.2, Vector3.UP, 2.4, 0.5, 0.0, ICE, 0.4)
				floating_text(feet + Vector3(0, 2.4, 0), "FROZEN", ICE)
			else:
				ring(feet + Vector3(0, 0.12, 0), Vector3.UP, 3.4, 0.4, 0.0, ICE)
		"heal":
			ring(feet + Vector3(0, 0.15, 0), Vector3.UP, 2.0, 0.6, 0.0, Color(0.6, 1.0, 0.85), 0.4)
			ring(feet + Vector3(0, 0.9, 0), Vector3.UP, 1.4, 0.5, 0.1, Color(0.6, 1.0, 0.85), 0.4)
		"gather":
			var gsrc: Vector3 = ev["src"]
			add_pull(gsrc + Vector3(_rng.randf_range(-0.8, 0.8), 0.05, _rng.randf_range(-0.8, 0.8)),
					Vector3(feet) + Vector3(0, 1.1, 0), 0.4, 0.2, false, false, true)
			ring(gsrc + Vector3(0, 0.05, 0), Vector3.UP, 1.6, 0.4, 0.0, WATER, 0.2, Vector3.INF, 0.5)
		"need_water":
			floating_text(feet + Vector3(0, 2.4, 0), "NO WATER NEAR", Color(1.0, 0.8, 0.5))
		"tide":
			ring(feet + Vector3(0, 0.15, 0), Vector3.UP, 5.0, 0.6, 0.0, WATER, 0.5)
			ring(feet + Vector3(0, 1.2, 0), Vector3.UP, 3.0, 0.5, 0.1, ICE, 0.5)
		"octo_start":
			dome(feet + Vector3(0, 0.1, 0), 4.5, 0.6, Color(0.4, 0.72, 1.0))
			for k in range(3):
				ring(feet + Vector3(0, 0.2 + 0.5 * k, 0), Vector3.UP, 3.0 + k, 0.5, k * 0.08, WATER, 0.5)
			floating_text(feet + Vector3(0, 2.5, 0), "OCTOPUS FORM", WATER)
		"octo_end":
			ring(feet + Vector3(0, 0.15, 0), Vector3.UP, 3.0, 0.5, 0.0, WATER, 0.5)
		"octo_swipe":
			_swipe[int(ev["side"])] = 1.0
			var ow: Vector3 = ev["origin"]
			var dw: Vector3 = ev["dir"]
			ring(ow + dw * 4.0, dw, 3.2, 0.3, 0.0, WATER, 0.6, ow + dw * 8.0, 0.6)
		"octo_grab":
			ring(Vector3(ev["origin"]) + Vector3(ev["dir"]) * 3.0, ev["dir"], 2.4, 0.3, 0.0, WATER, 0.5)
		"octo_throw":
			var ot: Vector3 = ev["origin"]
			var dt2: Vector3 = ev["dir"]
			for k in range(3):
				ring(ot + dt2 * (2.0 + 2.5 * k), dt2, 2.0 + k, 0.35, k * 0.05, WATER, 0.5)
		"elevator_on":
			ring(feet + Vector3(0, 0.12, 0), Vector3.UP, 2.6, 0.45, 0.0, EARTH)
			debris(feet, 10, 6.0, 0.26)
		"elevator_lip":
			ring(feet + Vector3(0, 0.12, 0), Vector3.UP, 3.0, 0.4, 0.0, DUST)
			debris(feet, 8, 7.0, 0.22)
		"armor_on":
			ring(feet + Vector3(0, 0.15, 0), Vector3.UP, 2.2, 0.45, 0.0, EARTH)
			ring(feet + Vector3(0, 1.0, 0), Vector3.UP, 1.5, 0.4, 0.06, EARTH)
			debris(feet + Vector3(0, 0.6, 0), 10, 3.5, 0.18)
		"armor_off":
			ring(feet + Vector3(0, 0.15, 0), Vector3.UP, 1.6, 0.3, 0.0, DUST, 0.3)
		"armor_hit":
			debris(feet + Vector3(0, 1.0, 0), 3, 4.0, 0.12)
		"armor_break":
			ring(feet + Vector3(0, 1.0, 0), Vector3.UP, 2.6, 0.4, 0.0, EARTH)
			debris(feet + Vector3(0, 1.0, 0), 16, 8.0, 0.2)
			floating_text(feet + Vector3(0, 2.3, 0), "ARMOR BROKEN", Color(0.9, 0.7, 0.4))
		"grab":
			ring(feet + Vector3(0, 0.12, 0), Vector3.UP, 3.0, 0.4, 0.0, EARTH)
			debris(feet + Vector3(0, 0.5, 0), 9, 5.0, 0.24)
		"plant":
			ring(feet + Vector3(0, 0.12, 0), Vector3.UP, 3.4, 0.4, 0.0, DUST)
		"quake_land":
			var ql: Vector3 = ev["pos"]
			var qr: float = ev["radius"]
			dome(ql, qr, 0.5)
			for k in range(4):
				ring(ql + Vector3(0, 0.1, 0), Vector3.UP, qr * (0.5 + 0.17 * k), 0.5 + 0.08 * k, k * 0.05, EARTH, 0.6, Vector3.INF, 0.8)
			debris(ql, 22, 12.0, 0.4, 2.0)
		"scooter_on":
			_scooter_scale = 0.15
			ring(feet + Vector3(0, 0.1, 0), Vector3.UP, 2.6, 0.4)
		"punch":
			var o: Vector3 = ev["origin"]
			var d: Vector3 = ev["dir"]
			ring(o + d * 1.1, d, 1.0, 0.2, 0.0, AIR, 0.2)
		"slice":
			var o2: Vector3 = ev["origin"]
			var d2: Vector3 = ev["dir"]
			ring(o2 + d2 * 1.3, d2, 1.8, 0.25, 0.0, AIR, 0.4)
		"blast":
			var o3: Vector3 = ev["origin"]
			var d3: Vector3 = ev["dir"]
			var c: float = ev["charge"]
			for k in range(4):
				ring(o3 + d3 * (1.4 + k * 1.6 * (0.6 + c)), d3, (1.2 + k * 0.9) * (0.8 + 0.9 * c), 0.35, k * 0.045)
			if bool(ev["boosted"]):
				ring(o3 + d3 * 2.5, d3, 3.0, 0.4)
		"shield_on":
			ring(feet + Vector3(0, 1.0, 0), Vector3.UP, 2.6, 0.3)
		"breath_start":
			var ob: Vector3 = feet + Vector3(0, C.EYE_STAND, 0)
			var lk: Vector3 = sim.look_dir()
			for k in range(3):
				ring(ob + lk * 2.0, lk, 7.0 + k * 3.0, 0.5, k * 0.08)
		"bomb_wind":
			for k in range(4):
				ring(feet + Vector3(0, 1.0, 0), Vector3.UP, 0.5, 0.35, k * 0.07, AIR, 5.0, Vector3.INF, 0.6, true)
		"bomb_dive":
			ring(feet + Vector3(0, 1.5, 0), Vector3.UP, 5.0, 0.35)
		"element":
			var which := String(ev["element"])
			var ecol: Color = EARTH if which == "earth" else (WATER if which == "water" else AIR)
			ring(feet + Vector3(0, 0.15, 0), Vector3.UP, 2.4, 0.4, 0.0, ecol)
			ring(feet + Vector3(0, 1.0, 0), Vector3.UP, 1.6, 0.35, 0.05, ecol)
			floating_text(feet + Vector3(0, 2.3, 0), which.to_upper(), Color(0.9, 0.7, 0.4) if which == "earth" else (WATER if which == "water" else Color(0.85, 0.96, 1.0)))
		"launched":
			ring(feet + Vector3(0, 0.1, 0), Vector3.UP, 3.0, 0.4, 0.0, EARTH)
			debris(feet, 8, 6.0)
		"wallrun_on":
			ring(feet + Vector3(0, 0.6, 0), ev["dir"], 1.6, 0.3, 0.0, AIR, 0.4)
			debris(feet + Vector3(0, 0.3, 0), 6, 4.0, 0.14, 0.6)
		"wallrun_lip":
			ring(feet + Vector3(0, 0.3, 0), Vector3.UP, 2.4, 0.4, 0.0, AIR, 0.5)
		"rock":
			var o4: Vector3 = ev["origin"]
			var d4: Vector3 = ev["dir"]
			ring(o4 + d4 * 1.1, d4, 0.9, 0.2, 0.0, EARTH, 0.2)
			debris(feet + sim.look_dir() * 1.6, 5, 4.0, 0.16)
			var rs0 := feet + Vector3(d4.x, 0.0, d4.z).normalized() * 1.8
			rs0.y = world.height_at(rs0.x, rs0.z)
			add_pull(rs0, o4 + d4 * 0.9, 0.14, 0.42, false)
		"earth_take":
			if sim.charging:
				add_pull(ev["src"], Vector3.ZERO, 0.38, 0.3, true)
		"boulder_pull":
			var bs: Vector3 = ev["src"]
			debris(bs + Vector3(0, 0.3, 0), 18, 8.0, 0.3, 1.8)
			ring(bs + Vector3(0, 0.15, 0), Vector3.UP, 4.4, 0.5, 0.0, DUST, 0.4, Vector3.INF, 0.5)
			for k in range(7):
				add_pull(bs + Vector3(_rng.randf_range(-1.8, 1.8), 0.2, _rng.randf_range(-1.8, 1.8)), Vector3.ZERO, 0.42 + 0.03 * k, 0.28, false, true)
		"boulder":
			var o6: Vector3 = ev["origin"]
			var d6: Vector3 = ev["dir"]
			ring(o6 + d6 * 1.6, d6, 1.6, 0.3, 0.0, EARTH, 0.3)
		"barrage":
			var o7: Vector3 = ev["origin"]
			var d7: Vector3 = ev["dir"]
			ring(o7 + d7 * 1.2, d7, 2.0, 0.3, 0.0, EARTH, 0.25)
			debris(feet + Vector3(d7.x, 0, d7.z).normalized() * 1.8, 9, 7.0, 0.2)
		"wave":
			var d5: Vector3 = ev["dir"]
			var f5 := Vector3(d5.x, 0.0, d5.z).normalized()
			ring(feet + Vector3(0, 0.1, 0) + f5 * 1.5, Vector3.UP, 2.6, 0.35, 0.0, EARTH)
			debris(feet + f5 * 1.5, 7, 6.0)
		"bomb":
			var at: Vector3 = ev["pos"]
			var r: float = ev["radius"]
			dome(at, r, 0.6)
			for k in range(5):
				ring(at + Vector3(0, 0.1, 0), Vector3.UP, r * (0.5 + 0.1 * k), 0.45 + 0.08 * k, k * 0.05, AIR, 0.5, Vector3.INF, 0.8)
			for k in range(4):
				ring(at + Vector3(0, 1.0 + k * 2.5, 0), Vector3.UP, 4.0 + k, 0.5, k * 0.06, AIR, 1.0, at + Vector3(0, 3.0 + k * 3.5, 0))


func on_world_event(ev: Dictionary) -> void:
	match String(ev["type"]):
		"bot_hit":
			var dmg: float = ev["damage"]
			var col := Color(1.0, 0.95, 0.6) if dmg >= 30.0 else Color(1, 1, 1)
			floating_text(ev["pos"], str(int(round(dmg))), col)
		"bot_die":
			var p: Vector3 = ev["pos"]
			for k in range(3):
				ring(p, Vector3.UP, 2.5 + k, 0.45, k * 0.07)
		"bot_respawn":
			ring(ev["pos"], Vector3.UP, 2.0, 0.5, 0.0, Color(0.6, 1.0, 0.7))
		"deflect":
			_shield_flash = 1.0
			ring(ev["pos"], Vector3.UP, 1.2, 0.3, 0.0, Color(1, 1, 1))
		"bot_fire":
			ring(ev["pos"], Vector3.UP, 0.8, 0.25, 0.0, BOLT)
			if ev.has("bot") and _bot_views.has(ev["bot"]):
				_bot_views[ev["bot"]]["rig"].trigger("throw", 0.3)
		"bot_cast":
			if _bot_views.has(ev["bot"]):
				var bk := String(ev["kind"])
				_bot_views[ev["bot"]]["rig"].trigger("thrust" if bk == "shield" else bk, 0.32)
				var cc := AIR if ev["bot"].nation == "air" else (WATER if ev["bot"].nation == "water" else EARTH)
				ring(ev["pos"], Vector3.UP, 1.2, 0.3, 0.0, cc, 0.35)
				if bk == "stomp" or bk == "raise" or bk == "slam":
					debris(ev["bot"].pos, 5, 4.5, 0.16)
		"bot_telegraph":
			var tp: Vector3 = ev["pos"]
			var td: float = ev["dur"]
			ring(tp + Vector3(0, 0.15, 0), Vector3.UP, float(ev["radius"]), td, 0.0, BOLT, 0.5, Vector3.INF, 0.9)
			ring(tp + Vector3(0, 0.15, 0), Vector3.UP, float(ev["radius"]) * 0.5, td, 0.0, BOLT, 0.5, Vector3.INF, 0.9)
		"bot_blast":
			ring(ev["pos"] + ev["dir"] * 1.0, ev["dir"], 2.4, 0.3, 0.0, AIR, 0.6)
			debris(ev["pos"], 4, 6.0, 0.12)
		"bot_breath":
			ring(ev["pos"], ev["dir"], 2.2, 0.45, 0.0, AIR, 0.7, ev["pos"] + ev["dir"] * 18.0, 0.4)
		"bot_swing":
			if _bot_views.has(ev["bot"]):
				_bot_views[ev["bot"]]["rig"].trigger("punch", C.BOT_MELEE_WINDUP, 1)
		"bot_melee_hit":
			ring(ev["pos"], Vector3.UP, 1.3, 0.25, 0.0, Color(1, 0.8, 0.6), 0.3)
			debris(ev["pos"], 4, 4.0, 0.12)
		"melee_hit":
			ring(ev["pos"], Vector3.UP, 1.1, 0.22, 0.0, Color(1, 1, 1), 0.3)
			debris(ev["pos"], 4, 4.5, 0.12)
		"clap_start":
			_start_book(ev["pos"], ev["dir"])
			var cs: Vector3 = ev["pos"]
			ring(cs + Vector3(0, 0.15, 0), Vector3.UP, C.CLAP_GAP * 1.4, 0.5, 0.0, DUST, 0.4, Vector3.INF, 0.5)
		"clap_rise":
			var cr2: Vector3 = ev["pos"]
			var cd: Vector3 = ev["dir"]
			var pp := Vector3(-cd.z, 0.0, cd.x)
			for sgn in [-1.0, 1.0]:
				var sp: Vector3 = cr2 + pp * float(ev["gap"]) * sgn
				debris(sp + Vector3(0, 1.0, 0), 14, 8.0, 0.35, 2.5)
				ring(sp + Vector3(0, 0.15, 0), Vector3.UP, 5.0, 0.5, 0.0, DUST, 0.4, Vector3.INF, 0.5)
		"clap_slam":
			var ci: Vector3 = ev["pos"]
			dome(ci + Vector3(0, 1.0, 0), 7.0, 0.4)
			for k in range(3):
				ring(ci + Vector3(0, 0.2, 0), Vector3.UP, 5.0 + 3.0 * k, 0.5, k * 0.06, EARTH, 0.6, Vector3.INF, 0.7)
			debris(ci + Vector3(0, 2.0, 0), 30, 14.0, 0.4, 3.0)
		"wall_grab":
			var gp: Vector3 = ev["pos"]
			debris(gp + Vector3(0, 1.5, 0), 18, 7.0, 0.32, 3.0)
			ring(gp + Vector3(0, 0.15, 0), Vector3.UP, float(ev["radius"]), 0.5, 0.0, DUST, 0.4, Vector3.INF, 0.5)
		"held_hit":
			debris(ev["pos"], 5, 5.0, 0.14)
			ring(ev["pos"], Vector3.UP, 1.0, 0.25, 0.0, EARTH, 0.2)
		"held_break":
			var hb: Vector3 = ev["pos"]
			debris(hb + Vector3(0, 1.0, 0), 26, 9.0, 0.34, 2.5)
			ring(hb + Vector3(0, 0.5, 0), Vector3.UP, 3.5, 0.45, 0.0, EARTH)
		"bot_fall":
			ring(ev["pos"] + Vector3(0, 0.1, 0), Vector3.UP, 2.4, 0.35, 0.0, DUST, 0.3)
			debris(ev["pos"], 6, 5.0, 0.2)
			floating_text(ev["pos"] + Vector3(0, 2.0, 0), "FALL " + str(int(round(float(ev["damage"])))), Color(0.95, 0.7, 0.4))
		"bot_cushion":
			ring(ev["pos"] + Vector3(0, 0.1, 0), Vector3.UP, 2.6, 0.4, 0.0, AIR)
			ring(ev["pos"] + Vector3(0, 0.6, 0), Vector3.UP, 1.8, 0.3, 0.05, AIR)
			floating_text(ev["pos"] + Vector3(0, 2.0, 0), "CUSHIONED", Color(0.85, 0.96, 1.0))
		"splash":
			var sp: Vector3 = ev["pos"]
			var big: bool = bool(ev.get("big", false))
			ring(sp + Vector3(0, 0.05, 0), Vector3.UP, 4.0 if big else 2.2, 0.55, 0.0, Color(0.75, 0.9, 1.0), 0.5)
			ring(sp + Vector3(0, 0.05, 0), Vector3.UP, 2.6 if big else 1.4, 0.4, 0.08, Color(0.9, 0.97, 1.0), 0.4)
			if big:
				debris(sp, 10, 7.0, 0.16, 1.2)
		"proj_hit":
			var kind: String = ev["kind"]
			if kind == "shard":
				debris(ev["pos"], 5, 5.0, 0.1, 0.4, 1.0, true)
			var col2 := BOLT if kind == "bolt" else (EARTH if (kind == "rock" or kind == "boulder") else AIR)
			ring(ev["pos"], Vector3.UP, 1.1, 0.25, 0.0, col2, 0.2)
			if kind == "rock":
				debris(ev["pos"], 6, 5.0, 0.18)
			elif kind == "boulder":
				debris(ev["pos"], 14, 9.0, 0.35)
		"rock_burst":
			var rp: Vector3 = ev["pos"]
			ring(rp + Vector3(0, 0.1, 0), Vector3.UP, float(ev.get("radius", C.ROCK_SPLASH)), 0.35, 0.0, EARTH, 0.3)
		"earth_rise":
			var ep: Vector3 = ev["pos"]
			var er: float = ev["radius"]
			ring(ep + Vector3(0, 0.12, 0), Vector3.UP, er * 1.4, 0.5, 0.0, DUST, 0.4, Vector3.INF, 0.55)
			debris(ep, int(clampf(er * 2.0, 4.0, 14.0)), 7.0 + er, 0.28, er * 0.5)
		"earth_wave":
			var wp: Vector3 = ev["pos"]
			ring(wp + Vector3(0, 0.12, 0), Vector3.UP, 3.0, 0.4, 0.0, DUST)
		"crater":
			var cp: Vector3 = ev["pos"]
			var cr: float = ev["radius"]
			var amt: float = ev["amount"]
			ring(cp + Vector3(0, 0.15, 0), Vector3.UP, cr * 1.6, 0.55, 0.0, DUST, 0.5, Vector3.INF, 0.5)
			debris(cp, int(clampf(amt * 0.6, 4.0, 22.0)), 6.0 + cr * 1.2, 0.26, cr * 0.6)
		"quake_start":
			var qp: Vector3 = ev["pos"]
			for k in range(3):
				ring(qp + Vector3(0, 0.15, 0), Vector3.UP, ev["radius"], 0.9, k * 0.18, EARTH, 1.0)
		"puddle":                                   # spent water lands on the ground: it can be gathered again
			var pd: Vector3 = ev["pos"]
			ring(pd + Vector3(0, 0.05, 0), Vector3.UP, float(ev["radius"]) * 1.4, 0.45, 0.0, WATER, 0.3, Vector3.INF, 0.55)
			debris(pd + Vector3(0, 0.1, 0), 3, 3.0, 0.08, 0.5, 0.8, true)
		"thaw":
			var tp: Vector3 = ev["pos"]
			ring(tp + Vector3(0, 0.08, 0), Vector3.UP, float(ev["radius"]) * 0.8, 0.6, 0.0, WATER, 0.5, Vector3.INF, 0.5)
			debris(tp + Vector3(0, 0.3, 0), 14, 6.0, 0.14, float(ev["radius"]) * 0.4, 1.0, true)
		"bot_jet":
			ring(ev["pos"], ev["dir"], 1.4, 0.4, 0.0, WATER, 0.6, ev["pos"] + ev["dir"] * 15.0, 0.5)
		"bot_whip":
			var wf: Vector3 = ev["from"]
			var wt: Vector3 = ev["to"]
			var wmid := (wf + wt) * 0.5 + Vector3(0.0, 0.5, 0.0)
			var thick := 0.16 if bool(ev["big"]) else 0.1
			beam(wf, wmid, thick, 0.25, WATER, 0.9)
			beam(wmid, wt, thick * 0.7, 0.25, WATER, 0.9)
			ring(wt, Vector3.UP, 1.4, 0.3, 0.05, WATER, 0.3)
		"bot_octo":
			var bo: Vector3 = ev["pos"]
			dome(bo, 4.0, 0.5, Color(0.4, 0.72, 1.0))
			floating_text(bo + Vector3(0, 2.0, 0), "OCTOPUS FORM", WATER)
		"bot_heal":
			ring(ev["pos"], Vector3.UP, 2.0, 0.6, 0.0, Color(0.6, 1.0, 0.85), 0.4)
		"ice_wall_rise":
			var iw: Vector3 = ev["pos"]
			ring(iw + Vector3(0, 0.12, 0), Vector3.UP, C.ICE_WALL_HALF_WIDTH * 1.3, 0.45, 0.0, ICE, 0.4, Vector3.INF, 0.6)
			debris(iw + Vector3(0, 1.0, 0), 14, 7.0, 0.16, C.ICE_WALL_HALF_WIDTH * 0.5, 1.0, true)
		"ice_shatter":
			var sh: Vector3 = ev["pos"]
			ring(sh + Vector3(0, 0.3, 0), Vector3.UP, C.ICE_WALL_HALF_WIDTH * 1.2, 0.4, 0.0, ICE, 0.4, Vector3.INF, 0.7)
			debris(sh + Vector3(0, 1.4, 0), 30, 10.0, 0.22, C.ICE_WALL_HALF_WIDTH * 0.6, 1.0, true)
			if bool(ev["struck"]):
				floating_text(sh + Vector3(0, 3.0, 0), "SHATTERED", ICE)
		"freeze":
			var fz: Vector3 = ev["pos"]
			ring(fz, Vector3.UP, 2.4, 0.5, 0.0, ICE, 0.4)
			debris(fz, 12, 6.0, 0.14, 0.8, 1.0, true)
			floating_text(fz + Vector3(0, 1.6, 0), "FROZEN", ICE)
		"unfreeze":
			var uf: Vector3 = ev["pos"]
			ring(uf, Vector3.UP, 2.2, 0.4, 0.0, ICE, 0.4)
			debris(uf, 20, 8.0, 0.18, 0.8, 1.0, true)
		"freeze_water":
			var fw: Vector3 = ev["pos"]
			ring(fw + Vector3(0, 0.08, 0), Vector3.UP, float(ev["radius"]) * 0.9, 0.35, 0.0, ICE, 0.5, Vector3.INF, 0.45)
		"tidal_wave":
			_start_tide_view(ev)
		"octo_grab":
			ring(ev["pos"], Vector3.UP, 2.0, 0.4, 0.0, WATER, 0.4)
		"octo_drop":
			ring(ev["pos"], Vector3.UP, 1.8, 0.3, 0.0, WATER, 0.4)
		"octo_throw":
			ring(ev["pos"], Vector3.UP, 2.0, 0.4, 0.0, WATER, 0.4)
		"octo_slam":
			var os2: Vector3 = ev["pos"]
			var osr: float = ev["radius"]
			dome(os2, osr, 0.5, Color(0.4, 0.72, 1.0))
			for k in range(4):
				ring(os2 + Vector3(0, 0.15, 0), Vector3.UP, osr * (0.5 + 0.17 * k), 0.45 + 0.07 * k, k * 0.05, WATER, 0.6, Vector3.INF, 0.8)
			debris(os2 + Vector3(0, 1.0, 0), 20, 11.0, 0.2, 2.5, 1.0, true)


# ------------------------------------------------------------------ per-frame views

func update(dt: float, feet: Vector3) -> void:
	_time += dt
	var look: Vector3 = sim.look_dir()
	var eye := feet + Vector3(0.0, sim.eye_height(), 0.0)
	var cb := cam.global_transform.basis
	_update_player_rigs(dt, feet)

	# --- Air Scooter bubble (grows in, wobbles, shows the spinning ball when you look down)
	_scooter_scale = lerpf(_scooter_scale, 1.0 if sim.scooter else 0.0, 1.0 - exp(-14.0 * dt))
	var riding := _scooter_scale > 0.03
	scooter_shell.visible = riding
	scooter_ball.visible = riding
	if riding:
		var wob := 1.0 + 0.035 * sin(_time * 9.0)
		scooter_shell.position = feet + Vector3(0.0, 0.8, 0.0)
		scooter_shell.scale = Vector3.ONE * 1.15 * _scooter_scale * wob
		scooter_ball.position = feet + Vector3(0.0, 0.5, 0.0)
		scooter_ball.scale = Vector3.ONE * 0.55 * _scooter_scale
		scooter_ball.rotate_y(dt * 9.0)
		scooter_ball.rotate_x(dt * 3.0)
		if sim.scooter and sim.on_ground and sim.speed() > 3.0:
			_wake_t -= dt
			if _wake_t <= 0.0:
				_wake_t = 0.1
				ring(feet + Vector3(0.0, 0.08, 0.0), Vector3.UP, 1.9, 0.35, 0.0, AIR, 0.5, Vector3.INF, 0.4)

	# --- Air Shield
	shield_node.visible = sim.shield_on
	if sim.shield_on:
		shield_node.position = feet + Vector3(0.0, 1.0, 0.0)
		shield_node.scale = Vector3.ONE * C.SHIELD_RADIUS * (1.0 + 0.02 * sin(_time * 14.0))
		_shield_flash = maxf(0.0, _shield_flash - dt * 3.0)
		var sm := shield_node.material_override as ShaderMaterial
		sm.set_shader_parameter("rim_alpha", 0.7 + _shield_flash)
		sm.set_shader_parameter("base_alpha", 0.10 + _shield_flash * 0.25)

	# --- Charge: air gathers as a bubble; earth is compressed into a rock ball as chunks are pulled in from around you
	var earth_charge: bool = sim.charging and sim.element == "earth"
	charge_orb.visible = sim.charging and not earth_charge
	charge_rock.visible = earth_charge
	if sim.charging:
		var orb: Vector3 = arm_rigs[sim.element].hand_mid() + (-cb.z) * (0.5 + 0.3 * sim.charge) + cb.y * 0.02
		charge_orb.position = orb
		var full: float = 1.0 + (0.12 * sim.charge if sim.charge >= 1.0 else 0.0)
		if earth_charge:
			var shake: Vector3 = Vector3(sin(_time * 70.0), cos(_time * 83.0), sin(_time * 61.0)) * 0.012 * sim.charge
			charge_rock.position = orb + shake
			charge_rock.scale = Vector3(1.0, 0.88, 1.0) * (0.10 + 0.24 * sim.charge) * (1.0 - 0.08 * sin(_time * 30.0) * sim.charge)
			charge_rock.rotate_y(dt * 3.0)
			charge_rock.rotate_x(dt * 1.7)
			_rock_mat.albedo_color = Color(0.5, 0.4, 0.3).lerp(Color(0.3, 0.24, 0.19), sim.charge)
			_charge_t -= dt
			if _charge_t <= 0.0:
				_charge_t = 0.07
				var a2 := _rng.randf() * TAU
				var rr := _rng.randf_range(1.2, 3.2)
				var src := feet + Vector3(cos(a2) * rr, 0.0, sin(a2) * rr)
				src.y = world.height_at(src.x, src.z) + 0.1
				add_pull(src, Vector3.ZERO, 0.34, 0.2, true)
		else:
			charge_orb.scale = Vector3.ONE * (0.06 + 0.28 * sim.charge) * full
			charge_orb.rotate_y(dt * 12.0)
			_charge_t -= dt
			if _charge_t <= 0.0:
				_charge_t = 0.09
				ring(orb + (-cb.z) * 0.9, -cb.z, 0.2, 0.28, 0.0, AIR, 0.9 + 0.8 * sim.charge, orb, 0.5, true)

	# --- RMB boulder: torn from the ground, carried to your hands, then thrown
	var bp: Dictionary = sim.boulder_pull
	boulder_node.visible = not bp.is_empty()
	if not bp.is_empty():
		var k: float = clampf(float(bp["t"]) / C.BOULDER_PULL_TIME, 0.0, 1.0)
		var src2: Vector3 = bp["src"]
		var hold := eye + look * C.BOULDER_HOLD_DIST + Vector3(0.0, 0.15, 0.0)
		var e: float = k * k * (3.0 - 2.0 * k)
		var from := src2 + Vector3(0.0, 0.5, 0.0)
		boulder_node.position = from.lerp(hold, e) + Vector3(0.0, sin(e * PI) * 1.2, 0.0)
		boulder_node.scale = Vector3(0.55, 0.42, 0.62) * 2.3 * (0.35 + 0.65 * minf(1.0, k * 2.0))
		boulder_node.rotate_y(dt * 4.0)
		boulder_node.rotate_x(dt * 2.5)
		_pull_t -= dt
		if _pull_t <= 0.0 and k < 0.8:
			_pull_t = 0.05
			debris(boulder_node.position, 1, 2.5, 0.14, 0.5, 0.4)
	_update_pulls(dt)
	_update_books(dt)

	# --- Air Suction: rings rush toward you
	if sim.suction_on:
		_suction_t -= dt
		if _suction_t <= 0.0:
			_suction_t = 0.06
			ring(eye + look * 15.0, look, 0.7, 0.45, 0.0, AIR, 7.5, eye + look * 1.4, 0.45, true)

	# --- Air Breath: a long cone of streaking air plus rings racing outward
	var breathing: bool = sim.breath_t > 0.0
	breath_cone.visible = breathing
	breath_core.visible = breathing
	if breathing:
		var length := C.BREATH_RANGE
		var spread := length * tan(acos(C.BREATH_CONE_COS))
		var apex := eye + look * 0.8 + Vector3(0.0, -0.35, 0.0)
		var q := Quaternion(Vector3.UP, -look)
		var flutter := 1.0 + 0.04 * sin(_time * 31.0)
		breath_cone.position = apex + look * (length * 0.5)
		breath_cone.quaternion = q
		breath_cone.scale = Vector3(spread * flutter, length, spread * flutter)
		breath_core.position = apex + look * (length * 0.5)
		breath_core.quaternion = q
		breath_core.scale = Vector3(spread * 0.42, length * 0.9, spread * 0.42)
		_breath_t -= dt
		if _breath_t <= 0.0:
			_breath_t = 0.03
			ring(apex, look, spread * 0.85, 0.5, 0.0, AIR, 0.6, apex + look * length * 0.95, 0.4)

	# --- Air Bomb aura and falling rings
	var bombing: bool = not sim.slam.is_empty()
	aura.visible = bombing
	if bombing:
		aura.position = feet + Vector3(0.0, 1.0, 0.0)
		aura.scale = Vector3.ONE * (2.2 + 0.15 * sin(_time * 25.0))
		var earth_dive: bool = bool(sim.slam.get("earth", false))
		(aura.material_override as ShaderMaterial).set_shader_parameter("tint", Color(0.75, 0.55, 0.32) if earth_dive else Color(0.9, 0.98, 1.0))
		aura.rotate_y(dt * 10.0)
		if String(sim.slam["phase"]) == "dive":
			_trail_t -= dt
			if _trail_t <= 0.0:
				_trail_t = 0.04
				ring(feet + Vector3(0.0, 2.0, 0.0), Vector3.UP, 3.2, 0.4, 0.0, EARTH if earth_dive else Color(1, 1, 1), 1.4)

	# --- Earthquake: dust and rock thrown up all around you while it runs
	if sim.quake_t > 0.0:
		_quake_fx_t -= dt
		if _quake_fx_t <= 0.0:
			_quake_fx_t = 0.07
			var a := _rng.randf() * TAU
			var r := _rng.randf_range(2.0, C.QUAKE_RADIUS * 0.9)
			var qp2 := feet + Vector3(cos(a) * r, 0.0, sin(a) * r)
			qp2.y = world.height_at(qp2.x, qp2.z)
			debris(qp2, 3, 7.0, 0.25, 0.8)
			ring(qp2 + Vector3(0, 0.1, 0), Vector3.UP, 2.4, 0.5, 0.0, DUST, 0.3, Vector3.INF, 0.4)

	if sim.wallrun:
		_wake_t -= dt
		if _wake_t <= 0.0:
			_wake_t = 0.06
			ring(feet + Vector3(0.0, 0.5, 0.0) + sim.wallrun_dir * 0.5, sim.wallrun_dir, 1.2, 0.3, 0.0, AIR, 0.5, Vector3.INF, 0.4)
			debris(feet + sim.wallrun_dir * 0.5 + Vector3(0, 0.2, 0), 1, 3.0, 0.12, 0.4, 0.5)

	# --- Earth Elevator: a slab of rock under your feet
	_skate_scale = lerpf(_skate_scale, 1.0 if sim.elevating else 0.0, 1.0 - exp(-16.0 * dt))
	skate_slab.visible = _skate_scale > 0.05
	if skate_slab.visible:
		var heading0 := Vector3(-sin(sim.yaw), 0.0, -cos(sim.yaw))
		skate_slab.look_at_from_position(feet + Vector3(0, -0.08, 0), feet + Vector3(0, -0.08, 0) + heading0, Vector3.UP)
		skate_slab.scale = Vector3.ONE * _skate_scale
		_slab_dust_t -= dt
		if _slab_dust_t <= 0.0:
			_slab_dust_t = 0.07
			debris(feet + Vector3(0, 0.1, 0), 2, 3.5, 0.16, 0.6, 0.6)

	# --- Earth Skate: one foot at a time, each step lifts a chunk of earth under the leading foot
	_foot_scale = lerpf(_foot_scale, 1.0 if (sim.skating and not sim.elevating) else 0.0, 1.0 - exp(-14.0 * dt))
	var fvis := _foot_scale > 0.05
	var iceskate: bool = sim.element == "water"
	for fr in foot_rocks:
		fr.visible = fvis
		fr.material_override = _ice_slab_mat if iceskate else _slab_mat
	if fvis:
		var hv2 := Vector3(sim.vel.x, 0.0, sim.vel.z)
		var moving := hv2.length() > 2.0
		var hd := hv2.normalized() if moving else Vector3(-sin(sim.yaw), 0.0, -cos(sim.yaw))
		var side := Vector3(-hd.z, 0.0, hd.x)
		if moving and sim.on_ground:
			_stride += hv2.length() * dt / 3.0          # one foot per ~1.5 m
		var ph := fposmod(_stride, 1.0)
		var stepping := 0 if ph < 0.5 else 1
		var lt := (ph * 2.0) if ph < 0.5 else (ph * 2.0 - 1.0)   # 0..1 through this foot's lift
		if stepping != _foot_up and moving:
			# the foot that was lifted plants: a puff and a ring where the chunk comes down
			var planted: MeshInstance3D = foot_rocks[_foot_up]
			var pp3 := planted.position
			ring(Vector3(pp3.x, world.height_at(pp3.x, pp3.z) + 0.06, pp3.z), Vector3.UP, 1.5, 0.3, 0.0, ICE if iceskate else DUST, 0.4, Vector3.INF, 0.4)
			debris(Vector3(pp3.x, world.height_at(pp3.x, pp3.z), pp3.z), 3, 3.0, 0.13, 0.5, 0.6, iceskate)
		_foot_up = stepping
		for k in range(2):
			var sgn := -1.0 if k == 0 else 1.0
			var lift := 0.0
			var fwd_off := 0.0
			if moving and k == stepping:
				lift = sin(lt * PI) * 0.5
				fwd_off = lerpf(-0.6, 0.7, lt)
			elif moving:
				fwd_off = lerpf(0.7, -0.6, lt)
			var fp := feet + side * sgn * 0.32 + hd * fwd_off
			var gy: float = world.height_at(fp.x, fp.z)
			var fr: MeshInstance3D = foot_rocks[k]
			var gd: Dictionary = world.ground_at(fp.x, fp.z, gy + 1.0)
			var nrm := Vector3(gd["nx"], gd["ny"], gd["nz"])
			fr.look_at_from_position(Vector3(fp.x, gy + 0.03 + lift, fp.z), Vector3(fp.x, gy + 0.03 + lift, fp.z) + hd, nrm.lerp(Vector3.UP, 0.3))
			if lift > 0.05:
				fr.rotate_object_local(Vector3.RIGHT, -0.35 * sin(lt * PI))      # the lifted chunk tips as it rises
			fr.scale = Vector3.ONE * _foot_scale * (0.82 + 0.18 * (1.0 if k != stepping or not moving else lt))
		if moving and sim.on_ground:
			_slab_dust_t -= dt
			if _slab_dust_t <= 0.0:
				_slab_dust_t = 0.09
				debris(feet + Vector3(0, 0.1, 0), 1, 3.0, 0.12, 0.5, 0.5)

	# --- Earth Armor: plates of rock orbiting you; they drop away as the armor wears down
	_armor_scale = lerpf(_armor_scale, 1.0 if sim.armor_on else 0.0, 1.0 - exp(-10.0 * dt))
	var ratio: float = clampf(sim.armor_hp / C.ARMOR_HP, 0.0, 1.0)
	var shown := int(ceil(ratio * float(armor_plates.size())))
	for k in range(armor_plates.size()):
		var plate: MeshInstance3D = armor_plates[k]
		plate.visible = _armor_scale > 0.05 and k < shown
		if plate.visible:
			var a := _time * 1.5 + float(k) * TAU / float(armor_plates.size())
			var r := (1.2 + 0.08 * sin(_time * 3.0 + k)) * (0.4 + 0.6 * _armor_scale)
			plate.position = feet + Vector3(cos(a) * r, 0.15 + float(k % 5) * 0.2, sin(a) * r)
			plate.rotation = Vector3(0.3 * sin(_time * 2.0 + k), -a, 0.2)
			plate.scale = Vector3.ONE * (0.6 * _armor_scale)

	# --- The carried wall slab
	var carrying: bool = not world.held.is_empty()
	held_node.visible = carrying
	if carrying:
		var hc: Vector3 = world.held["c"]
		var hf: Vector2 = world.held["f"]
		var half_w: float = world.held["half_w"]
		held_node.look_at_from_position(hc + Vector3(0, C.HELD_HEIGHT * 0.5, 0), hc + Vector3(hf.x, C.HELD_HEIGHT * 0.5, hf.y), Vector3.UP)
		held_node.scale = Vector3(half_w * 2.0, C.HELD_HEIGHT, 0.9)
		var hr: float = clampf(float(world.held["hp"]) / C.HELD_HP, 0.0, 1.0)
		_held_mat.albedo_color = Color(0.30, 0.25, 0.20).lerp(Color(0.52, 0.45, 0.36), hr)

	# --- Water Jet: a streaming cone of water
	var jetting: bool = sim.jet_on
	jet_cone.visible = jetting
	jet_core.visible = jetting
	if jetting:
		var jlen := C.JET_RANGE
		var jspread := jlen * tan(acos(C.JET_CONE_COS)) * 0.5
		var japex := eye + look * 0.8 + Vector3(0.0, -0.35, 0.0)
		var jq := Quaternion(Vector3.UP, -look)
		var jfl := 1.0 + 0.05 * sin(_time * 37.0)
		jet_cone.position = japex + look * (jlen * 0.5)
		jet_cone.quaternion = jq
		jet_cone.scale = Vector3(jspread * jfl, jlen, jspread * jfl)
		jet_core.position = japex + look * (jlen * 0.5)
		jet_core.quaternion = jq
		jet_core.scale = Vector3(jspread * 0.4, jlen * 0.92, jspread * 0.4)
		_jet_t -= dt
		if _jet_t <= 0.0:
			_jet_t = 0.04
			ring(japex, look, jspread * 0.9, 0.35, 0.0, WATER, 0.4, japex + look * jlen * 0.95, 0.45)

	# --- Heal: rings of light water rise around you while it pours in
	if sim.heal_left > 0.0:
		_heal_fx_t -= dt
		if _heal_fx_t <= 0.0:
			_heal_fx_t = 0.12
			ring(feet + Vector3(0, 0.1, 0), Vector3.UP, 1.3, 0.55, 0.0, Color(0.6, 1.0, 0.85), 0.8, feet + Vector3(0, 1.9, 0), 0.5)

	# --- Ice Skate: a trail of frost behind you
	if sim.skating and sim.element == "water" and sim.on_ground and sim.speed() > 3.0:
		_ice_dust_t -= dt
		if _ice_dust_t <= 0.0:
			_ice_dust_t = 0.09
			ring(feet + Vector3(0.0, 0.08, 0.0), Vector3.UP, 1.9, 0.35, 0.0, ICE, 0.5, Vector3.INF, 0.4)
			debris(feet + Vector3(0, 0.1, 0), 1, 3.0, 0.1, 0.5, 0.5, true)

	# --- Octopus Form: two long arms of water follow your view, lash out on a swipe, and reach for a grabbed enemy
	_octo_scale = lerpf(_octo_scale, 1.0 if sim.octo_t > 0.0 else 0.0, 1.0 - exp(-8.0 * dt))
	var octo_vis := _octo_scale > 0.04
	for side in range(2):
		_swipe[side] = maxf(0.0, float(_swipe[side]) - dt * 3.5)
		var beads: Array = octo_arms[side]
		var sgn := -1.0 if side == 0 else 1.0
		var shoulder := eye + cb.x * 0.7 * sgn + cb.y * -0.6 + look * 0.9
		var prog: float = 1.0 - float(_swipe[side])
		var ang := -sgn * 0.3
		if float(_swipe[side]) > 0.0:
			ang += sgn * sin(prog * PI) * 1.3
		var dirv: Vector3 = look.rotated(Vector3.UP, ang)
		var rightv := dirv.cross(Vector3.UP)
		rightv = rightv.normalized() if rightv.length() > 0.01 else Vector3.RIGHT
		var grabbing: bool = side == 0 and world.grabbed != null
		var tip: Vector3 = world.bot_center(world.grabbed) if grabbing else Vector3.ZERO
		for k in range(OCTO_BEADS):
			var bead: MeshInstance3D = beads[k]
			bead.visible = octo_vis
			if not octo_vis:
				continue
			var t := float(k) / float(OCTO_BEADS - 1)
			var p: Vector3
			if grabbing:
				p = shoulder.lerp(tip, t) + Vector3.UP * sin(t * PI) * 0.5
			else:
				p = shoulder + dirv * (t * OCTO_LEN) + rightv * sin(_time * 2.6 + t * 6.0 + float(side) * 1.7) * 0.5 * t \
						+ Vector3.UP * (cos(_time * 2.1 + t * 5.0 + float(side)) * 0.4 * t - 0.15 * t)
			bead.position = p
			bead.scale = Vector3.ONE * lerpf(0.22, 0.1, t) * _octo_scale

	_update_whips(dt, eye, look, cb)
	_update_beams(dt)
	_update_tides(dt)
	_update_effects(dt)
	_update_debris(dt)
	_sync_projectiles()
	update_bots()


# --- projectiles

func _make_proj_node(p) -> Node3D:
	var n := Node3D.new()
	match String(p.kind):
		"slice":
			n.add_child(_inst(_crescent_mesh, _flat(Color(0.93, 0.99, 1.0), 0.9)))
			var glow := _inst(_crescent_mesh, _flat(Color(0.55, 0.85, 1.0), 0.3))
			glow.scale = Vector3(1.3, 1.3, 1.0)
			n.add_child(glow)
		"punch":
			var core := _inst(_sphere_mesh, _flat(Color(0.95, 1.0, 1.0), 0.95))
			core.scale = Vector3.ONE * 0.2
			n.add_child(core)
			var halo := _inst(_sphere_mesh, _bubble(Color(0.8, 0.95, 1.0), 0.1, 0.8, 1.5, 6.0, 6.0, 0.5))
			halo.scale = Vector3.ONE * 0.5
			n.add_child(halo)
		"shard":
			var sc := _inst(_shard_mesh, _shard_mat)        # a sharp four-sided ice spike, point first
			sc.scale = Vector3(1.0, 1.0, 1.25)
			n.add_child(sc)
		"rock", "boulder":
			var rm := StandardMaterial3D.new()
			rm.albedo_color = Color(0.45, 0.36, 0.27)
			rm.roughness = 1.0
			var rock := MeshInstance3D.new()
			rock.mesh = _sphere_mesh
			rock.material_override = rm
			rock.scale = Vector3(0.55, 0.42, 0.62) * (2.3 if String(p.kind) == "boulder" else 1.0)
			rock.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			n.add_child(rock)
			var dust := _inst(_sphere_mesh, _flat(DUST, 0.18))
			dust.scale = Vector3.ONE * (2.2 if String(p.kind) == "boulder" else 0.9)
			n.add_child(dust)
		_:
			var enemy: bool = String(p.team) == "enemy"
			var c := BOLT if enemy else AIR
			var core2 := _inst(_sphere_mesh, _flat(c, 0.95))
			core2.scale = Vector3.ONE * 0.26
			n.add_child(core2)
			var halo2 := _inst(_sphere_mesh, _flat(c, 0.28))
			halo2.scale = Vector3.ONE * 0.55
			n.add_child(halo2)
	return n


func _sync_projectiles() -> void:
	var live := {}
	for p in world.projectiles:
		var key := "%d%s" % [p.id, p.team]
		live[key] = true
		var n: Node3D = _proj_nodes.get(key)
		if n == null:
			n = _make_proj_node(p)
			add_child(n)
			_proj_nodes[key] = n
		var dir: Vector3 = p.vel.normalized()
		var up := Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT
		n.look_at_from_position(p.pos, p.pos + dir, up)
		if String(p.kind) == "slice":
			n.rotate_object_local(Vector3.FORWARD, p.roll)
		elif String(p.kind) == "punch":
			n.scale = Vector3.ONE * (1.0 + 0.12 * sin(_time * 40.0))
		elif String(p.kind) == "rock" or String(p.kind) == "boulder":
			n.rotate_object_local(Vector3.RIGHT, _time * 9.0)
	for key in _proj_nodes.keys():
		if not live.has(key):
			_proj_nodes[key].queue_free()
			_proj_nodes.erase(key)


# --- bots

func _build_bot_view(b = null) -> Dictionary:
	var root := Node3D.new()
	var rig = RigScript.new()
	var bot_nat := "earth"
	if b != null:
		bot_nat = b.nation if b.bender else ("air" if b.air_user else "earth")
	rig.build(bot_nat)
	if b != null and b.boss:
		rig.scale = Vector3.ONE * 1.12
	root.add_child(rig)
	var bar_mat := ShaderMaterial.new()
	bar_mat.shader = _bar_shader
	bar_mat.set_shader_parameter("ratio", 1.0)
	var bar_mesh := QuadMesh.new()
	bar_mesh.size = Vector2(1.1, 0.13)
	var bar := MeshInstance3D.new()
	bar.mesh = bar_mesh
	bar.material_override = bar_mat
	bar.position = Vector3(0.0, 2.3, 0.0)
	bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(bar)
	add_child(root)
	var sh := _shell(_sphere_mesh, _bubble(Color(0.7, 0.9, 1.0), 0.10, 0.7, 2.2, 1.2, 16.0, 0.22))
	sh.scale = Vector3.ONE * C.SHIELD_RADIUS
	sh.position = Vector3(0.0, 1.0, 0.0)
	sh.visible = false
	sh.get_parent().remove_child(sh)
	root.add_child(sh)
	var ice_block := MeshInstance3D.new()                # the block of ice a frozen bot is trapped in
	var ice_mesh := BoxMesh.new()
	ice_mesh.size = Vector3(1.25, 2.15, 1.25)
	ice_block.mesh = ice_mesh
	ice_block.material_override = _flat(Color(0.7, 0.88, 1.0), 0.5)
	ice_block.position = Vector3(0.0, 1.05, 0.0)
	ice_block.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ice_block.visible = false
	root.add_child(ice_block)
	return {"root": root, "rig": rig, "bar": bar_mat, "bar_node": bar, "shield": sh, "ice": ice_block}


func update_bots() -> void:
	var bdt: float = clampf(_time - _bot_last_t, 0.0, 0.1)
	_bot_last_t = _time
	for b in world.bots:
		var v: Dictionary = _bot_views[b]
		var root: Node3D = v["root"]
		root.visible = b.alive
		if not b.alive:
			continue
		root.position = b.pos
		root.rotation.y = b.yaw
		var rig = v["rig"]
		rig.flash(clampf(b.flash / 0.15, 0.0, 1.0))
		var near_player: bool = cam.global_position.distance_to(b.pos) < C.BOT_SIGHT
		var bstance := "ready" if near_player else "idle"
		if b.shield_t > 0.0:
			bstance = "shield"
		elif b.armor_t > 0.0:
			bstance = "armor"
		elif b.breath_t > 0.0:
			bstance = "breath"
		elif b.suck_t > 0.0:
			bstance = "suction"
		elif b.jet_t > 0.0 or b.octo_t > 0.0:
			bstance = "breath"
		elif b.scoot_t > 0.0:
			bstance = "scooter" if b.nation == "air" else "skate"
		var frozen: bool = b.frozen_t > 0.0
		rig.animate(0.0 if frozen else bdt, {"speed": 0.0 if frozen else Vector2(b.vel.x, b.vel.z).length(), "grounded": b.on_ground, "stance": bstance})
		(v["shield"] as MeshInstance3D).visible = b.shield_t > 0.0
		(v["ice"] as MeshInstance3D).visible = frozen
		var bar: ShaderMaterial = v["bar"]
		bar.set_shader_parameter("ratio", clampf(b.hp / b.max_hp, 0.0, 1.0))
		var bar_node: MeshInstance3D = v["bar_node"]
		bar_node.visible = b.hp < b.max_hp - 0.01 or b.boss or cam.global_position.distance_to(b.pos) < 22.0


# ------------------------------------------------------------------ waterbending visuals

# A straight glowing segment that fades out (one link of a water lash).
func beam(a: Vector3, b: Vector3, width: float, dur: float, color := WATER, peak := 0.8) -> void:
	var seg := a.distance_to(b)
	if seg < 0.05 or _beams.size() > 160:
		return
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 1.0
	cyl.radial_segments = 8
	cyl.rings = 1
	var mat := _flat(color, peak)
	var mi := _inst(cyl, mat)
	add_child(mi)
	mi.position = (a + b) * 0.5
	mi.quaternion = Quaternion(Vector3.UP, (b - a).normalized())
	mi.scale = Vector3(width, seg, width)
	_beams.append({"node": mi, "mat": mat, "t": 0.0, "dur": dur, "peak": peak})


func _update_beams(dt: float) -> void:
	var i := _beams.size() - 1
	while i >= 0:
		var e: Dictionary = _beams[i]
		e["t"] = float(e["t"]) + dt
		var u: float = float(e["t"]) / float(e["dur"])
		if u >= 1.0:
			(e["node"] as Node3D).queue_free()
			_beams.remove_at(i)
		else:
			(e["mat"] as StandardMaterial3D).albedo_color.a = float(e["peak"]) * (1.0 - u)
		i -= 1


# A quick solid flick of water out from the hand and back ("blap"): the two whips alternate left and right.
func start_whip(flip: bool) -> void:
	var k := 1 if flip else 0
	_whip_t[k] = 0.0
	_whip_side[k] = 1.0 if flip else -1.0


func _update_whips(dt: float, eye: Vector3, look: Vector3, cb: Basis) -> void:
	var right := look.cross(Vector3.UP)
	right = right.normalized() if right.length() > 0.01 else Vector3.RIGHT
	for k in range(2):
		var chain: Array = whip_chains[k]
		var wt: float = _whip_t[k]
		var live := wt >= 0.0
		if live:
			wt += dt
			_whip_t[k] = wt
			if wt >= C.WHIP_VIS_TIME:
				_whip_t[k] = -1.0
				live = false
		for bead in chain:
			(bead as MeshInstance3D).visible = live
		if not live:
			continue
		var u: float = wt / C.WHIP_VIS_TIME
		var ext := C.ss(0.0, 0.4, u) * (1.0 - C.ss(0.62, 1.0, u))        # snaps out, holds a beat, whips back
		var sgn: float = _whip_side[k]
		var shoulder := eye + cb.x * 0.35 * sgn + cb.y * -0.35 + look * 0.5
		for i in range(WHIP_BEADS):
			var t := float(i) / float(WHIP_BEADS - 1)
			var p := shoulder + look * (t * C.WHIP_REACH * ext) \
					+ right * (sin(t * TAU + u * 9.0) * (1.0 - u) * 0.45 * t + sgn * sin(u * PI) * 0.5 * t) \
					+ Vector3.UP * (-0.2 * t)
			var bead: MeshInstance3D = chain[i]
			bead.position = p
			bead.scale = Vector3.ONE * lerpf(0.2, 0.09, t) * clampf(ext * 4.0, 0.0, 1.0)


# A pointed ice crystal: a long four-sided spike, sharp at the front and tapering at the back.
func _build_shard() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tip := Vector3(0.0, 0.0, -1.0)
	var tail := Vector3(0.0, 0.0, 0.45)
	var r := 0.11
	var ring := [Vector3(r, 0.0, -0.2), Vector3(0.0, r, -0.2), Vector3(-r, 0.0, -0.2), Vector3(0.0, -r, -0.2)]
	for k in range(4):
		var a: Vector3 = ring[k]
		var b: Vector3 = ring[(k + 1) % 4]
		st.add_vertex(tip)
		st.add_vertex(b)
		st.add_vertex(a)
		st.add_vertex(tail)
		st.add_vertex(a)
		st.add_vertex(b)
	st.generate_normals()
	_shard_mesh = st.commit()
	_shard_mat = StandardMaterial3D.new()
	_shard_mat.albedo_color = Color(0.85, 0.96, 1.0)
	_shard_mat.roughness = 0.1
	_shard_mat.emission_enabled = true
	_shard_mat.emission = Color(0.45, 0.75, 1.0)
	_shard_mat.emission_energy_multiplier = 0.8


# The Tidal Wave: a rolling barrel of water that travels with the world's wave job.
func _start_tide_view(ev: Dictionary) -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 2.0
	cyl.radial_segments = 24
	cyl.rings = 1
	var mat := _bubble(Color(0.3, 0.62, 0.95), 0.34, 0.7, 1.4, 3.0, 10.0, 0.5)
	var mi := _inst(cyl, mat)
	add_child(mi)
	var d: Vector3 = ev["dir"]
	var o: Vector3 = ev["pos"]
	_tides.append({"node": mi, "mat": mat, "o": Vector2(o.x, o.z), "d": Vector2(d.x, d.z), "dist": 0.0, "len": float(ev["len"]),
			"speed": float(ev["speed"]), "half": float(ev["half"]), "radius": float(ev["radius"]), "splash_t": 0.0})
	var src: Vector3 = ev["src"]
	var chest: Vector3 = sim.pos + Vector3(0.0, 1.2, 0.0)
	for k in range(14):                                   # the water is pulled in from where you drew it
		add_pull(src + Vector3(_rng.randf_range(-2.5, 2.5), 0.1, _rng.randf_range(-2.5, 2.5)), chest, 0.35 + 0.025 * k, 0.28, false, false, true)


func _update_tides(dt: float) -> void:
	var i := _tides.size() - 1
	while i >= 0:
		var t: Dictionary = _tides[i]
		t["dist"] = minf(float(t["len"]), float(t["dist"]) + float(t["speed"]) * dt)
		var node: MeshInstance3D = t["node"]
		var frac: float = float(t["dist"]) / float(t["len"])
		if frac >= 1.0:
			node.queue_free()
			_tides.remove_at(i)
			i -= 1
			continue
		var d: Vector2 = t["d"]
		var q: Vector2 = (t["o"] as Vector2) + d * float(t["dist"])
		var gy: float = world.terrain.surface_at(q.x, q.y)
		var half: float = float(t["half"]) * lerpf(1.0, 0.8, frac)
		var fade := 1.0 - C.ss(0.8, 1.0, frac)
		var r: float = float(t["radius"]) * (0.6 + 0.4 * fade)
		var d3 := Vector3(d.x, 0.0, d.y)
		var lat := Vector3(-d.y, 0.0, d.x)
		node.position = Vector3(q.x, gy + r * 0.55, q.y)
		node.quaternion = Basis(d3, lat, -Vector3.UP).get_rotation_quaternion()
		node.scale = Vector3(r, half, r)
		(t["mat"] as ShaderMaterial).set_shader_parameter("fade", 0.3 + 0.7 * fade)
		t["splash_t"] = float(t["splash_t"]) - dt
		if float(t["splash_t"]) <= 0.0:
			t["splash_t"] = 0.1
			var sp := Vector3(q.x, gy + 0.05, q.y)
			ring(sp, Vector3.UP, half * 0.7, 0.5, 0.0, Color(0.75, 0.9, 1.0), 0.8, Vector3.INF, 0.5)
			ring(sp + d3 * 1.5, Vector3.UP, half * 0.45, 0.4, 0.04, Color(0.95, 0.99, 1.0), 0.5, Vector3.INF, 0.45)
		i -= 1


# ------------------------------------------------------------------ pulled earth chunks

# A chunk of earth flies from `from` to `to` (or to the charge rock when `to_charge`). `boulder_bound` makes it land on the boulder.
func add_pull(from: Vector3, to: Vector3, dur: float, size: float, to_charge := false, boulder_bound := false, watery := false) -> void:
	if _pulls.size() > 120:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = _sphere_mesh if watery else _debris_mesh
	mi.material_override = _flat(WATER, 0.75) if watery else _debris_mats[_rng.randi() % _debris_mats.size()]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3.ONE * size * _rng.randf_range(0.7, 1.3)
	add_child(mi)
	mi.position = from
	_pulls.append({"node": mi, "from": from, "to": to, "t": 0.0, "dur": dur, "charge": to_charge, "boulder": boulder_bound,
			"spin": Vector3(_rng.randf_range(-8, 8), _rng.randf_range(-8, 8), _rng.randf_range(-8, 8))})


func _update_pulls(dt: float) -> void:
	var i := _pulls.size() - 1
	while i >= 0:
		var d: Dictionary = _pulls[i]
		d["t"] = float(d["t"]) + dt
		var node: MeshInstance3D = d["node"]
		var k: float = float(d["t"]) / float(d["dur"])
		var dest: Vector3 = d["to"]
		if bool(d["charge"]):
			dest = charge_rock.position
		elif bool(d["boulder"]):
			dest = boulder_node.position
		if k >= 1.0 or (bool(d["charge"]) and not charge_rock.visible) or (bool(d["boulder"]) and not boulder_node.visible):
			node.queue_free()
			_pulls.remove_at(i)
		else:
			var from: Vector3 = d["from"]
			var e := k * k
			node.position = from.lerp(dest, e) + Vector3(0.0, sin(k * PI) * 0.5, 0.0)
			var sp: Vector3 = d["spin"]
			node.rotate_x(sp.x * dt)
			node.rotate_y(sp.y * dt)
		i -= 1


# ------------------------------------------------------------------ Earth Clap: two stone pages hinged at the ground close like a book

func _start_book(pos: Vector3, dir: Vector3) -> void:
	var pages: Array = []
	for k in range(2):
		var pivot := Node3D.new()
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(C.CLAP_HALF_LEN * 2.0, C.CLAP_SPINE, C.CLAP_PAGE)
		mi.mesh = bm
		mi.material_override = foot_rocks[0].material_override
		mi.position = Vector3(0.0, C.CLAP_SPINE * 0.5, C.CLAP_PAGE * 0.5)
		pivot.add_child(mi)
		add_child(pivot)
		pages.append(pivot)
	_claps.append({"pos": pos, "dir": dir, "t": 0.0, "pages": pages})


func _update_books(dt: float) -> void:
	var rise := C.CLAP_RISE
	var hold_end := rise + C.CLAP_HOLD
	var slam_end := hold_end + C.CLAP_SLAM
	var sink_end := slam_end + 0.6 + 0.5
	var open_deg := C.CLAP_OPEN_DEG
	var closed_deg := 90.0
	var i := _claps.size() - 1
	while i >= 0:
		var c: Dictionary = _claps[i]
		c["t"] = float(c["t"]) + dt
		var t: float = c["t"]
		var pages: Array = c["pages"]
		if t >= sink_end:
			for pg in pages:
				pg.queue_free()
			_claps.remove_at(i)
			i -= 1
			continue
		var psi := 0.0
		if t < rise:
			var k: float = t / rise
			psi = open_deg * (k * k * (3.0 - 2.0 * k))
		elif t < hold_end:
			psi = open_deg + 3.0 * ((t - rise) / C.CLAP_HOLD)
		elif t < slam_end:
			var kk: float = (t - hold_end) / C.CLAP_SLAM
			psi = lerpf(open_deg + 3.0, closed_deg, kk * kk * kk)
		else:
			psi = closed_deg
		var sink := 0.0
		if t > slam_end + 0.6:
			sink = (t - slam_end - 0.6) / 0.5 * 7.0
		var ang := deg_to_rad(psi)
		var d: Vector3 = c["dir"]
		var pp := Vector3(-d.z, 0.0, d.x)
		var base: Vector3 = c["pos"]
		for k in range(2):
			var sgn := -1.0 if k == 0 else 1.0
			var outward := pp * sgn
			var w := outward * cos(ang) + Vector3.UP * sin(ang)
			var u := -outward * sin(ang) + Vector3.UP * cos(ang)
			var pivot: Node3D = pages[k]
			pivot.transform = Transform3D(Basis(d * sgn, u, w), base + pp * C.CLAP_SPINE * sgn + Vector3(0.0, -0.9 + 0.6 * minf(1.0, psi / 18.0) - sink, 0.0))
		i -= 1


# ------------------------------------------------------------------ player body (first person: arms + legs) and bot fighters

func _update_player_rigs(dt: float, feet: Vector3) -> void:
	var el: String = sim.element
	for nat in ["air", "earth", "water"]:
		body_rigs[nat].visible = nat == el
		arm_rigs[nat].visible = nat == el
	var br = body_rigs[el]
	var ar = arm_rigs[el]
	br.position = feet
	br.rotation.y = sim.yaw
	var hs := Vector2(sim.vel.x, sim.vel.z).length()
	var leg_stance := "idle"
	if sim.sliding:
		leg_stance = "slide"
	elif sim.swimming:
		leg_stance = "swim"
	elif sim.elevating or sim.wallrun:
		leg_stance = "elevator"
	elif sim.skating:
		leg_stance = "skate"
	elif sim.scooter:
		leg_stance = "scooter"
	elif sim.crouching:
		leg_stance = "crouch"
	br.animate(dt, {"speed": hs, "grounded": sim.on_ground, "stance": leg_stance, "swim": sim.swimming})
	var arm_stance := "fp_idle"
	if sim.swimming:
		arm_stance = "swim"
	elif sim.gliding:
		arm_stance = "glide"
	elif sim.breath_t > 0.0 or sim.jet_on:
		arm_stance = "breath"
	elif sim.octo_t > 0.0:
		arm_stance = "hold"
	elif sim.gathering:
		arm_stance = "suction"
	elif sim.charging:
		arm_stance = "charge"
	elif not sim.boulder_pull.is_empty():
		arm_stance = "hold"
	elif sim.armor_on:
		arm_stance = "armor"
	elif not world.held.is_empty():
		arm_stance = "hold"
	elif sim.shield_on:
		arm_stance = "shield"
	elif sim.suction_on:
		arm_stance = "suction"
	ar.animate(dt, {"speed": 0.0, "grounded": true, "stance": arm_stance})


func rebuild_bots() -> void:
	for k in _bot_views.keys():
		_bot_views[k]["root"].queue_free()
	_bot_views.clear()
	for b in world.bots:
		_bot_views[b] = _build_bot_view(b)
	update_bots()
