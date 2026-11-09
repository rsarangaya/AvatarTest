extends Node3D
## A low-poly humanoid built from boxes, animated procedurally. Faces -Z, origin at the feet, 1.8 m tall.
## Used for the player's first-person arms + legs, and for the bot fighters.

const DEG := PI / 180.0

# --- looks
var skin_col := Color(0.86, 0.66, 0.5)
var outfit_col := Color(0.95, 0.72, 0.18)
var trim_col := Color(0.85, 0.35, 0.1)
var dark_col := Color(0.25, 0.2, 0.18)
var nation := "air"

# --- joints
var hips: Node3D
var torso: Node3D
var head: Node3D
var sh_l: Node3D
var sh_r: Node3D
var el_l: Node3D
var el_r: Node3D
var hip_l: Node3D
var hip_r: Node3D
var kn_l: Node3D
var kn_r: Node3D
var _mats: Array = []
var _arm_nodes: Array = []
var _leg_nodes: Array = []
var _body_nodes: Array = []
var _all_meshes: Array = []

# --- animation state
var _cur := {}
var _phase := 0.0
var _attack := ""
var _attack_t := 0.0
var _attack_dur := 0.3
var _attack_side := 0
var stance := "idle"
var _t := 0.0
var _flash := 0.0

const HIP_Y := 0.86


func build(p_nation: String) -> void:
	nation = p_nation
	if nation == "air":
		outfit_col = Color(0.95, 0.74, 0.2)
		trim_col = Color(0.86, 0.38, 0.1)
		dark_col = Color(0.88, 0.5, 0.14)
	elif nation == "water":
		outfit_col = Color(0.2, 0.42, 0.74)
		trim_col = Color(0.84, 0.93, 0.98)
		dark_col = Color(0.13, 0.24, 0.44)
	else:
		outfit_col = Color(0.36, 0.5, 0.28)
		trim_col = Color(0.62, 0.5, 0.3)
		dark_col = Color(0.3, 0.25, 0.18)
	var skin := _mat(skin_col)
	var outfit := _mat(outfit_col)
	var trim := _mat(trim_col)
	var dark := _mat(dark_col)

	hips = Node3D.new()
	hips.position = Vector3(0, HIP_Y, 0)
	add_child(hips)
	torso = Node3D.new()
	hips.add_child(torso)
	_box(torso, Vector3(0.46, 0.58, 0.26), Vector3(0, 0.29, 0), outfit, _body_nodes)
	_box(torso, Vector3(0.48, 0.09, 0.28), Vector3(0, 0.03, 0), trim, _body_nodes)
	head = Node3D.new()
	head.position = Vector3(0, 0.6, 0)
	torso.add_child(head)
	_box(head, Vector3(0.27, 0.28, 0.27), Vector3(0, 0.18, 0), skin, _body_nodes)
	if nation == "air":
		_box(head, Vector3(0.07, 0.12, 0.02), Vector3(0, 0.27, -0.14), _mat(Color(0.3, 0.6, 0.95)), _body_nodes)   # the arrow
	else:
		_box(head, Vector3(0.29, 0.06, 0.29), Vector3(0, 0.27, 0), trim, _body_nodes)                               # headband
		_box(head, Vector3(0.28, 0.1, 0.1), Vector3(0, 0.33, 0.1), dark, _body_nodes)                               # topknot

	for side in [-1, 1]:
		var sh := Node3D.new()
		sh.position = Vector3(0.31 * side, 0.5, 0)
		torso.add_child(sh)
		_box(sh, Vector3(0.14, 0.3, 0.14), Vector3(0, -0.15, 0), outfit, _arm_nodes)
		var el := Node3D.new()
		el.position = Vector3(0, -0.3, 0)
		sh.add_child(el)
		_box(el, Vector3(0.115, 0.27, 0.115), Vector3(0, -0.135, 0), skin, _arm_nodes)
		_box(el, Vector3(0.13, 0.11, 0.13), Vector3(0, -0.32, 0), skin, _arm_nodes)
		if side < 0:
			sh_l = sh
			el_l = el
		else:
			sh_r = sh
			el_r = el
		var hp := Node3D.new()
		hp.position = Vector3(0.12 * side, 0, 0)
		hips.add_child(hp)
		_box(hp, Vector3(0.17, 0.42, 0.17), Vector3(0, -0.21, 0), dark, _leg_nodes)
		var kn := Node3D.new()
		kn.position = Vector3(0, -0.42, 0)
		hp.add_child(kn)
		_box(kn, Vector3(0.145, 0.42, 0.145), Vector3(0, -0.21, 0), dark, _leg_nodes)
		_box(kn, Vector3(0.16, 0.08, 0.28), Vector3(0, -0.41, -0.05), _mat(Color(0.2, 0.16, 0.13)), _leg_nodes)
		if side < 0:
			hip_l = hp
			kn_l = kn
		else:
			hip_r = hp
			kn_r = kn
	_cur = _pose_default()


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	m.emission = Color(1.0, 0.3, 0.2)
	_mats.append(m)
	return m


func _box(parent: Node3D, size: Vector3, at: Vector3, mat: Material, bucket: Array) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = at
	mi.material_override = mat
	parent.add_child(mi)
	bucket.append(mi)
	_all_meshes.append(mi)


# "full" everything, "legs" (first-person body: only legs visible, the rest casts a shadow), "arms" (first-person arms only)
func set_view(mode: String) -> void:
	for mi in _all_meshes:
		mi.visible = true
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if mode == "legs":
		for mi in _body_nodes + _arm_nodes:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	elif mode == "arms":
		for mi in _all_meshes:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for mi in _body_nodes + _leg_nodes:
			mi.visible = false


func flash(v: float) -> void:
	_flash = v
	for m in _mats:
		var sm: StandardMaterial3D = m
		sm.emission_enabled = v > 0.01
		sm.emission_energy_multiplier = v * 1.5


func hand_pos(side: int) -> Vector3:
	var el := el_l if side < 0 else el_r
	return el.to_global(Vector3(0, -0.34, 0))


func hand_mid() -> Vector3:
	return (hand_pos(-1) + hand_pos(1)) * 0.5


# Start a one-shot move. side: -1 left, 1 right, 0 either/both.
func trigger(name: String, dur := 0.3, side := 1) -> void:
	_attack = name
	_attack_t = 0.0
	_attack_dur = maxf(0.05, dur)
	_attack_side = side


func attacking() -> bool:
	return _attack != ""


# --- poses ---------------------------------------------------------------------------------------

func _pose_default() -> Dictionary:
	return {
		"ls": Vector3(0, 0, -4), "le": 8.0, "rs": Vector3(0, 0, 4), "re": 8.0,
		"hl": 0.0, "kl": 0.0, "hr": 0.0, "kr": 0.0,
		"torso": Vector3.ZERO, "drop": 0.0, "head": 0.0,
	}


# Arms forward by `fwd` degrees (90 = straight ahead), `yaw` swings them inward (+) or outward (-).
func _arms(p: Dictionary, fwd_l: float, fwd_r: float, yaw: float, elbow_l: float, elbow_r: float) -> void:
	p["ls"] = Vector3(fwd_l, -yaw, 0)
	p["rs"] = Vector3(fwd_r, yaw, 0)
	p["le"] = elbow_l
	p["re"] = elbow_r


func _stance_pose(s: String, speed: float, grounded: bool) -> Dictionary:
	var p := _pose_default()
	var sway := sin(_t * 1.8) * 2.0
	match s:
		"idle":
			p["ls"] = Vector3(sway, 0, -5)
			p["rs"] = Vector3(-sway, 0, 5)
		"fp_idle":            # first-person arms: relaxed, hands low in view
			_arms(p, 34.0 + sway, 34.0 - sway, 12, 78, 78)
		"ready":              # bending stance: fists up
			_arms(p, 55, 55, 10, 100, 100)
		"charge":
			var sh := sin(_t * 60.0) * 1.5
			_arms(p, 78 + sh, 78 - sh, 28, 62, 62)
		"armor":
			_arms(p, 62, 62, 52, 118, 118)
		"hold":
			_arms(p, 74, 74, 8, 30, 30)
		"shield":
			_arms(p, 70, 70, 34, 100, 100)
		"suction":
			p["rs"] = Vector3(92, 6, 0)
			p["re"] = 6.0
			p["ls"] = Vector3(60, -10, 0)
			p["le"] = 90.0
		"breath":
			_arms(p, 92, 92, -12, 4, 4)
			p["torso"] = Vector3(-8, 0, 0)
		"glide":
			p["ls"] = Vector3(10, 0, -82)
			p["rs"] = Vector3(10, 0, 82)
			p["le"] = 5.0
			p["re"] = 5.0
			p["torso"] = Vector3(25, 0, 0)
		"swim":
			var sw := sin(_phase * 0.8)
			p["ls"] = Vector3(100 + 70 * sw, 0, -10)
			p["rs"] = Vector3(100 - 70 * sw, 0, 10)
			p["le"] = 20.0
			p["re"] = 20.0
			p["hl"] = 20.0 * sw
			p["hr"] = -20.0 * sw
			p["torso"] = Vector3(30, 0, 0)
		"skate":
			p["ls"] = Vector3(15, 0, -38)
			p["rs"] = Vector3(15, 0, 38)
			p["torso"] = Vector3(10, 0, 0)
			p["drop"] = 0.1
			p["kl"] = 25.0
			p["kr"] = 25.0
		"scooter":
			p["ls"] = Vector3(25, 0, -40)
			p["rs"] = Vector3(25, 0, 40)
			p["hl"] = -35.0
			p["hr"] = 15.0
			p["kl"] = 40.0
			p["kr"] = 30.0
		"slide":
			p["torso"] = Vector3(-22, 0, 0)
			p["hl"] = 70.0
			p["hr"] = 80.0
			p["kl"] = 15.0
			p["kr"] = 5.0
			p["drop"] = 0.45
			p["ls"] = Vector3(30, 0, -30)
			p["rs"] = Vector3(30, 0, 30)
		"crouch":
			p["drop"] = 0.35
			p["hl"] = 55.0
			p["hr"] = 55.0
			p["kl"] = 100.0
			p["kr"] = 100.0
			p["ls"] = Vector3(40, 0, -8)
			p["rs"] = Vector3(40, 0, 8)
			p["torso"] = Vector3(15, 0, 0)
		"elevator":
			p["ls"] = Vector3(150, 0, -10)
			p["rs"] = Vector3(150, 0, 10)
			p["hl"] = 15.0
			p["hr"] = 15.0
			p["kl"] = 40.0
			p["kr"] = 40.0
	# locomotion overlays
	if s in ["idle", "ready", "charge", "armor", "hold", "shield"] or s == "run":
		pass
	if grounded and speed > 0.4 and s in ["idle", "ready", "charge", "armor", "hold", "shield", "suction"]:
		var amp := clampf(speed / 7.0, 0.0, 1.2)
		var sw2 := sin(_phase)
		p["hl"] = 42.0 * amp * sw2
		p["hr"] = -42.0 * amp * sw2
		p["kl"] = maxf(0.0, -sw2) * 55.0 * amp
		p["kr"] = maxf(0.0, sw2) * 55.0 * amp
		if s == "idle":
			p["ls"] = Vector3(-38.0 * amp * sw2, 0, -5)
			p["rs"] = Vector3(38.0 * amp * sw2, 0, 5)
			p["le"] = 15.0 + 35.0 * amp
			p["re"] = 15.0 + 35.0 * amp
			p["torso"] = Vector3(6.0 * amp, 0, 0)
	if not grounded and s in ["idle", "ready"]:
		p["hl"] = -25.0
		p["hr"] = 20.0
		p["kl"] = 50.0
		p["kr"] = 25.0
		p["ls"] = Vector3(25, 0, -35)
		p["rs"] = Vector3(25, 0, 35)
	return p


func _attack_pose(p: Dictionary, name: String, u: float, side: int) -> void:
	var e := sin(clampf(u, 0.0, 1.0) * PI)                 # 0 -> 1 -> 0
	var ext := clampf(u * 2.2, 0.0, 1.0)                    # quick extension then hold
	match name:
		"punch":
			var s2 := side if side != 0 else 1
			var key := "rs" if s2 > 0 else "ls"
			var ekey := "re" if s2 > 0 else "le"
			p[key] = Vector3(lerpf(25, 98, e), (14.0 if s2 > 0 else -14.0), 0)
			p[ekey] = lerpf(110, 4, e)
			p["torso"] = Vector3(0, (-22.0 if s2 > 0 else 22.0) * e, 0)
			var other := "ls" if s2 > 0 else "rs"
			p[other] = Vector3(55, 0, 0)
			p["le" if s2 > 0 else "re"] = 105.0
		"kick":
			p["hr"] = lerpf(-10, 88, e)
			p["kr"] = lerpf(70, 8, e)
			p["torso"] = Vector3(-14 * e, 0, 0)
			p["ls"] = Vector3(40, 0, -30)
			p["rs"] = Vector3(40, 0, 30)
			p["hl"] = -8.0
		"sweep":
			var yy := lerpf(55, -65, clampf(u * 1.3, 0.0, 1.0))
			p["rs"] = Vector3(92, yy, 0)
			p["ls"] = Vector3(92, yy * 0.8, 0)
			p["re"] = 6.0
			p["le"] = 6.0
			p["torso"] = Vector3(0, lerpf(30, -35, u), 0)
			p["drop"] = 0.12 * e
			p["hl"] = 20.0
			p["kl"] = 30.0
		"stomp":
			p["ls"] = Vector3(lerpf(150, 25, clampf(u * 1.4, 0.0, 1.0)), 0, -10)
			p["rs"] = Vector3(lerpf(150, 25, clampf(u * 1.4, 0.0, 1.0)), 0, 10)
			p["hl"] = lerpf(80, 0, clampf(u * 1.6, 0.0, 1.0))
			p["kl"] = lerpf(80, 0, clampf(u * 1.6, 0.0, 1.0))
			p["drop"] = 0.18 * clampf(u * 2.0 - 0.8, 0.0, 1.0)
		"throw":
			var back := lerpf(-50, 105, ext)
			p["rs"] = Vector3(back, 8, 0)
			p["re"] = lerpf(100, 6, ext)
			p["ls"] = Vector3(60, -20, 0)
			p["le"] = 70.0
			p["torso"] = Vector3(0, lerpf(24, -18, ext), 0)
		"thrust":
			_arms(p, lerpf(30, 96, ext), lerpf(30, 96, ext), lerpf(30, 4, ext), lerpf(110, 4, ext), lerpf(110, 4, ext))
			p["torso"] = Vector3(-6 * e, 0, 0)
		"slash":
			var yy2 := lerpf(-45, 45, ext)
			p["rs"] = Vector3(90, yy2, 0)
			p["re"] = 6.0
			p["ls"] = Vector3(50, -15, 0)
			p["le"] = 90.0
		"raise":
			var up := lerpf(40, 160, clampf(u * 1.6, 0.0, 1.0))
			p["ls"] = Vector3(up, 0, -12)
			p["rs"] = Vector3(up, 0, 12)
			p["le"] = 6.0
			p["re"] = 6.0
		"slam":
			var dn := lerpf(170, 20, clampf(u * 1.8, 0.0, 1.0))
			p["ls"] = Vector3(dn, 0, -10)
			p["rs"] = Vector3(dn, 0, 10)
			p["torso"] = Vector3(lerpf(-10, 25, ext), 0, 0)
			p["drop"] = 0.15 * ext
		"gust":
			var f := lerpf(-40, 30, ext)
			p["ls"] = Vector3(f, 0, lerpf(-6, -50, ext))
			p["rs"] = Vector3(f, 0, lerpf(6, 50, ext))
		"hurt":
			p["torso"] = Vector3(-20 * e, 0, 0)
			p["ls"] = Vector3(40, 0, -50)
			p["rs"] = Vector3(40, 0, 50)


func animate(dt: float, st: Dictionary) -> void:
	_t += dt
	var speed: float = st.get("speed", 0.0)
	var grounded: bool = st.get("grounded", true)
	if grounded:
		_phase += speed * dt * 1.25
	elif st.get("swim", false):
		_phase += (1.5 + speed * 0.4) * dt * 2.0
	var s: String = st.get("stance", stance)
	var p := _stance_pose(s, speed, grounded)
	var atk_w := 0.0
	if _attack != "":
		_attack_t += dt
		var u := _attack_t / _attack_dur
		if u >= 1.0:
			_attack = ""
		else:
			_attack_pose(p, _attack, u, _attack_side)
			atk_w = 1.0
	# smooth toward the target pose (faster while attacking so strikes snap)
	var k := 1.0 - exp(-(34.0 if atk_w > 0.0 else 14.0) * dt)
	for key in p.keys():
		var tv = p[key]
		if _cur.has(key):
			_cur[key] = lerp(_cur[key], tv, k)
		else:
			_cur[key] = tv
	sh_l.rotation = _v(_cur["ls"])
	sh_r.rotation = _v(_cur["rs"])
	el_l.rotation = Vector3(_cur["le"] * DEG, 0, 0)
	el_r.rotation = Vector3(_cur["re"] * DEG, 0, 0)
	hip_l.rotation = Vector3(_cur["hl"] * DEG, 0, 0)
	hip_r.rotation = Vector3(_cur["hr"] * DEG, 0, 0)
	kn_l.rotation = Vector3(-_cur["kl"] * DEG, 0, 0)
	kn_r.rotation = Vector3(-_cur["kr"] * DEG, 0, 0)
	torso.rotation = _v(_cur["torso"])
	hips.position.y = HIP_Y - float(_cur["drop"])
	if _flash > 0.0:
		flash(maxf(0.0, _flash - dt * 6.0))


func _v(d: Vector3) -> Vector3:
	return Vector3(d.x * DEG, d.y * DEG, d.z * DEG)
