extends Node3D
## The 3D backdrop of the main menu: the four nations' benders in a loose group, a slow camera drift, a little nation effect
## each, one light and a plain ground. Cheap by design (4 rigs, shared meshes and materials, no allocation per frame).
## Low quality: static poses, no effects, no shadows. set_covered(true) hides and stops it (text screens, game start).

const RigScript = preload("res://scripts/rig.gd")
const Settings = preload("res://scripts/settings.gd")

const NATIONS := ["air", "earth", "water", "fire"]
const SPOTS := [Vector3(-6.2, 0.0, -0.4), Vector3(-3.6, 0.0, 0.7), Vector3(3.6, 0.0, 0.3), Vector3(6.2, 0.0, -0.5)]
const YAWS := [0.35, 0.12, -0.15, -0.4]          # extra turn (rad) so the group faces slightly inward

var rigs: Array = []                 # the four rigs (tests count them)
var cam: Camera3D
var _t := 0.0
var _animated := true
var _air: Array = []
var _rocks: Array = []
var _beads: Array = []
var _flames: Array = []
var _sphere: SphereMesh
var _env: Environment
var _we: WorldEnvironment
var _sun: DirectionalLight3D
var _quality := -1


func _ready() -> void:
	var q: int = Settings.quality
	_quality = q
	_animated = q > 0
	_build_world(q)
	for i in range(4):
		var rig = RigScript.new()
		rig.build(NATIONS[i])
		rig.position = SPOTS[i]
		rig.rotation.y = PI + float(YAWS[i])
		add_child(rig)
		rigs.append(rig)
	if _animated:
		_build_fx()
	_pose(0.0)
	_camera(0.0)
	set_process(_animated)


func _build_world(q: int) -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.04, 0.09, 0.20)
	sky_mat.sky_horizon_color = Color(0.22, 0.30, 0.38)
	sky_mat.ground_horizon_color = Color(0.16, 0.22, 0.22)
	sky_mat.ground_bottom_color = Color(0.05, 0.08, 0.07)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.32
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.16, 0.24, 0.30)
	env.fog_density = 0.02
	_env = env
	_we = WorldEnvironment.new()
	_we.environment = env
	add_child(_we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35.0, -30.0, 0.0)
	sun.light_color = Color(1.0, 0.88, 0.7)
	sun.light_energy = 0.75
	sun.shadow_enabled = q > 0
	sun.directional_shadow_max_distance = 16.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_sun = sun
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(120.0, 120.0)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.11, 0.19, 0.12)
	gm.roughness = 1.0
	ground.material_override = gm
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)
	cam = Camera3D.new()
	cam.fov = 42.0
	cam.far = 150.0
	add_child(cam)
	cam.make_current()


func _glow(c: Color, a: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(c.r, c.g, c.b, a)
	return m


func _build_fx() -> void:
	_sphere = SphereMesh.new()
	_sphere.radius = 0.5
	_sphere.height = 1.0
	_sphere.radial_segments = 8
	_sphere.rings = 4
	var air_m := _glow(Color(0.9, 0.97, 1.0), 0.55)
	var rock_m := StandardMaterial3D.new()
	rock_m.albedo_color = Color(0.5, 0.4, 0.3)
	rock_m.roughness = 1.0
	var water_m := _glow(Color(0.4, 0.7, 1.0), 0.8)
	var fire_m := _glow(Color(1.0, 0.55, 0.15), 0.85)
	for k in range(8):
		_air.append(_bit(rigs[0], air_m, 0.07 + 0.01 * (k % 3), false))
	for k in range(5):
		_rocks.append(_bit(rigs[1], rock_m, 0.16 + 0.03 * (k % 3), true))
	for k in range(7):
		_beads.append(_bit(rigs[2], water_m, 0.13 - 0.008 * k, false))
	for k in range(3):
		_flames.append(_bit(rigs[3], fire_m, 0.2, false))


func _bit(parent: Node3D, mat: Material, size: float, shadow: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _sphere
	mi.material_override = mat
	mi.scale = Vector3.ONE * size * 2.0
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


# Covered: hidden, not processed and the sky/fog environment is detached too (it would still be drawn into the view).
# Uncovered: a graphics-quality change made meanwhile (Options) is applied.
func set_covered(covered: bool) -> void:
	visible = not covered
	_we.environment = null if covered else _env
	if not covered:
		_apply_quality(Settings.quality)
		cam.make_current()
	set_process(not covered and _animated)


func _apply_quality(q: int) -> void:
	if q == _quality:
		return
	_quality = q
	_animated = q > 0
	_sun.shadow_enabled = _animated
	if _animated and _air.is_empty():
		_build_fx()
	for group in [_air, _rocks, _beads, _flames]:
		for n in group:
			(n as Node3D).visible = _animated
	_pose(0.0)
	_camera(0.0)


func _process(dt: float) -> void:
	_t += dt
	_pose(_t)
	_camera(_t)
	_effects(_t)


func _camera(t: float) -> void:
	var a := sin(t * 0.13) * 0.2
	cam.position = Vector3(sin(a) * 10.5, 1.5 + sin(t * 0.09) * 0.1, cos(a) * 10.5)
	cam.look_at(Vector3(0.0, 1.15, 0.0))


# Each bender holds a signature pose with a slow breathing sway (joint angles in degrees; the rig faces -Z).
func _pose(t: float) -> void:
	var br := sin(t * 1.3)
	var sw := sin(t * 0.7)
	var s := sin(t * 0.9)
	_apply_pose(rigs[0], Vector3(18.0 + br * 3.0, -10.0, -22.0), 18.0, Vector3(18.0 + br * 3.0, 10.0, 22.0), 18.0,
			Vector3(-8.0 + br * 2.0, sw * 6.0, 0.0), 0.0, 0.0, 0.0, 0.0, 0.0)
	_apply_pose(rigs[1], Vector3(58.0 + br * 2.0, -10.0, 0.0), 100.0, Vector3(58.0 + br * 2.0, 10.0, 0.0), 100.0,
			Vector3(2.0, sw * 2.0, 0.0), 32.0, 62.0, 32.0, 62.0, 0.26 + br * 0.01)
	_apply_pose(rigs[2], Vector3(72.0 + 28.0 * s, -18.0, 0.0), 24.0, Vector3(40.0 - 26.0 * s, 20.0, 0.0), 30.0,
			Vector3(0.0, 12.0 * s, 0.0), 8.0, 10.0, -6.0, 8.0, 0.04)
	_apply_pose(rigs[3], Vector3(50.0, -12.0, 0.0), 110.0, Vector3(84.0 + br * 2.0, 4.0, 0.0), 36.0,
			Vector3(0.0, -14.0 + sw * 2.0, 0.0), 26.0, 46.0, -18.0, 20.0, 0.14 + br * 0.008)


func _apply_pose(r, ls: Vector3, le: float, rs: Vector3, re: float, torso: Vector3, hl: float, kl: float, hr: float, kr: float, drop: float) -> void:
	r.sh_l.rotation = Vector3(deg_to_rad(ls.x), deg_to_rad(-ls.y), deg_to_rad(ls.z))
	r.sh_r.rotation = Vector3(deg_to_rad(rs.x), deg_to_rad(-rs.y), deg_to_rad(rs.z))
	r.el_l.rotation.x = deg_to_rad(le)
	r.el_r.rotation.x = deg_to_rad(re)
	r.torso.rotation = Vector3(deg_to_rad(torso.x), deg_to_rad(torso.y), deg_to_rad(torso.z))
	r.hip_l.rotation.x = deg_to_rad(hl)
	r.hip_r.rotation.x = deg_to_rad(hr)
	r.kn_l.rotation.x = -deg_to_rad(kl)
	r.kn_r.rotation.x = -deg_to_rad(kr)
	r.hips.position.y = RigScript.HIP_Y - drop


func _effects(t: float) -> void:
	for k in range(_air.size()):
		var a := t * 1.6 + k * 0.85
		var rad := 0.75 + 0.05 * k
		(_air[k] as Node3D).position = Vector3(cos(a) * rad, 0.25 + 0.2 * k, sin(a) * rad)
	for k in range(_rocks.size()):
		var a := t * 0.8 + k * 1.2566
		(_rocks[k] as Node3D).position = Vector3(cos(a), 0.9 + 0.12 * sin(t * 1.5 + k), sin(a))
	for k in range(_beads.size()):
		var a := t * 1.1 - k * 0.3
		(_beads[k] as Node3D).position = Vector3(cos(a) * 0.85, 1.0 + 0.3 * sin(a * 2.0), sin(a) * 0.85)
	for k in range(_flames.size()):
		var f := 0.75 + 0.25 * sin(t * 17.0 + k * 2.3) * sin(t * 11.0 + k)
		var n := _flames[k] as Node3D
		n.position = Vector3(-0.22 + 0.05 * k, 1.18 + 0.1 * k * f, -0.62 - 0.05 * k)
		n.scale = Vector3.ONE * (0.4 - 0.08 * k) * f
