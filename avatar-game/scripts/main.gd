extends Node3D
## Scene setup, input, camera, HUD and the main loop.
## Gameplay lives in player_sim.gd / world.gd, visual effects in fx.gd.

const C = preload("res://scripts/config.gd")
const WorldScript = preload("res://scripts/world.gd")
const SimScript = preload("res://scripts/player_sim.gd")
const FxScript = preload("res://scripts/fx.gd")
const TerrainViewScript = preload("res://scripts/terrain_view.gd")
const Settings = preload("res://scripts/settings.gd")
const Session = preload("res://scripts/session.gd")
const UI = preload("res://scripts/ui.gd")
const TutorialView = preload("res://scripts/tutorial_view.gd")
const OptionsUI = preload("res://scripts/options_ui.gd")
const HudSlot = preload("res://scripts/hud_slot.gd")

const TICK := 1.0 / C.TICK_RATE

var world
var sim
var inp
var fx
var terrain_view

var cam: Camera3D
var captured := false
var accumulator := 0.0
var prev_pos := Vector3.ZERO
var respawn_queued := false
const ROUND_DELAY := 5.0
var round_label: Label
var debug_label: Label             # small tag while the hidden debug mode is on (flashes big when it is switched)
var debug_flash := 0.0
var pillar_label: Label            # earthbenders: how many pillars are in hand
var round_t := 0.0                 # seconds until a duel round starts (the fighters are frozen until then)
var round_msg := ""
var clock := 0.0

# camera rig
var rig_eye := C.EYE_STAND
var rig_kick := 0.0
var rig_roll := 0.0
var rig_fov: float = Settings.fov
var rig_fov_punch := 0.0
var rig_shake := 0.0

# HUD
var speed_label: Label
var state_label: Label
var info_label: Label
var chi_bar: ProgressBar
var hp_bar: ProgressBar
var hp_label: Label
var ult_bar: ProgressBar
var ult_label: Label
var element_label: Label
var chi_text: Label
var hints_label: Label
var charge_bar: ProgressBar
var slot_rows := {}                    # "air" / "earth" / "water" / "octo" -> HBoxContainer of ability indicators
var slot_nodes := {}                   # the same keys -> Array of HudSlot (order matches _update_slots)
var hit_marker: Label
var hurt_flash: ColorRect
var water_tint: ColorRect
# the sky darkens while an ultimate is running (yours or the duel enemy's)
const SKY_DAY := {"top": Color(0.30, 0.56, 0.90), "horizon": Color(0.74, 0.86, 0.95), "ground": Color(0.45, 0.55, 0.40),
		"fog": Color(0.77, 0.88, 0.96), "ambient": 0.45, "sun": 0.8}
const SKY_DARK := {"top": Color(0.02, 0.03, 0.09), "horizon": Color(0.07, 0.08, 0.15), "ground": Color(0.04, 0.05, 0.07),
		"fog": Color(0.06, 0.08, 0.14), "ambient": 0.14, "sun": 0.2}
const SKY_FADE_IN := 2.0               # how fast it darkens (1 / seconds)
const SKY_FADE_OUT := 1.0              # and how fast the day comes back
var env: Environment
var sky_mat: ProceduralSkyMaterial
var sun: DirectionalLight3D
var sky_dark := 0.0                    # 0 = day, 1 = fully darkened
var _quality_applied := -1

var overlay: Control                   # the pause menu
var pause_center: CenterContainer
var pause_box: VBoxContainer
var pause_info: Label
var pause_sub: Control = null          # the "my moves" / options screen when one is open inside the pause menu
var hit_t := 0.0
var hurt_t := 0.0


func _ready() -> void:
	Settings.ensure_loaded()
	world = WorldScript.new(1337)
	sim = SimScript.new(world)
	inp = SimScript.InputState.new()
	sim.debug_god = Settings.debug_enabled
	sim.debug_nocd = Settings.debug_enabled
	_apply_session()
	_build_environment()
	_build_terrain()
	_build_camera()
	fx = FxScript.new()
	add_child(fx)
	fx.setup(world, sim, cam)
	_apply_quality()
	_build_hud()
	prev_pos = sim.pos
	_capture(true)


# ------------------------------------------------------------------ scene building

func _build_environment() -> void:
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.30, 0.56, 0.90)
	sky_mat.sky_horizon_color = Color(0.74, 0.86, 0.95)
	sky_mat.ground_horizon_color = Color(0.74, 0.86, 0.95)
	sky_mat.ground_bottom_color = Color(0.45, 0.55, 0.40)
	sky_mat.sun_angle_max = 18.0
	sky_mat.sun_curve = 0.12
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.45
	env.fog_enabled = true
	env.fog_light_color = Color(0.77, 0.88, 0.96)
	env.fog_density = 0.0035
	env.fog_sun_scatter = 0.25
	env.fog_aerial_perspective = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.12
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -35.0, 0.0)
	sun.light_energy = 0.8
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 130.0
	add_child(sun)


# Is any ultimate running right now? Yours (breath, bomb or quake dive, quake, tidal wave, octopus form), an earth clap
# or tidal wave anywhere, or one cast by the duel enemy.
func _ult_active() -> bool:
	if sim.breath_t > 0.0 or sim.quake_t > 0.0 or sim.octo_t > 0.0 or sim.ult_lock > 0.0 or not sim.slam.is_empty():
		return true
	if sim.rush_t > 0.0 or sim.light_t >= 0.0:
		return true
	for j in world.jobs:
		if j["kind"] == "clap" or j["kind"] == "tide":
			return true
	for b in world.bots:
		if not b.alive:
			continue
		if b.breath_t > 0.0 or b.octo_t > 0.0 or b.light_t > 0.0:
			return true
		for pe in b.pending:
			if String(pe["kind"]).begins_with("clap"):
				return true
	return false


func _update_ult_sky(dt: float) -> void:
	var target := 1.0 if _ult_active() else 0.0
	sky_dark = move_toward(sky_dark, target, dt * (SKY_FADE_IN if target > sky_dark else SKY_FADE_OUT))
	sky_mat.sky_top_color = SKY_DAY["top"].lerp(SKY_DARK["top"], sky_dark)
	sky_mat.sky_horizon_color = SKY_DAY["horizon"].lerp(SKY_DARK["horizon"], sky_dark)
	sky_mat.ground_horizon_color = SKY_DAY["horizon"].lerp(SKY_DARK["horizon"], sky_dark)
	sky_mat.ground_bottom_color = SKY_DAY["ground"].lerp(SKY_DARK["ground"], sky_dark)
	env.fog_light_color = SKY_DAY["fog"].lerp(SKY_DARK["fog"], sky_dark)
	env.ambient_light_energy = lerpf(SKY_DAY["ambient"], SKY_DARK["ambient"], sky_dark)
	sun.light_energy = lerpf(SKY_DAY["sun"], SKY_DARK["sun"], sky_dark)


# Graphics quality (Options): anti-aliasing, shadows and how far the ground and the bots are drawn. Called again
# whenever the setting changes, also in a running game.
func _apply_quality() -> void:
	_quality_applied = Settings.quality
	var q: Dictionary = Settings.profile()
	get_viewport().msaa_3d = Viewport.MSAA_2X if int(q["msaa"]) == 2 else Viewport.MSAA_DISABLED
	sun.shadow_enabled = float(q["shadow_dist"]) > 0.0
	sun.directional_shadow_max_distance = maxf(float(q["shadow_dist"]), 1.0)
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if int(q["shadow_splits"]) == 4 \
			else DirectionalLight3D.SHADOW_ORTHOGONAL
	cam.far = float(q["far"])
	terrain_view.set_view_range(float(q["terrain_range"]))
	fx.bot_range = float(q["bot_range"])


func _build_terrain() -> void:
	terrain_view = TerrainViewScript.new()
	add_child(terrain_view)
	terrain_view.setup(world.terrain)


func _build_camera() -> void:
	cam = Camera3D.new()
	cam.fov = Settings.fov
	cam.near = 0.05
	cam.far = 2200.0
	add_child(cam)
	cam.make_current()


# ------------------------------------------------------------------ HUD

func _make_label(font_size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _make_bar(fill_color: Color, maximum: float) -> ProgressBar:
	var b := ProgressBar.new()
	b.min_value = 0.0
	b.max_value = maximum
	b.show_percentage = false
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.set_corner_radius_all(5)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.45)
	bg.set_corner_radius_all(5)
	b.add_theme_stylebox_override("fill", fill)
	b.add_theme_stylebox_override("background", bg)
	return b


func _anchor(c: Control, ax: float, ay: float, l: float, t: float, r: float, bt: float) -> void:
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.offset_left = l
	c.offset_top = t
	c.offset_right = r
	c.offset_bottom = bt


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	hurt_flash = ColorRect.new()
	hurt_flash.color = Color(0.9, 0.1, 0.1, 0.0)
	hurt_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	hurt_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hurt_flash)

	water_tint = ColorRect.new()
	water_tint.color = Color(0.05, 0.3, 0.45, 0.0)
	water_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	water_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(water_tint)

	var cross := ColorRect.new()
	cross.color = Color(1, 1, 1, 0.85)
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor(cross, 0.5, 0.5, -2.0, -2.0, 2.0, 2.0)
	root.add_child(cross)

	hit_marker = _make_label(26)
	hit_marker.text = "X"
	hit_marker.modulate = Color(1.0, 0.4, 0.3, 0.0)
	hit_marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anchor(hit_marker, 0.5, 0.5, -20.0, -20.0, 20.0, 20.0)
	root.add_child(hit_marker)

	round_label = _make_label(44)
	round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	round_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	round_label.add_theme_constant_override("outline_size", 8)
	_anchor(round_label, 0.5, 0.0, -420.0, 120.0, 420.0, 230.0)
	round_label.visible = false
	root.add_child(round_label)

	debug_label = _make_label(22)
	debug_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	debug_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	_anchor(debug_label, 0.5, 0.0, -300.0, 8.0, 300.0, 40.0)
	debug_label.visible = false
	root.add_child(debug_label)

	pillar_label = _make_label(18)
	pillar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pillar_label.add_theme_color_override("font_color", Color(0.9, 0.78, 0.55))
	_anchor(pillar_label, 0.5, 1.0, -200.0, -118.0, 200.0, -94.0)
	pillar_label.visible = false
	root.add_child(pillar_label)

	_build_slots(root)

	charge_bar = _make_bar(Color(0.85, 0.97, 1.0), 1.0)
	_anchor(charge_bar, 0.5, 0.5, -60.0, 34.0, 60.0, 42.0)
	charge_bar.visible = false
	root.add_child(charge_bar)

	# bottom-left: HP, speed, state
	hp_bar = _make_bar(Color(0.45, 0.9, 0.5), C.PLAYER_HP)
	_anchor(hp_bar, 0.0, 1.0, 22.0, -138.0, 282.0, -124.0)
	root.add_child(hp_bar)
	hp_label = _make_label(11)
	_anchor(hp_label, 0.0, 1.0, 22.0, -156.0, 282.0, -140.0)
	root.add_child(hp_label)
	var box := VBoxContainer.new()
	_anchor(box, 0.0, 1.0, 22.0, -120.0, 360.0, -16.0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(box)
	speed_label = _make_label(40)
	state_label = _make_label(15)
	info_label = _make_label(11)
	info_label.modulate = Color(1, 1, 1, 0.6)
	box.add_child(speed_label)
	box.add_child(state_label)
	box.add_child(info_label)

	# bottom-centre: chi
	chi_bar = _make_bar(Color(0.72, 0.92, 1.0), C.CHI_MAX)
	_anchor(chi_bar, 0.5, 1.0, -130.0, -40.0, 130.0, -28.0)
	root.add_child(chi_bar)
	chi_text = _make_label(11)
	chi_text.text = "CHI"
	_anchor(chi_text, 0.5, 1.0, -130.0, -58.0, 130.0, -42.0)
	root.add_child(chi_text)

	# bottom-right: ultimate
	ult_label = _make_label(14)
	ult_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_anchor(ult_label, 1.0, 1.0, -360.0, -74.0, -22.0, -52.0)
	root.add_child(ult_label)
	ult_bar = _make_bar(Color(1.0, 0.85, 0.4), C.ULT_MAX)
	_anchor(ult_bar, 1.0, 1.0, -282.0, -46.0, -22.0, -30.0)
	root.add_child(ult_bar)
	hints_label = _make_label(11)
	hints_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hints_label.modulate = Color(1, 1, 1, 0.55)
	_anchor(hints_label, 1.0, 1.0, -760.0, -24.0, -22.0, -8.0)
	root.add_child(hints_label)
	element_label = _make_label(22)
	element_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anchor(element_label, 0.5, 1.0, -300.0, -92.0, 300.0, -62.0)
	root.add_child(element_label)

	_build_pause_menu(root)


# Ability indicators (cooldown sweep, ready flash, dimmed when unusable): one row per nation plus one for octopus form.
func _build_slots(root: Control) -> void:
	var air := Color(0.78, 0.93, 1.0)
	var earth := Color(0.85, 0.62, 0.32)
	var water := Color(0.45, 0.78, 1.0)
	var gold := Color(1.0, 0.85, 0.4)
	var fire := Color(1.0, 0.55, 0.25)
	var defs := {
		"air": [["PUNCH", "LMB", air], ["SLICE", "RMB", air], ["SHIELD", "ability_e", air], ["SUCTION", "ability_f", air], ["SCOOTER", "ability_q", air], ["GUST", "2xSPC", air], ["DASH", "ability_z", air], ["ULT", "ultimate", gold]],
		"earth": [["ROCK", "LMB", earth], ["BOULDER", "RMB", earth], ["BARRAGE", "ability_z", earth], ["WALL", "ability_e", earth], ["PILLAR", "ability_f", earth], ["ARMOR", "ability_v", earth], ["SKATE", "ability_q", earth], ["ULT", "ultimate", gold]],
		"water": [["WHIP", "LMB", water], ["HEAL", "RMB", water], ["SHARDS", "ability_z", water], ["ICE WALL", "ability_e", water], ["DISC", "ability_e", water], ["SKATE", "ability_q", water], ["FREEZE", "ability_freeze", water], ["PROPEL", "SPC", water], ["ULT", "ultimate", gold]],
		"fire": [["FIREBALL", "LMB", fire], ["BURST", "RMB", fire], ["KICK", "ability_z", fire], ["RING", "ability_f", fire], ["ULT", "ultimate", gold]],
		"octo": [["L ARM", "LMB", water], ["R ARM", "RMB", water], ["SLAM", "ability_e", water], ["GRAB", "ability_q", water], ["ULT", "ultimate", gold]],
	}
	for k in defs:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 6)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_anchor(row, 0.5, 1.0, -260.0, -176.0, 260.0, -126.0)
		row.visible = false
		root.add_child(row)
		var nodes := []
		for d in defs[k]:
			var s := HudSlot.new()
			s.title = String(d[0])
			s.set_key(String(d[1]))
			s.accent = d[2]
			row.add_child(s)
			nodes.append(s)
		slot_rows[k] = row
		slot_nodes[k] = nodes


# Feeds the current row. Reads sim values only, so debug mode (no cooldowns) just shows everything ready.
func _update_slots(dt: float) -> void:
	var el: String = sim.element
	if el == "water" and sim.octo_t > 0.0:
		el = "octo"
	for k in slot_rows:
		slot_rows[k].visible = k == el
	var s: Array = slot_nodes[el]
	var chi: float = sim.chi
	match el:
		"air":
			s[0].update_slot(dt, sim.punch_cd, C.PUNCH_COOLDOWN, chi >= C.PUNCH_COST, false)
			s[1].update_slot(dt, sim.slice_cd, C.SLICE_COOLDOWN, chi >= C.SLICE_COST, false)
			s[2].update_slot(dt, 0.0, 0.0, chi >= C.SHIELD_MIN_CHI or sim.shield_on, sim.shield_on)
			s[3].update_slot(dt, 0.0, 0.0, chi >= C.SUCTION_MIN_CHI or sim.suction_on, sim.suction_on)
			s[4].update_slot(dt, 0.0, 0.0, chi > 0.0 or sim.scooter, sim.scooter)
			s[5].update_slot(dt, sim.gust_cd, C.GUST_COOLDOWN, chi >= C.GUST_COST, false)
			s[6].update_slot(dt, sim.dash_cd, C.ADASH_COOLDOWN, chi >= C.ADASH_COST and (sim.on_ground or not sim.dash_air_used), sim.dash_t > 0.0)
		"earth":
			s[0].update_slot(dt, sim.punch_cd, C.ROCK_COOLDOWN, chi >= C.ROCK_COST, false)
			s[1].update_slot(dt, sim.boulder_cd, C.BOULDER_COOLDOWN, chi >= C.BOULDER_COST, false)
			s[2].update_slot(dt, sim.barrage_cd, C.BARRAGE_COOLDOWN, chi >= C.BARRAGE_COST, false)
			s[3].update_slot(dt, sim.wall_cd, C.WALL_COOLDOWN, chi >= C.WALL_COST, false)
			# pillars: the short gap between two, or (with none left) the wait for the next charge to come back
			if sim.pillar_charges > 0:
				s[4].update_slot(dt, sim.pillar_cd, C.PILLAR_COOLDOWN, chi >= C.PILLAR_COST, false, sim.pillar_charges)
			else:
				s[4].update_slot(dt, C.PILLAR_RECHARGE - sim.pillar_recharge, C.PILLAR_RECHARGE, false, false, 0)
			s[5].update_slot(dt, sim.armor_cd, C.ARMOR_TOGGLE_CD, chi >= C.ARMOR_COST or sim.armor_on, sim.armor_on)
			s[6].update_slot(dt, 0.0, 0.0, chi > 0.0 or sim.skating, sim.skating)
		"water":
			s[0].update_slot(dt, sim.punch_cd, C.WHIP_COOLDOWN, chi >= sim._cost(C.WHIP_COST), false)
			s[1].update_slot(dt, sim.heal_cd, C.HEAL_COOLDOWN, chi >= sim._cost(C.HEAL_COST) and sim.hp < C.PLAYER_HP - 0.5, sim.heal_left > 0.0)
			s[2].update_slot(dt, sim.barrage_cd, C.SHARD_COOLDOWN, chi >= sim._cost(C.SHARD_COST), false)
			s[3].update_slot(dt, sim.iwall_cd, C.ICE_WALL_COOLDOWN, chi >= sim._cost(C.ICE_WALL_COST), false)
			s[4].update_slot(dt, sim.disc_cd, C.DISC_COOLDOWN, chi >= sim._cost(C.DISC_COST), false)
			s[5].update_slot(dt, 0.0, 0.0, chi >= sim._cost(C.ICE_SKATE_COST) or sim.skating, sim.skating)
			s[6].update_slot(dt, 0.0, 0.0, true, sim.freezing)
			s[7].update_slot(dt, sim.propel_cd, C.PROPEL_COOLDOWN, chi >= sim._cost(C.PROPEL_MIN), sim.propelling)
		"fire":
			var hot_ok: bool = sim.overheat_t <= 0.0
			s[0].update_slot(dt, sim.fpunch_cd, C.FPUNCH_COOLDOWN, hot_ok, sim.fcharging)
			s[1].update_slot(dt, sim.fburst_cd, C.FBURST_COOLDOWN, hot_ok, false)
			s[2].update_slot(dt, sim.dash_cd, C.FKICK_COOLDOWN, hot_ok and (sim.on_ground or not sim.dash_air_used), sim.dash_t > 0.0)
			s[3].update_slot(dt, sim.ring_cd, C.RING_COOLDOWN, hot_ok and sim.soak_t <= 0.0, sim.guard_t > 0.0)
		"octo":
			s[0].update_slot(dt, sim.octo_cd, C.OCTO_SWIPE_COOLDOWN, true, false)
			s[1].update_slot(dt, sim.octo_cd_r, C.OCTO_SWIPE_COOLDOWN, true, false)
			s[2].update_slot(dt, sim.octo_slam_cd, C.OCTO_SLAM_COOLDOWN, true, false)
			s[3].update_slot(dt, sim.octo_q_cd, C.OCTO_GRAB_COOLDOWN, true, false)
	# the ultimate meter: the sweep is what is still missing, it flashes when full
	s[s.size() - 1].update_slot(dt, C.ULT_MAX - sim.ult, C.ULT_MAX, sim.ult_ready(), sim.octo_t > 0.0 or sim.breath_t > 0.0 or sim.quake_t > 0.0 or sim.rush_t > 0.0 or sim.light_t >= 0.0, -1, false)


# The pause menu: Resume / Restart / My moves / Options / Quit to menu. "My moves" and "Options" open inside it.
func _build_pause_menu(root: Control) -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.05, 0.10, 0.84)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.theme = UI.make_theme()
	root.add_child(dim)
	pause_center = CenterContainer.new()
	pause_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(pause_center)
	pause_box = VBoxContainer.new()
	pause_box.add_theme_constant_override("separation", 14)
	pause_center.add_child(pause_box)
	var title := UI.label("PAUSED", 52)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_box.add_child(title)
	pause_info = UI.label("", 16, UI.DIM)
	pause_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_box.add_child(pause_info)
	for entry in [["RESUME", _resume], ["RESTART", _reset_round], ["MY MOVES", _show_moves], ["OPTIONS", _show_options],
			["QUIT TO MENU", _quit_to_menu]]:
		var b := UI.button(String(entry[0]), Vector2(380.0, 54.0))
		b.pressed.connect(entry[1])
		pause_box.add_child(b)
	overlay = dim


# ------------------------------------------------------------------ session, pause menu, input

# Set up the game the way the menus asked for: your nation, the bots or the duel enemy.
func _apply_session() -> void:
	sim.set_nation(Session.player_nation)
	world.duel_nation = Session.enemy_nation
	world.bot_nation = Session.bot_nation
	world.set_bot_mode(Session.world_mode(), sim.element, sim.pos, sim.yaw)
	sim.respawn()                              # a full pouch or chi bar, and your side of the map in a duel
	prev_pos = sim.pos
	if world.bot_mode == "duel":
		round_t = ROUND_DELAY


func _resume() -> void:
	_capture(true)


func _show_pause_main() -> void:
	if pause_sub != null:
		pause_sub.queue_free()
		pause_sub = null
	pause_box.visible = true
	pause_info.text = _setup_text()


func _setup_text() -> String:
	var s := Session.nation_name(sim.element)
	if world.bot_mode == "duel":
		s += "   -   duel vs %s" % Session.nation_name(world.bots[0].nation) if not world.bots.is_empty() else ""
	elif world.bot_mode == "benders":
		s += "   -   %s bots" % Session.nation_name(world.bot_nation)
	else:
		s += "   -   fighting dummies"
	return s


func _open_sub(c: Control) -> void:
	pause_box.visible = false
	pause_sub = c
	pause_center.add_child(c)


func _show_moves() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	var t := UI.label("MY MOVES - " + Session.nation_name(sim.element), 32)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var view := TutorialView.new()
	view.custom_minimum_size = Vector2(900.0, 520.0)
	view.show_nation(sim.element)
	v.add_child(view)
	var back := UI.button("BACK", Vector2(300.0, 50.0))
	back.pressed.connect(_show_pause_main)
	v.add_child(back)
	_open_sub(v)


# Slot key labels follow the key bindings (a rebind in Options shows up when it closes).
func _refresh_slot_keys() -> void:
	for k in slot_nodes:
		for s in slot_nodes[k]:
			s.refresh_keys()


func _options_closed() -> void:
	_refresh_slot_keys()
	_show_pause_main()


func _show_options() -> void:
	var o := OptionsUI.new()
	o.closed.connect(_options_closed)
	_open_sub(o)


func _quit_to_menu() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/menu.tscn")


# The hidden debug code was entered (or turned off again): god mode and no cooldowns follow it.
func _apply_debug() -> void:
	sim.debug_god = Settings.debug_enabled
	sim.debug_nocd = Settings.debug_enabled
	debug_flash = 2.5
	if pause_sub is OptionsUI:
		(pause_sub as OptionsUI).rebuild()


# Everything back to its start: you on your spawn (your side of the map in a duel), bots at home and at full health.
func _reset_round(msg := "") -> void:
	sim.respawn()
	world.reset_bots()
	if world.bot_mode == "duel":
		sim.ult = 0.0                       # the ultimate starts empty every duel round
	prev_pos = sim.pos
	fx.rebuild_bots()
	if world.bot_mode == "duel":
		round_t = ROUND_DELAY               # both fighters wait on their sides until the timer runs out
		round_msg = msg
	else:
		round_t = 0.0
	_capture(true)


func _capture(on: bool) -> void:
	captured = on
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE
	if overlay:
		overlay.visible = not on
		if not on:
			_show_pause_main()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and captured:
		_capture(false)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if captured:
			var mm := event as InputEventMouseMotion
			var sens: float = Settings.BASE_SENS * Settings.mouse_sens
			sim.yaw -= mm.relative.x * sens
			sim.pitch = clampf(sim.pitch - mm.relative.y * sens, -1.55, 1.55)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed or not captured:
			return
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				inp.fire_pressed = true
			MOUSE_BUTTON_RIGHT:
				inp.slice_pressed = true
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				inp.jump_pressed = true
	elif event is InputEventKey:
		var k := event as InputEventKey
		if not k.pressed or k.echo:
			return
		var code := int(k.physical_keycode)
		if Settings.feed_key(code):
			_apply_debug()
		if captured:
			_game_key(code)
		match code:
			KEY_ESCAPE:
				if captured:
					_capture(false)
				elif pause_sub == null:
					_capture(true)                   # Esc again closes the pause menu
			KEY_F10:
				get_tree().quit()
			KEY_F11:
				var fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fs else DisplayServer.WINDOW_MODE_FULLSCREEN)


# A bound key was pressed while playing.
func _game_key(code: int) -> void:
	if code == Settings.key("jump"):
		inp.jump_pressed = true
	elif code == Settings.key("ability_q"):
		inp.scooter_pressed = true
	elif code == Settings.key("ability_z"):
		inp.barrage_pressed = true
	elif code == Settings.key("ability_g"):
		inp.grab_pressed = true
	elif code == Settings.key("ability_v"):
		inp.armor_pressed = true
	elif code == Settings.key("ability_freeze"):
		inp.freeze_pressed = true
	elif code == Settings.key("ultimate"):
		inp.ult_pressed = true
	elif code == Settings.key("respawn"):
		respawn_queued = true
	elif Settings.debug_enabled and code == Settings.key("debug_ult"):
		sim.ult = C.ULT_MAX                          # debug: fill the ultimate meter


func _poll_input() -> void:
	inp.move_x = float(Settings.down("move_right")) - float(Settings.down("move_left"))
	inp.move_y = float(Settings.down("move_forward")) - float(Settings.down("move_back"))
	inp.sprint = Settings.down("sprint")
	inp.crouch = Settings.down("crouch") or Input.is_physical_key_pressed(KEY_CTRL)
	inp.jump_held = Settings.down("jump")
	inp.fire_held = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	inp.shield_held = Settings.down("ability_e")
	inp.suction_held = Settings.down("ability_f")
	inp.ult_held = Settings.down("ultimate")


# ------------------------------------------------------------------ frame loop

func _process(delta: float) -> void:
	var dt := minf(delta, 0.05)                 # a hitch never makes the simulation run a long catch-up burst
	if Settings.quality != _quality_applied:
		_apply_quality()
	clock += dt
	if captured:
		_poll_input()
		if respawn_queued:
			if world.bot_mode == "duel":
				_reset_round()
			else:
				sim.respawn()
				world.reset_bots()
				prev_pos = sim.pos
		if round_t > 0.0:
			round_t = maxf(0.0, round_t - dt)       # waiting for the round to start: nobody moves
			accumulator = 0.0
		else:
			accumulator += dt
		while accumulator >= TICK:
			prev_pos = sim.pos
			var d0: int = sim.deaths
			sim.step(TICK, inp)
			accumulator -= TICK
			if world.bot_mode == "duel" and (sim.deaths != d0 or world.duel_round_over):
				_reset_round("YOU WIN" if world.duel_round_over else "THE ENEMY WINS")   # a kill ends the round
				accumulator = 0.0
				break
			if sim.pos.y < -60.0:
				sim.respawn()
	else:
		accumulator = 0.0
		inp.fire_held = false
		inp.shield_held = false
		inp.suction_held = false
		inp.ult_held = false
	respawn_queued = false

	_update_ult_sky(dt)
	terrain_view.update(6)
	_handle_events()
	_update_camera(dt)
	var a := accumulator / TICK
	fx.update(dt, prev_pos.lerp(sim.pos, a))
	_update_hud(dt)


func _handle_events() -> void:
	for ev in sim.events:
		fx.on_sim_event(ev, sim.pos)
		match String(ev["type"]):
			"land":
				rig_kick = -minf(0.28, float(ev["impact"]) * 0.016)
			"slide":
				rig_kick = -0.06
			"gust":
				rig_kick = 0.10
			"punch":
				rig_kick = 0.03
			"boulder":
				rig_kick = 0.12
				rig_fov_punch = 5.0
				rig_shake = maxf(rig_shake, 0.35)
			"barrage":
				rig_kick = 0.08
				rig_shake = maxf(rig_shake, 0.25)
			"slice":
				rig_kick = 0.05
				rig_fov_punch = 3.0
			"blast":
				var c: float = ev["charge"]
				rig_kick = 0.04 + 0.12 * c
				rig_fov_punch = 3.0 + 9.0 * c
				rig_shake = maxf(rig_shake, 0.2 + 0.5 * c)
			"breath_start":
				rig_fov_punch = 12.0
				rig_shake = maxf(rig_shake, 0.5)
			"bomb_wind":
				rig_fov_punch = -10.0
			"bomb_dive":
				rig_fov_punch = 24.0
			"bomb":
				rig_kick = -0.6
				rig_shake = 1.0
				rig_fov_punch = -8.0
			"rock":
				rig_kick = 0.04
			"wave":
				var wc: float = ev["charge"]
				rig_kick = 0.05 + 0.1 * wc
				rig_shake = maxf(rig_shake, 0.25 + 0.4 * wc)
			"wall", "grab", "plant":
				rig_kick = 0.06
				rig_shake = maxf(rig_shake, 0.35)
			"elevator_on", "skate_on":
				rig_kick = 0.05
			"armor_on":
				rig_kick = -0.05
				rig_shake = maxf(rig_shake, 0.2)
			"armor_break":
				rig_shake = maxf(rig_shake, 0.4)
			"clap":
				rig_fov_punch = -4.0
			"quake_land":
				rig_kick = -0.5
				rig_shake = 1.0
			"pillar":
				rig_shake = maxf(rig_shake, 0.4)
			"propel":
				rig_kick = 0.12
				rig_fov_punch = 9.0
				rig_shake = maxf(rig_shake, 0.3)
			"slab_throw":
				rig_kick = 0.1
				rig_shake = maxf(rig_shake, 0.4)
			"bullet":
				rig_kick = 0.02
			"whip":
				rig_kick = 0.04
				rig_fov_punch = 2.0
			"jet_start":
				rig_fov_punch = 3.0
			"shards":
				rig_kick = 0.06
				rig_shake = maxf(rig_shake, 0.2)
			"ice_wall":
				rig_kick = 0.06
				rig_shake = maxf(rig_shake, 0.3)
			"tide":
				rig_fov_punch = 9.0
				rig_shake = maxf(rig_shake, 0.8)
			"octo_start":
				rig_fov_punch = 11.0
				rig_shake = maxf(rig_shake, 0.6)
			"octo_swipe":
				rig_kick = 0.05
				rig_shake = maxf(rig_shake, 0.3)
			"octo_slam":
				rig_kick = -0.4
				rig_shake = 1.0
			"octo_grab", "octo_throw":
				rig_shake = maxf(rig_shake, 0.35)
			"fpunch":
				rig_kick = 0.04
				rig_fov_punch = 2.0
			"fbig":
				rig_kick = 0.1
				rig_shake = maxf(rig_shake, 0.3)
			"fburst":
				rig_kick = 0.14
				rig_shake = maxf(rig_shake, 0.4)
			"fring":
				rig_kick = -0.2
				rig_shake = maxf(rig_shake, 0.6)
			"fkick":
				rig_fov_punch = 8.0
			"fkick_hit":
				rig_kick = 0.1
				rig_shake = maxf(rig_shake, 0.5)
			"adash":
				rig_fov_punch = 10.0
			"overheat":
				rig_shake = maxf(rig_shake, 0.7)
			"rush_start":
				rig_fov_punch = 14.0
				rig_shake = maxf(rig_shake, 0.7)
			"lightning_charge":
				rig_fov_punch = -4.0
			"lightning_fire":
				rig_kick = 0.2
				rig_fov_punch = 10.0
				rig_shake = maxf(rig_shake, 1.0)
			"launched":
				rig_kick = 0.12
				rig_fov_punch = 8.0
			"quake_start":
				rig_shake = maxf(rig_shake, 0.9)
				rig_fov_punch = -6.0
			"hurt":
				hurt_t = 0.35
				rig_shake = maxf(rig_shake, 0.25)
			"died":
				hurt_t = 0.8
				prev_pos = sim.pos
	sim.events.clear()
	for ev in world.events:
		fx.on_world_event(ev)
		if String(ev["type"]) == "bot_hit":
			hit_t = 0.18
	world.events.clear()


func _update_camera(dt: float) -> void:
	var a := accumulator / TICK
	var p: Vector3 = prev_pos.lerp(sim.pos, a)
	rig_eye = lerpf(rig_eye, sim.eye_height(), 1.0 - exp(-18.0 * dt))
	rig_kick = lerpf(rig_kick, 0.0, 1.0 - exp(-9.0 * dt))
	rig_fov_punch = lerpf(rig_fov_punch, 0.0, 1.0 - exp(-5.0 * dt))
	var floor_shake := 0.07 if sim.breath_t > 0.0 else (0.35 if sim.quake_t > 0.0 else 0.0)
	rig_shake = maxf(floor_shake, lerpf(rig_shake, 0.0, 1.0 - exp(-6.0 * dt)))
	var sp: float = sim.speed()
	var strafe: float = inp.move_x
	var target_roll: float = -strafe * 0.025 * minf(1.0, sp / 8.5)
	if sim.sliding:
		target_roll += 0.03
	if sim.gliding:
		target_roll += -strafe * 0.03
	rig_roll = lerpf(rig_roll, target_roll, 1.0 - exp(-10.0 * dt))
	var target_fov: float = Settings.fov + clampf((sp - 5.0) * 1.1, 0.0, 18.0) + (6.0 if sim.gliding else 0.0)
	if not sim.slam.is_empty() and String(sim.slam["phase"]) == "dive":
		target_fov += 16.0
	rig_fov = lerpf(rig_fov, target_fov, 1.0 - exp(-6.0 * dt))
	cam.fov = rig_fov + rig_fov_punch
	cam.position = p + Vector3(0.0, rig_eye + rig_kick, 0.0)
	var sx := (sin(clock * 53.0) + sin(clock * 37.0 + 1.3)) * 0.5 * rig_shake * 0.025
	var sy := (sin(clock * 47.0 + 2.1) + sin(clock * 29.0)) * 0.5 * rig_shake * 0.025
	cam.rotation = Vector3(sim.pitch + sx, sim.yaw + sy, rig_roll)


func _update_hud(dt: float) -> void:
	var waiting: bool = round_t > 0.0 and world.bot_mode == "duel"
	round_label.visible = waiting
	if waiting:
		if round_msg == "":
			round_label.text = "DUEL STARTS IN %d" % int(ceil(round_t))
		else:
			round_label.text = "%s\nnext round in %d" % [round_msg, int(ceil(round_t))]
	debug_flash = maxf(0.0, debug_flash - dt)
	debug_label.visible = Settings.debug_enabled or debug_flash > 0.0
	if debug_flash > 0.0:
		debug_label.text = "DEBUG MODE ON: god mode, no cooldowns, unlimited ultimates" if Settings.debug_enabled else "DEBUG MODE OFF"
	else:
		debug_label.text = "DEBUG"
	_update_slots(dt)
	speed_label.text = "%.1f m/s" % sim.speed()
	state_label.text = sim.state_name()
	var eye_y: float = sim.pos.y + sim.eye_height()
	var under: bool = world.terrain.water_depth_at(sim.pos.x, sim.pos.z) > 0.05 and eye_y < world.terrain.surface_at(sim.pos.x, sim.pos.z)
	water_tint.color.a = lerpf(water_tint.color.a, 0.45 if under else 0.0, minf(1.0, dt * 10.0))
	var slope := rad_to_deg(acos(clampf(sim.ground_normal.y, -1.0, 1.0)))
	info_label.text = "slope %d deg   |   y %.1f   |   %s" % [int(slope), sim.pos.y, "grounded" if sim.on_ground else "airborne"]
	chi_bar.max_value = sim.chi_cap()
	chi_bar.value = sim.chi
	hp_bar.value = sim.hp
	hp_label.text = "HP %d" % int(ceil(sim.hp))
	charge_bar.visible = sim.charging
	charge_bar.value = sim.charge

	ult_bar.value = sim.ult
	var earth: bool = sim.element == "earth"
	var water: bool = sim.element == "water"
	var fire: bool = sim.element == "fire"
	var etxt := "FIRE" if fire else ("WATER" if water else ("EARTH" if earth else "AIR"))
	if fire:
		if sim.overheat_t > 0.0:
			etxt = "OVERHEATED  %.1f s" % sim.overheat_t
		elif sim.rush_t > 0.0:
			etxt = "DRAGON RUSH  %.1f s" % sim.rush_t
		elif sim.light_t >= 0.0:
			etxt = "LIGHTNING  %d%%" % int(100.0 * sim.light_t / C.LIGHT_CHARGE)
		elif sim.soak_t > 0.0:
			etxt += "   SOAKED (no ring, no lightning)"
		elif sim.is_hot():
			etxt += "   HOT +20%"
	if earth and sim.armor_on:
		etxt += "   ARMOR %d%%" % int(round(100.0 * sim.armor_hp / C.ARMOR_HP))
	if earth and not world.held.is_empty():
		etxt += "   SLAB %d" % int(ceil(float(world.held["hp"])))
	if water and sim.octo_t > 0.0:
		etxt = "OCTOPUS FORM  %.1f s" % sim.octo_t
		if world.grabbed != null:
			etxt += "   HELD %.1f s  (Q to throw)" % maxf(world.grab_t, 0.0)
	elif water and sim.gathering:
		etxt += "   GATHERING"
	if water and sim.freezing and sim.octo_t <= 0.0:
		etxt += "   FREEZE ON"
	if sim.combo_t > 0.0:
		etxt += "   COMBO! " + String(C.COMBOS[sim.element]["cue"])
	if sim.burn_t > 0.0:
		etxt += "   BURNING (water puts it out)"
	if sim.momentum_t > 0.0:
		etxt += "   MOMENTUM %.1f s" % sim.momentum_t
	chi_text.text = ("INNER FIRE  %d%%" % int(sim.heat)) if fire else (("WATER POUCH" + ("   -   FREE HERE (water or ice is close)" if sim.near_water else "")) if water else "CHI")
	chi_bar.modulate = (Color(1.0, 0.3, 0.15) if (sim.overheat_t > 0.0 or sim.heat >= 90.0) else (Color(1.0, 0.6, 0.2) if sim.is_hot() else Color(1.0, 0.8, 0.4))) if fire else (Color(0.45, 0.78, 1.0) if water else Color(1, 1, 1))
	element_label.text = etxt
	element_label.modulate = Color(1.0, 0.6, 0.3) if fire else Color(0.55, 0.82, 1.0) if water else (Color(0.85, 0.62, 0.32) if earth else Color(0.78, 0.93, 1.0))
	if water:
		var kq := Settings.key_name("ability_q")
		var ke := Settings.key_name("ability_e")
		hints_label.text = ("OCTOPUS:  LMB left arm   RMB right arm   %s slam   %s grab / throw" % [ke, kq] if sim.octo_t > 0.0 \
				else "LMB whip / hold bullets   hold Space over water: propel   RMB heal   %s ice shards   %s ice wall, again near it: discs   %s ice skate   %s freeze%s   hold %s gather   %s tap octopus / hold wave" \
				% [Settings.key_name("ability_z"), ke, kq, Settings.key_name("ability_freeze"), " (ON)" if sim.freezing else "", Settings.key_name("ability_f"), Settings.key_name("ultimate")])
	else:
		hints_label.text = ("LMB small fireball / hold + release big fireball   RMB flame burst   %s fire kick   %s fire ring   tap X dragon rush / hold X lightning (2 s)" 				% [Settings.key_name("ability_z"), Settings.key_name("ability_f")]) if fire else ("LMB rock/wave  RMB boulder  Z barrage  Q skate  E wall  G grab  F pillar  V armor  hold Space at wall: elevator  X ult   (carrying a wall: LMB throws it)" if earth \
				else "LMB punch / hold blast   RMB slice   E shield   F suction   Q scooter   %s air dash (look up to climb)   X ultimate" % Settings.key_name("ability_z"))
	if sim.octo_t > 0.0:
		ult_label.text = "OCTOPUS FORM"
		ult_label.modulate = Color(0.6, 0.85, 1.0, 0.9)
	elif sim.rush_t > 0.0:
		ult_label.text = "DRAGON RUSH"
		ult_label.modulate = Color(1.0, 0.7, 0.4, 0.9)
	elif sim.ult_ready() and fire:
		ult_label.text = "ULTIMATE READY  -  tap X: DRAGON RUSH    hold X (2 s): LIGHTNING"
		ult_label.modulate = Color(1.0, 0.9, 0.5, 0.75 + 0.25 * sin(clock * 8.0))
	elif sim.ult_ready() and water:
		ult_label.text = "ULTIMATE READY  -  tap X: OCTOPUS FORM    hold X near water: TIDAL WAVE (%d%% size)" % int(round(100.0 * sim.tide_power))
		ult_label.modulate = Color(1.0, 0.9, 0.5, 0.75 + 0.25 * sin(clock * 8.0))
	elif sim.ult_ready():
		var kind := "AIR BOMB"
		match sim.ult_kind():
			"breath":
				kind = "AIR BREATH"
			"quake":
				kind = "EARTHQUAKE DIVE"
			"clap":
				kind = "EARTH CLAP"
		ult_label.text = "ULTIMATE READY  -  press X for %s" % kind
		ult_label.modulate = Color(1.0, 0.9, 0.5, 0.75 + 0.25 * sin(clock * 8.0))
	else:
		ult_label.text = "ULTIMATE  %d%%" % int(sim.ult)
		ult_label.modulate = Color(1, 1, 1, 0.8)

	hit_t = maxf(0.0, hit_t - dt)
	hit_marker.modulate.a = clampf(hit_t / 0.18, 0.0, 1.0)
	hurt_t = maxf(0.0, hurt_t - dt)
	hurt_flash.color.a = clampf(hurt_t / 0.8, 0.0, 1.0) * 0.35
