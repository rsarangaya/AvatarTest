extends RefCounted
## Player movement + airbending simulation. Pure logic, runs at a fixed tick.
## Core (Apex-style): sprint, slide, slide-jump, air control, mantle.
## Airbending: Gust Jump, Glide, Air Scooter, Air Punch / Charged Blast, Air Slice,
## Air Shield, Air Suction, and two ultimates (Air Breath, Air Bomb).
## Earthbending (press 2): Rock Throw / Earth Wave, Earth Ramp, Earth Wall, Earth Pillar, Earthquake.
## All damage and bot logic lives in world.gd; this file only decides what the player does.

const C = preload("res://scripts/config.gd")


class InputState:
	var move_x := 0.0
	var move_y := 0.0
	var sprint := false
	var crouch := false
	var jump_held := false
	var fire_held := false
	var shield_held := false
	var suction_held := false
	var ult_held := false              # X is down: a held press (Tidal Wave) differs from a tap (Octopus Form)
	# Edges: set by the game, consumed (cleared) by step().
	var jump_pressed := false
	var scooter_pressed := false
	var fire_pressed := false
	var slice_pressed := false
	var ult_pressed := false
	var barrage_pressed := false
	var grab_pressed := false          # G: grab / plant an earth wall
	var freeze_pressed := false        # T: freeze / unfreeze water (waterbender)
	var armor_pressed := false         # V: earth armor
	var element_pressed := ""         # "air" | "earth" | "water" | "" (set by the game when a nation is picked)


var world

var pos := Vector3.ZERO
var vel := Vector3.ZERO
var yaw := 0.0
var pitch := 0.0
var radius: float = C.RADIUS
var height: float = C.STAND_HEIGHT

var on_ground := false
var ground_normal := Vector3.UP
var crouching := false
var sliding := false
var crouch_latch := false

var ground_time := 0.0
var air_time := 0.0
var coyote := 0.0
var jump_buf := 0.0
var slide_cd := 0.0
var mantle_cd := 0.0
var gust_cd := 0.0
var punch_cd := 0.0
var slice_cd := 0.0
var boulder_cd := 0.0
var barrage_cd := 0.0
var wall_cd := 0.0
var pillar_cd := 0.0
var pillar_charges := C.PILLAR_CHARGES   # earth pillars in hand: each comes back PILLAR_RECHARGE seconds after use
var pillar_recharge := 0.0
var bullet_cd := 0.0
var propel_cd := 0.0
var propel_armed := true         # a jet that has ended re-arms only after touching ground or water with Space released
var propelling := false          # hold Space over water: the jet is lifting you

# vitals
var hp: float = C.PLAYER_HP
var deaths := 0
var hp_delay := 0.0
var chi: float = C.CHI_MAX
var chi_delay := 0.0
var ult := 0.0

# bending state
var scooter := false
var gliding := false
var shield_on := false          # world.gd reads this to reflect enemy bolts
var suction_on := false
var fire_down := false          # left button is down and not yet resolved
var fire_time := 0.0
var charging := false
var charge := 0.0               # 0..1
var slice_flip := false
var breath_t := 0.0             # seconds of Air Breath left
var slam := {}                  # Air Bomb: {phase: "wind"|"dive", t, h0}
var element := "air"            # which bending style is active: "air" | "earth" | "water"
var quake_t := 0.0              # seconds of Earthquake left
var skating := false            # Earth Skate: riding a slab over the ground
var boulder_pull := {}           # RMB boulder being torn from the ground / a wall before the throw
var _take_acc := 0.0
var climbing := false           # air scooter running up steep ground
var melee_cd := 0.0
var melee_window := 0.0
var melee_combo := 0
var melee_hold := false
var wallrun := false             # air scooter running straight up a wall
var wallrun_speed := 0.0
var wallrun_dir := Vector3.ZERO
var swimming := false           # in deep water
var water_depth := 0.0
var elevating := false          # Earth Elevator: riding a column of rock up a wall
var armor_on := false
var armor_hp: float = C.ARMOR_HP
var armor_cd := 0.0
# waterbending (the chi bar is the water pouch: it never refills by itself)
var debug_god := false          # hidden debug mode (see settings.gd): take no damage ...
var debug_nocd := false         # ... and have no cooldowns
var hurt_acc := 0.0             # damage taken since world.gd last looked (fills the duel enemy's ultimate)
var jet_on := false             # Water Jet running
var gathering := false          # drawing water into the pouch
var gather_acc := 0.0
var whip_flip := false
var iwall_cd := 0.0
var disc_cd := 0.0
var heal_cd := 0.0
var heal_left := 0.0            # hit points still to be restored by a heal
var octo_t := 0.0               # seconds of Octopus Form left
var octo_cd := 0.0              # left arm swipe cooldown
var octo_cd_r := 0.0            # right arm swipe cooldown
var octo_slam_cd := 0.0
var octo_q_cd := 0.0
var ult_hold := -1.0            # >= 0 while X is down on a water ultimate that is still deciding between tap and hold
var ult_lock := 0.0             # the Tidal Wave's own damage must not refill the meter
var freeze_acc := 0.0
var near_water := false         # in or right next to water or ice: waterbending costs nothing here
var skate_dry_t := 0.0          # how long the ice skate has had no water or ice around it
var freezing := false           # the freeze toggle (T) is on: water around you turns to ice as you move
var freeze_dry_t := 0.0
var _jet_drop_t := 0.0          # spent jet water lands as a puddle every so often
var _jet_drop_amt := 0.0
var tide_power := 0.0           # 0..1, how big a Tidal Wave from here would be (refreshed a few times a second)
var _tide_power_t := 0.0
var _prev_e := false
var _prev_f := false
var _e_edge := false
var _f_edge := false
# firebending (see config.gd "Fire nation")
var heat := 0.0                  # Inner Fire 0..HEAT_MAX (shown in the chi bar)
var heat_idle := 0.0             # seconds since the last attack (heat only falls after HEAT_IDLE)
var overheat_t := 0.0            # > 0: overheated, no moves
var soak_t := 0.0                # > 0: soaked by water: no ring, no lightning
var fcharging := false           # holding LMB: the big fireball is winding up
var fpunch_cd := 0.0             # small fireball
var fbig_cd := 0.0
var fburst_cd := 0.0
var dash_cd := 0.0               # air dash (air) / fire kick (fire) cooldown
var dash_t := 0.0                # > 0 while an air dash or the fire kick lunge runs
var dash_dir := Vector3.ZERO     # unit vector (3D for the air dash, flat for the kick)
var dash_speed := 0.0
var dash_exit := 0.0             # speed cap when the dash ends
var dash_kick := false           # the running dash is a fire kick: the hit lands when the lunge ends
var dash_air_used := false       # one dash in the air per landing (air dash, fire kick)
var ring_cd := 0.0
var guard_t := 0.0               # fire ring guard: little damage taken, projectiles burn up inside it
var rush_t := 0.0                # seconds of Dragon Rush left
var rush_dir := Vector3.ZERO
var light_t := -1.0              # >= 0 while charging lightning (seconds so far)
var _rush_fx_acc := 0.0
# burn, combos, kill momentum
var burn_t := 0.0                # > 0: burning (small damage over time; water puts it out)
var _burn_acc := 0.0
var combo_t := 0.0               # > 0: the nation's combo opener was just used; the finisher now hits harder
var boulder_mult := 1.0          # combo multiplier carried by the boulder being pulled
var momentum_t := 0.0            # > 0: kill momentum (a speed boost from a kill, only in modes that give it)
var momentum_mult := 0.0

var mantle := {}
var events: Array = []


func _init(w) -> void:
	world = w
	respawn()


func respawn() -> void:
	pos = world.spawn + Vector3(0.0, 0.05, 0.0)
	vel = Vector3.ZERO
	yaw = world.spawn_yaw
	pitch = 0.0
	on_ground = false
	sliding = false
	crouching = false
	scooter = false
	skating = false
	swimming = false
	wallrun = false
	melee_cd = 0.0
	melee_window = 0.0
	melee_combo = 0
	melee_hold = false
	boulder_pull = {}
	burn_t = 0.0
	_burn_acc = 0.0
	combo_t = 0.0
	boulder_mult = 1.0
	momentum_t = 0.0
	pillar_charges = C.PILLAR_CHARGES
	pillar_recharge = 0.0
	bullet_cd = 0.0
	propel_cd = 0.0
	propelling = false
	propel_armed = true
	elevating = false
	armor_on = false
	armor_hp = C.ARMOR_HP
	armor_cd = 0.0
	world.drop_held()
	world.octo_release()
	jet_on = false
	gathering = false
	freezing = false
	octo_t = 0.0
	octo_cd = 0.0
	octo_cd_r = 0.0
	octo_slam_cd = 0.0
	octo_q_cd = 0.0
	heal_left = 0.0
	ult_hold = -1.0
	ult_lock = 0.0
	heat = 0.0
	heat_idle = 0.0
	overheat_t = 0.0
	soak_t = 0.0
	fcharging = false
	dash_t = 0.0
	dash_kick = false
	dash_air_used = false
	guard_t = 0.0
	rush_t = 0.0
	light_t = -1.0
	gliding = false
	shield_on = false
	suction_on = false
	fire_down = false
	charging = false
	charge = 0.0
	breath_t = 0.0
	quake_t = 0.0
	slam = {}
	mantle = {}
	height = C.STAND_HEIGHT
	hp = C.PLAYER_HP
	hp_delay = 0.0
	chi = chi_cap()
	chi_delay = 0.0
	air_time = 0.0


func chi_cap() -> float:
	if element == "fire":
		return C.HEAT_MAX
	if element == "water":
		return C.WATER_MAX
	return C.AIR_CHI_MAX if element == "air" else C.CHI_MAX


func speed() -> float:
	return Vector2(vel.x, vel.z).length()


func eye_height() -> float:
	return C.EYE_CROUCH if crouching else C.EYE_STAND


func look_dir() -> Vector3:
	return Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))


func height_above_ground() -> float:
	var g: Dictionary = world.ground_at(pos.x, pos.z, pos.y)
	var gy: float = g["y"]
	return pos.y - gy


func ult_ready() -> bool:
	return ult >= C.ULT_MAX - 0.001


func is_hot() -> bool:
	return element == "fire" and heat >= C.HEAT_HOT


func _hot_mult() -> float:
	return C.HOT_MULT if heat >= C.HEAT_HOT else 1.0



# Which ultimate pressing X would trigger right now.
func ult_kind() -> String:
	if element == "fire":
		return "rush"                               # tap = Dragon Rush, hold = Lightning
	if element == "water":
		return "tide"                               # tap = Octopus Form, hold near water = Tidal Wave
	if not on_ground and slam.is_empty() and height_above_ground() >= C.BOMB_MIN_HEIGHT:
		return "quake" if element == "earth" else "bomb"
	return "clap" if element == "earth" else "breath"


func state_name() -> String:
	if element == "fire":
		if rush_t > 0.0:
			return "DRAGON RUSH"
		if light_t >= 0.0:
			return "LIGHTNING"
		if overheat_t > 0.0:
			return "OVERHEATED"
		if dash_t > 0.0:
			return "FIRE KICK"
		if fcharging:
			return "FIREBALL"
	if dash_t > 0.0 and element == "air":
		return "AIR DASH"
	if octo_t > 0.0:
		return "OCTOPUS FORM"
	if jet_on:
		return "WATER JET"
	if not slam.is_empty():
		return "EARTHQUAKE DIVE" if bool(slam.get("earth", false)) else "AIR BOMB"
	if breath_t > 0.0:
		return "AIR BREATH"
	if quake_t > 0.0:
		return "EARTHQUAKE"
	if not mantle.is_empty():
		return "MANTLE"
	if sliding:
		return "SLIDE"
	if elevating:
		return "EARTH ELEVATOR"
	if wallrun:
		return "WALL RUN"
	if swimming:
		return "SWIM"
	if not on_ground:
		return "GLIDE" if gliding else "AIR"
	if scooter:
		return "AIR SCOOTER"
	if skating:
		return "ICE SKATE" if element == "water" else "EARTH SKATE"
	if crouching:
		return "CROUCH"
	var s := speed()
	if s > 6.5:
		return "SPRINT"
	if s > 0.5:
		return "WALK"
	return "IDLE"


func take_damage(amount: float, ult := false) -> void:
	if debug_god:
		return
	if guard_t > 0.0 and not ult:
		amount *= C.RING_GUARD_TAKE                 # the fire ring's guard
	if not slam.is_empty():
		return                                  # the air bomb makes you untouchable
	if armor_on:
		var soak := minf(amount * C.ARMOR_SOAK, armor_hp)
		armor_hp -= soak
		amount -= soak
		events.append({"type": "armor_hit", "amount": soak})
		if armor_hp <= 0.001:
			armor_hp = 0.0
			armor_on = false
			armor_cd = C.ARMOR_TOGGLE_CD
			events.append({"type": "armor_break"})
	hurt_acc += amount
	hp -= amount
	hp_delay = C.HP_REGEN_DELAY
	events.append({"type": "hurt", "amount": amount})
	if hp <= 0.0:
		events.append({"type": "died"})
		deaths += 1
		respawn()


# ------------------------------------------------------------------ main tick

func step(dt: float, inp: InputState) -> void:
	if debug_nocd:
		_clear_cooldowns()
		ult = C.ULT_MAX                             # debug: unlimited ultimates
	if debug_god:
		hp = C.PLAYER_HP
	hp_delay = maxf(0.0, hp_delay - dt)
	if hp_delay <= 0.0:
		hp = minf(C.PLAYER_HP, hp + C.HP_REGEN * dt)
	_step(dt, inp)
	world.update_combat(dt, self)
	if element == "fire" and ult_lock <= 0.0 and rush_t <= 0.0 and light_t < 0.0:
		heat += world.dealt * C.HEAT_PER_DAMAGE         # damage dealt feeds the fire
		heat -= float(world.kills) * C.HEAT_KILL_DROP    # a kill cools you down
	if octo_t <= 0.0 and ult_lock <= 0.0:       # the meter only fills from damage you deal (an ultimate's own hits do not refill it)
		ult = minf(C.ULT_MAX, ult + world.dealt * C.ULT_PER_DAMAGE)
	world.dealt = 0.0
	if element == "fire":
		_update_heat(dt)
	if world.kills > 0:
		_kill_effect()
	world.kills = 0


# What a kill gives, by game mode (C.MODE_KILL_EFFECTS): a short speed boost in the bot modes, nothing in a duel.
func _kill_effect() -> void:
	var ke: Dictionary = world.kill_effect()
	if ke.has("speed"):
		momentum_t = float(ke["time"])
		momentum_mult = float(ke["speed"])
		events.append({"type": "momentum", "pos": pos})


# ---- burn: set by a fire hit (world.roll_burn_player), put out by water
func ignite() -> void:
	if burn_t <= 0.0:
		events.append({"type": "burn_on", "pos": pos})
	burn_t = C.BURN_TIME


func _update_burn(dt: float) -> void:
	if burn_t <= 0.0:
		return
	if water_depth >= C.SOAK_DEPTH or swimming:
		burn_t = 0.0
		_burn_acc = 0.0
		events.append({"type": "burn_out", "pos": pos})
		return
	burn_t = maxf(0.0, burn_t - dt)
	_burn_acc += C.BURN_DPS * dt
	if _burn_acc >= 1.25:                                # a small tick every quarter second, not a hurt event per sim step
		var a := _burn_acc
		_burn_acc = 0.0
		take_damage(a, true)


# ---- combos (C.COMBOS): the opener starts a short window, the finisher inside it multiplies its damage
func _combo_open(move: String) -> void:
	var c: Dictionary = C.COMBOS.get(element, {})
	if not c.is_empty() and c["open"] == move:
		combo_t = C.COMBO_WINDOW
		events.append({"type": "combo_ready", "pos": pos, "cue": c["cue"]})


func _combo_mult(move: String) -> float:
	if combo_t <= 0.0:
		return 1.0
	var c: Dictionary = C.COMBOS.get(element, {})
	if c.is_empty() or c["finish"] != move:
		return 1.0
	combo_t = 0.0
	events.append({"type": "combo", "pos": pos, "text": c["text"]})
	return float(c["mult"])


func _clear_cooldowns() -> void:
	slide_cd = 0.0
	mantle_cd = 0.0
	gust_cd = 0.0
	punch_cd = 0.0
	slice_cd = 0.0
	boulder_cd = 0.0
	barrage_cd = 0.0
	wall_cd = 0.0
	pillar_cd = 0.0
	pillar_charges = C.PILLAR_CHARGES
	bullet_cd = 0.0
	propel_cd = 0.0
	propelling = false
	propel_armed = true
	armor_cd = 0.0
	melee_cd = 0.0
	iwall_cd = 0.0
	disc_cd = 0.0
	heal_cd = 0.0
	octo_cd = 0.0
	octo_cd_r = 0.0
	octo_slam_cd = 0.0
	octo_q_cd = 0.0
	fpunch_cd = 0.0
	fbig_cd = 0.0
	fburst_cd = 0.0
	dash_cd = 0.0
	dash_air_used = false
	ring_cd = 0.0
	heat = 0.0                                     # debug: no overheat
	overheat_t = 0.0


# Pick the nation (the menus do this once, at the start of a game).
func set_nation(n: String) -> void:
	_set_element(n)


func _clear_edges(inp: InputState) -> void:
	inp.fire_pressed = false
	inp.slice_pressed = false
	inp.ult_pressed = false
	inp.scooter_pressed = false
	inp.barrage_pressed = false
	inp.grab_pressed = false
	inp.armor_pressed = false
	inp.freeze_pressed = false
	inp.element_pressed = ""


func _step(dt: float, inp: InputState) -> void:
	slide_cd = maxf(0.0, slide_cd - dt)
	mantle_cd = maxf(0.0, mantle_cd - dt)
	gust_cd = maxf(0.0, gust_cd - dt)
	punch_cd = maxf(0.0, punch_cd - dt)
	slice_cd = maxf(0.0, slice_cd - dt)
	boulder_cd = maxf(0.0, boulder_cd - dt)
	melee_cd = maxf(0.0, melee_cd - dt)
	melee_window = maxf(0.0, melee_window - dt)
	barrage_cd = maxf(0.0, barrage_cd - dt)
	wall_cd = maxf(0.0, wall_cd - dt)
	pillar_cd = maxf(0.0, pillar_cd - dt)
	bullet_cd = maxf(0.0, bullet_cd - dt)
	propel_cd = maxf(0.0, propel_cd - dt)
	if pillar_charges < C.PILLAR_CHARGES:
		pillar_recharge += dt
		if pillar_recharge >= C.PILLAR_RECHARGE:
			pillar_recharge = 0.0
			pillar_charges += 1
	armor_cd = maxf(0.0, armor_cd - dt)
	iwall_cd = maxf(0.0, iwall_cd - dt)
	disc_cd = maxf(0.0, disc_cd - dt)
	heal_cd = maxf(0.0, heal_cd - dt)
	octo_cd = maxf(0.0, octo_cd - dt)
	octo_cd_r = maxf(0.0, octo_cd_r - dt)
	octo_slam_cd = maxf(0.0, octo_slam_cd - dt)
	octo_q_cd = maxf(0.0, octo_q_cd - dt)
	ult_lock = maxf(0.0, ult_lock - dt)
	dash_cd = maxf(0.0, dash_cd - dt)
	combo_t = maxf(0.0, combo_t - dt)
	momentum_t = maxf(0.0, momentum_t - dt)
	if element == "fire":
		fpunch_cd = maxf(0.0, fpunch_cd - dt)
		fbig_cd = maxf(0.0, fbig_cd - dt)
		fburst_cd = maxf(0.0, fburst_cd - dt)
		ring_cd = maxf(0.0, ring_cd - dt)
		guard_t = maxf(0.0, guard_t - dt)
	near_water = element == "water" and _wet_within(C.WATER_FREE_RADIUS)
	if element == "water":
		_tide_power_t -= dt
		if _tide_power_t <= 0.0:
			_tide_power_t = 0.25
			tide_power = world.tide_strength(pos)
	if not armor_on:
		armor_hp = minf(C.ARMOR_HP, armor_hp + C.ARMOR_REGEN * dt)
	_e_edge = inp.shield_held and not _prev_e
	_f_edge = inp.suction_held and not _prev_f
	_prev_e = inp.shield_held
	_prev_f = inp.suction_held
	jump_buf = maxf(0.0, jump_buf - dt)
	chi_delay = maxf(0.0, chi_delay - dt)
	if inp.jump_pressed:
		jump_buf = C.JUMP_BUFFER
		inp.jump_pressed = false
	if not inp.crouch:
		crouch_latch = false
	if inp.element_pressed != "":
		_set_element(inp.element_pressed)
		inp.element_pressed = ""

	if not mantle.is_empty():
		_clear_edges(inp)
		_update_mantle(dt)
		return

	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var wish := fwd * inp.move_y + right * inp.move_x
	var wl := wish.length()
	if wl > 1.0:
		wish /= wl
		wl = 1.0

	if not slam.is_empty():
		_clear_edges(inp)
		_update_slam(dt, wish)
		return

	# Ledge grab (airborne, pressing into a wall)
	if not on_ground and mantle_cd <= 0.0 and (inp.move_y > 0.0 or inp.jump_held):
		var ledge: Dictionary = world.find_ledge(self, fwd.x, fwd.z)
		if not ledge.is_empty():
			_clear_edges(inp)
			_start_mantle(ledge, fwd)
			return

	_update_abilities(dt, inp)
	if not slam.is_empty():            # the ultimate just started an air bomb: skip this tick's movement
		return

	if rush_t > 0.0:
		_update_rush(dt, wish)
		return
	if dash_t > 0.0:
		_step_dash(dt)
		return

	# Crouch / slide state (the scooter replaces crouching)
	var want_crouch := inp.crouch and not scooter and not skating
	if on_ground and not sliding and want_crouch and not crouch_latch \
			and slide_cd <= 0.0 and speed() >= C.SLIDE_MIN_SPEED:
		_start_slide()
	if sliding and (not want_crouch or not on_ground):
		_end_slide()
	if sliding or want_crouch:
		crouching = true
	elif crouching and world.can_stand(self):
		crouching = false
	height = C.CROUCH_HEIGHT if crouching else C.STAND_HEIGHT

	# Jump (buffered + coyote), or Gust Jump if already airborne
	if jump_buf > 0.0 and (on_ground or coyote > 0.0) and not swimming:
		if sliding:
			_end_slide()
		vel.y = C.JUMP_SPEED * (C.SCOOTER_JUMP_MULT if scooter else 1.0) * (C.AIR_JUMP_MULT if element == "air" else 1.0)
		on_ground = false
		coyote = 0.0
		jump_buf = 0.0
		ground_time = 0.0
		air_time = 0.0
		events.append({"type": "jump"})
	elif jump_buf > 0.0 and not on_ground and not swimming and _can_gust():
		_do_gust(wish, wl)

	# Forces
	var move_mult := 1.0
	if shield_on:
		move_mult = minf(move_mult, C.SHIELD_MOVE_MULT)
	if breath_t > 0.0:
		move_mult = minf(move_mult, C.BREATH_MOVE_MULT)
	if quake_t > 0.0:
		move_mult = minf(move_mult, C.QUAKE_MOVE_MULT)
	if charging:
		move_mult = minf(move_mult, 0.85)
	if jet_on:
		move_mult = minf(move_mult, C.JET_MOVE_MULT)
	if armor_on:
		move_mult = minf(move_mult, C.ARMOR_MOVE_MULT)
	if overheat_t > 0.0:
		move_mult = minf(move_mult, C.OVERHEAT_MOVE_MULT)
	if fcharging:
		move_mult = minf(move_mult, C.FBIG_MOVE_MULT)
	if light_t >= 0.0:
		move_mult = minf(move_mult, C.LIGHT_MOVE_MULT)
	if not world.held.is_empty():
		move_mult = minf(move_mult, C.HELD_MOVE_MULT)
	if momentum_t > 0.0:
		move_mult *= 1.0 + momentum_mult                     # kill momentum

	water_depth = world.terrain.water_depth_at(pos.x, pos.z)
	var was_swim := swimming
	swimming = water_depth >= C.SWIM_DEPTH or (was_swim and water_depth >= C.SWIM_DEPTH - 0.35)
	_update_burn(dt)
	if swimming != was_swim:
		events.append({"type": "splash", "pos": Vector3(pos.x, world.terrain.surface_at(pos.x, pos.z), pos.z), "big": absf(vel.y) > 6.0})
		if swimming:
			scooter = false
			if element != "water":                       # a waterbender keeps skating: it glides over the water
				skating = false
			sliding = false
			crouching = false
			gliding = false
	_update_propel(dt, inp)
	if on_ground and not swimming:
		var on_ice: bool = world.terrain.ice_at(pos.x, pos.z)
		if element == "water":
			if on_ice:
				move_mult *= C.ICE_WALK_WATER_MULT          # water and ice are the same thing to a waterbender: quick on both
		else:
			if water_depth > 0.25:
				move_mult = minf(move_mult, C.WADE_MULT)
			if on_ice:
				move_mult = minf(move_mult, C.ICE_SLOW_MULT)    # everyone else is a little slower on ice

	# Air Scooter wall run: enough speed into a steep wall turns the momentum into a climb
	if scooter and not wallrun and not swimming and inp.move_y > 0.0 and speed() >= C.WALLRUN_MIN:
		var hv := Vector3(vel.x, 0.0, vel.z).normalized()
		if hv.dot(fwd) > 0.2 and _wall_ahead(hv):
			wallrun = true
			wallrun_speed = speed()
			wallrun_dir = hv
			on_ground = false
			coyote = 0.0
			events.append({"type": "wallrun_on", "pos": pos, "dir": hv})

	# Earth Elevator: hold Space against a wall to ride a column of rock up it (W pushes you forward over the lip)
	var elev_now := false
	if element == "earth" and inp.jump_held and not sliding and (elevating or chi >= C.ELEV_MIN_CHI) and chi > 0.0:
		elev_now = _wall_ahead(fwd)
	gliding = false
	if elev_now and not swimming:
		if not elevating:
			elevating = true
			skating = false
			events.append({"type": "elevator_on", "pos": pos})
		chi = maxf(0.0, chi - C.ELEV_DRAIN * dt)
		chi_delay = C.CHI_REGEN_DELAY
		on_ground = false
		coyote = 0.0
		air_time = 0.0
		vel.y = move_toward(vel.y, C.ELEV_SPEED * (C.ARMOR_MOVE_MULT if armor_on else 1.0), C.ELEV_ACCEL * dt)
		var lean := fwd * (maxf(inp.move_y, 0.0) * C.ELEV_FORWARD + 1.4) + right * inp.move_x * 1.6
		vel.x = lean.x
		vel.z = lean.z
	elif wallrun:
		_wallrun_forces(dt, inp)
	elif propelling:
		_propel_forces(dt, wish, wl)
	elif swimming:
		_swim_forces(dt, inp, wish, wl)
	elif on_ground:
		if elevating:
			elevating = false
		ground_time += dt
		air_time = 0.0
		if sliding:
			_slide_forces(dt, wish, wl)
		elif scooter:
			_scooter_forces(dt, wish, wl)
		elif skating:
			var skate_mult := move_mult
			if element == "water":                  # ice and water are where an ice skater is fast
				var wet: bool = water_depth > 0.05 or world.terrain.ice_at(pos.x, pos.z)
				skate_mult *= C.ICE_SKATE_ICE_MULT if wet else C.ICE_SKATE_LAND_MULT
			_skate_forces(dt, wish, wl, skate_mult)
		else:
			var target := C.CROUCH_SPEED if crouching else (C.SPRINT_SPEED if (inp.sprint and inp.move_y > 0.0) else C.WALK_SPEED)
			target *= move_mult * (C.AIR_SPEED_MULT if element == "air" else 1.0)
			if ground_time > C.BHOP_WINDOW:
				_apply_friction(dt, C.FRICTION)
			if wl > 1e-4:
				_accelerate(wish / wl, target * wl, C.GROUND_ACCEL * (C.AIR_GROUND_ACCEL_MULT if element == "air" else 1.0), dt)
		# keep velocity on the slope plane; slopes too steep to stand on dump you downhill
		var n := ground_normal
		if n.y > 0.05 and sqrt(1.0 - n.y * n.y) / n.y > C.MAX_WALK_SLOPE:
			var dn := Vector2(n.x, n.z).normalized()
			vel.x += dn.x * C.STEEP_SLIDE_ACCEL * dt
			vel.z += dn.y * C.STEEP_SLIDE_ACCEL * dt
		vel.y = -(n.x * vel.x + n.z * vel.z) / n.y if n.y > 0.2 else 0.0
	else:
		if elevating:                          # cleared the top of the wall: a hop forward over the lip
			elevating = false
			if inp.jump_held and chi > 0.0:
				vel.x = fwd.x * C.ELEV_LIP_FWD
				vel.z = fwd.z * C.ELEV_LIP_FWD
				vel.y = maxf(vel.y, C.ELEV_LIP_UP)
				events.append({"type": "elevator_lip", "pos": pos})
		ground_time = 0.0
		air_time += dt
		coyote = maxf(0.0, coyote - dt)
		var glide_ok := element == "air" and inp.jump_held and chi > 0.0 and vel.y < C.GLIDE_START_VY and air_time >= C.GLIDE_MIN_AIR_TIME
		if glide_ok:
			gliding = true
			chi = maxf(0.0, chi - C.GLIDE_DRAIN * dt)
			chi_delay = C.CHI_REGEN_DELAY
			vel.y = move_toward(vel.y, -C.GLIDE_FALL * C.AIR_GLIDE_FALL_MULT, C.GLIDE_VERT_ACCEL * dt)
			_air_control(dt, wish, wl, C.GLIDE_ACCEL, C.GLIDE_SPEED_FLOOR)
		else:
			_air_control(dt, wish, wl, C.AIR_ACCEL * (C.AIR_AIRCTL_MULT if element == "air" else 1.0), C.AIR_SPEED * (1.1 if element == "air" else 1.0))
			vel.y = maxf(vel.y - C.GRAVITY * (C.AIR_GRAVITY_MULT if element == "air" else 1.0) * dt, -C.TERMINAL_VELOCITY)

	if not scooter or not on_ground:
		climbing = false
	_integrate(dt)
	if not world.held.is_empty():
		world.set_held_pose(Vector3(pos.x + fwd.x * C.HELD_DIST, pos.y, pos.z + fwd.z * C.HELD_DIST), Vector2(fwd.x, fwd.z))

	if on_ground and not scooter and not skating and chi_delay <= 0.0 and element != "water":
		chi = minf(chi_cap(), chi + (C.AIR_CHI_REGEN if element == "air" else C.CHI_REGEN) * dt)
	elif element == "water" and chi_delay <= 0.0 and not gathering:      # the pouch refills slowly by itself; F is much faster
		chi = minf(chi_cap(), chi + C.WATER_PASSIVE * dt)


# ------------------------------------------------------------------ ground / air helpers

func _swim_forces(dt: float, inp, wish: Vector3, wl: float) -> void:
	on_ground = false
	elevating = false
	coyote = 0.0
	ground_time = 0.0
	air_time = 0.0
	var surf: float = world.terrain.surface_at(pos.x, pos.z)
	var sp := (C.SWIM_SPRINT if inp.sprint else C.SWIM_SPEED) * (C.WATER_SWIM_MULT if element == "water" else 1.0)
	var swim_accel := C.SWIM_ACCEL
	var skate_swim := skating and element == "water"      # ice skate on open water: glide over the surface, fast
	if skate_swim:
		sp = C.SKATE_SPEED * C.ICE_SKATE_ICE_MULT
		swim_accel = 40.0
		chi = maxf(0.0, chi - _cost(C.ICE_SKATE_DRAIN) * dt)
		chi_delay = C.WATER_PASSIVE_DELAY
	var tgt := wish * sp
	vel.x = move_toward(vel.x, tgt.x, swim_accel * dt)
	vel.z = move_toward(vel.z, tgt.z, swim_accel * dt)
	# float with the head above water; Ctrl dives, Space swims up and out
	var target_y := surf - C.SWIM_FLOAT
	var want_vy := clampf((target_y - pos.y) * 3.0, -3.0, 3.0)
	if inp.crouch and not skate_swim:
		want_vy = -C.SWIM_DIVE
	elif inp.jump_held and pos.y < target_y + 0.3:      # Space swims you up to the surface, not on into the air
		want_vy = C.SWIM_RISE
	vel.y = move_toward(vel.y, want_vy, 14.0 * dt)
	if jump_buf > 0.0 and pos.y > surf - C.SWIM_FLOAT - 0.4:
		vel.y = C.SWIM_HOP
		jump_buf = 0.0
	var drag := maxf(0.0, 1.0 - 1.5 * dt)
	vel.x *= drag
	vel.z *= drag


func _wallrun_forces(dt: float, inp) -> void:
	chi = maxf(0.0, chi - C.SCOOTER_DRAIN * dt)
	chi_delay = C.CHI_REGEN_DELAY
	wallrun_speed -= C.WALLRUN_DECAY * dt
	on_ground = false
	coyote = 0.0
	air_time = 0.0
	ground_time = 0.0
	var still_wall := _wall_ahead(wallrun_dir)
	if chi <= 0.0 or not scooter or inp.move_y <= 0.0 or wallrun_speed < C.WALLRUN_END:
		wallrun = false                                  # out of steam: drop off the wall
		vel.x = -wallrun_dir.x * 1.5
		vel.z = -wallrun_dir.z * 1.5
		return
	if not still_wall:
		wallrun = false                                  # the lip: hop over the top and keep rolling
		vel.x = wallrun_dir.x * (wallrun_speed * 0.7 + 4.0)
		vel.z = wallrun_dir.z * (wallrun_speed * 0.7 + 4.0)
		vel.y = maxf(vel.y, 5.5)
		events.append({"type": "wallrun_lip", "pos": pos})
		return
	vel.x = 0.0
	vel.z = 0.0
	vel.y = wallrun_speed * C.WALLRUN_CLIMB


func _apply_friction(dt: float, friction: float) -> void:
	var sp := speed()
	if sp < 0.001:
		vel.x = 0.0
		vel.z = 0.0
		return
	var drop := maxf(sp, C.STOP_SPEED) * friction * dt
	var k := maxf(0.0, sp - drop) / sp
	vel.x *= k
	vel.z *= k


func _accelerate(dir: Vector3, wish_speed: float, accel: float, dt: float) -> void:
	var add := wish_speed - (vel.x * dir.x + vel.z * dir.z)
	if add <= 0.0:
		return
	var a := minf(accel * wish_speed * dt, add)
	vel.x += dir.x * a
	vel.z += dir.z * a


# Steer freely, but never gain speed past what you carried in (or the floor).
func _air_control(dt: float, wish: Vector3, wl: float, accel: float, speed_floor: float) -> void:
	if wl < 1e-4:
		return
	var pre := speed()
	vel.x += wish.x * accel * dt
	vel.z += wish.z * accel * dt
	var cap := maxf(pre, speed_floor)
	var now := speed()
	if now > cap:
		var k := cap / now
		vel.x *= k
		vel.z *= k


func _cap_h_speed(limit: float) -> void:
	var hs := speed()
	if hs > limit:
		var k := limit / hs
		vel.x *= k
		vel.z *= k


# ------------------------------------------------------------------ slide

func _start_slide() -> void:
	var sp := speed()
	sliding = true
	crouching = true
	if sp > 0.0:
		var k := minf(sp * C.SLIDE_BOOST, C.SLIDE_MAX_START) / sp
		vel.x *= k
		vel.z *= k
	events.append({"type": "slide"})


func _end_slide() -> void:
	sliding = false
	slide_cd = C.SLIDE_COOLDOWN
	crouch_latch = true


func _slide_forces(dt: float, wish: Vector3, wl: float) -> void:
	var n := ground_normal
	var k := C.SLIDE_SLOPE_GAIN * C.GRAVITY
	var vx := vel.x + k * n.y * n.x * dt   # downhill pull
	var vz := vel.z + k * n.y * n.z * dt
	var sp := Vector2(vx, vz).length()
	if sp > 1e-4:
		if wl > 1e-4:                       # gentle steering
			var cur := atan2(vz, vx)
			var want := atan2(wish.z, wish.x)
			var d := wrapf(want - cur, -PI, PI)
			var m := C.SLIDE_STEER * dt
			var a := cur + clampf(d, -m, m)
			vx = cos(a) * sp
			vz = sin(a) * sp
		sp = minf(maxf(0.0, sp - C.SLIDE_DECEL * dt), C.SLIDE_MAX_SPEED)
		var cur_len := Vector2(vx, vz).length()
		var s := sp / cur_len if cur_len > 1e-6 else 0.0
		vx *= s
		vz *= s
	vel.x = vx
	vel.z = vz
	if sp < C.SLIDE_END_SPEED:
		_end_slide()


# ------------------------------------------------------------------ gust / glide / scooter

func _can_gust() -> bool:
	return element == "air" and gust_cd <= 0.0 and chi >= C.GUST_COST and air_time >= C.GUST_MIN_AIR_TIME \
			and height_above_ground() >= C.GUST_MIN_HEIGHT


func _do_gust(wish: Vector3, wl: float) -> void:
	chi -= C.GUST_COST
	chi_delay = C.CHI_REGEN_DELAY
	gust_cd = C.GUST_COOLDOWN
	jump_buf = 0.0
	var pre := speed()
	if wallrun:                                          # kick off the wall
		wallrun = false
		vel.x = -wallrun_dir.x * 7.0
		vel.z = -wallrun_dir.z * 7.0
		pre = 7.0
	vel.y = maxf(vel.y, C.GUST_UP)
	if wl > 1e-4:
		var h := Vector3(vel.x, 0.0, vel.z) + (wish / wl) * C.GUST_PUSH * wl
		var cap := maxf(pre + C.GUST_SPEED_GAIN, C.GUST_MIN_SPEED)
		if h.length() > cap:
			h = h.normalized() * cap
		vel.x = h.x
		vel.z = h.z
	events.append({"type": "gust", "pos": pos})


func _scooter_forces(dt: float, wish: Vector3, wl: float) -> void:
	chi = maxf(0.0, chi - C.SCOOTER_DRAIN * dt)
	chi_delay = C.CHI_REGEN_DELAY
	if chi <= 0.0:
		scooter = false
	var sp0 := speed()
	if wl > 1e-4:
		var dir := wish / wl
		var target := C.SCOOTER_SPEED * wl
		if sp0 < 0.1:
			vel.x = dir.x * 0.5
			vel.z = dir.z * 0.5
			sp0 = 0.5
		else:
			# swing the heading toward the steering direction, keeping speed
			var cur := atan2(vel.z, vel.x)
			var want := atan2(dir.z, dir.x)
			var d := wrapf(want - cur, -PI, PI)
			var a := cur + clampf(d, -C.SCOOTER_TURN * dt, C.SCOOTER_TURN * dt)
			vel.x = cos(a) * sp0
			vel.z = sin(a) * sp0
		var sp_new := sp0
		if sp0 < target:
			sp_new = minf(target, sp0 + C.SCOOTER_ACCEL * dt)
		else:
			sp_new = sp0 - (sp0 - target) * C.SCOOTER_OVERSPEED_DRAG * dt
		var sc := sp_new / sp0
		vel.x *= sc
		vel.z *= sc
	elif ground_time > C.BHOP_WINDOW:
		_apply_friction(dt, C.SCOOTER_FRICTION)
	var n := ground_normal
	var steep: bool = n.y > 0.02 and sqrt(1.0 - n.y * n.y) / n.y > C.MAX_WALK_SLOPE
	var hs0 := speed()
	if climbing:
		climbing = hs0 >= C.SCOOTER_CLIMB_KEEP and (steep or hs0 >= C.SCOOTER_CLIMB_MIN * 0.7)
	else:
		climbing = hs0 >= C.SCOOTER_CLIMB_MIN
	if climbing and steep:
		# momentum is spent on the climb: faster in, higher up
		var kk := maxf(0.0, hs0 - C.SCOOTER_CLIMB_DECAY * dt) / maxf(hs0, 0.001)
		vel.x *= kk
		vel.z *= kk
		chi_delay = C.CHI_REGEN_DELAY
	var k := C.SCOOTER_SLOPE_GAIN * C.GRAVITY * (0.15 if climbing else 1.0)
	vel.x += k * n.y * n.x * dt
	vel.z += k * n.y * n.z * dt
	var sp := speed()
	if sp > C.SCOOTER_MAX_SPEED:
		var s := C.SCOOTER_MAX_SPEED / sp
		vel.x *= s
		vel.z *= s


func _wall_ahead(fwd: Vector3) -> bool:
	var ax := pos.x + fwd.x * (radius + 0.55)
	var az := pos.z + fwd.z * (radius + 0.55)
	if world.height_at(ax, az) < pos.y + 0.9:
		return false
	return world.terrain.gradient_at(ax, az).length() >= C.MAX_WALK_SLOPE * 0.9


func _skate_forces(dt: float, wish: Vector3, wl: float, mult: float) -> void:
	chi = maxf(0.0, chi - (_cost(C.ICE_SKATE_DRAIN) if element == "water" else C.SKATE_DRAIN) * dt)
	chi_delay = C.WATER_PASSIVE_DELAY if element == "water" else C.CHI_REGEN_DELAY
	if chi <= 0.0 and not near_water:
		skating = false
	var sp0 := speed()
	if wl > 1e-4:
		var dir := wish / wl
		var target := C.SKATE_SPEED * wl * mult
		if sp0 < 0.1:
			vel.x = dir.x * 0.5
			vel.z = dir.z * 0.5
			sp0 = 0.5
		else:
			var cur := atan2(vel.z, vel.x)
			var want := atan2(dir.z, dir.x)
			var d := wrapf(want - cur, -PI, PI)
			var a := cur + clampf(d, -C.SKATE_TURN * dt, C.SKATE_TURN * dt)
			vel.x = cos(a) * sp0
			vel.z = sin(a) * sp0
		var sp_new := sp0
		if sp0 < target:
			sp_new = minf(target, sp0 + C.SKATE_ACCEL * dt)
		else:
			sp_new = sp0 - (sp0 - target) * C.SKATE_OVERSPEED_DRAG * dt
		var sc := sp_new / sp0
		vel.x *= sc
		vel.z *= sc
	elif ground_time > C.BHOP_WINDOW:
		_apply_friction(dt, C.SKATE_FRICTION)
	var n := ground_normal
	var k := C.SKATE_SLOPE_GAIN * C.GRAVITY
	vel.x += k * n.y * n.x * dt
	vel.z += k * n.y * n.z * dt
	var sp := speed()
	if sp > C.SKATE_MAX_SPEED:
		var s2 := C.SKATE_MAX_SPEED / sp
		vel.x *= s2
		vel.z *= s2


# ------------------------------------------------------------------ attacks & utility bending

func _update_abilities(dt: float, inp: InputState) -> void:
	# Air Scooter toggle (airbending only)
	if inp.scooter_pressed:
		inp.scooter_pressed = false
		if element == "fire":
			pass
		elif element == "water":
			_water_q()
		elif element == "earth":
			if skating:
				skating = false
			elif chi >= C.SKATE_COST_START and not sliding:
				skating = true
				events.append({"type": "skate_on", "pos": pos})
		elif scooter:
			scooter = false
		elif chi >= C.SCOOTER_COST_START and not sliding:
			scooter = true
			events.append({"type": "scooter_on", "pos": pos})

	# Earth Armor (V) and the wall grab / plant (G)
	if inp.armor_pressed:
		inp.armor_pressed = false
		if element == "earth":
			_toggle_armor()
	if inp.grab_pressed:
		inp.grab_pressed = false
		if element == "earth":
			_grab_or_plant()

	var look := look_dir()
	var origin := pos + Vector3(0.0, eye_height(), 0.0)

	# Ultimate
	if inp.ult_pressed:
		inp.ult_pressed = false
		if element == "water":
			if ult_ready() and octo_t <= 0.0:
				ult_hold = 0.0                 # tap or hold? decided in _update_water
		elif element == "fire":
			if ult_ready() and rush_t <= 0.0 and light_t < 0.0 and overheat_t <= 0.0:
				ult_hold = 0.0                 # tap or hold? decided in _update_fire
		else:
			_try_ult()
			if not slam.is_empty():
				return

	# Air Breath / Earthquake: a channelled ultimate that locks out every other move until it ends
	if breath_t > 0.0 or quake_t > 0.0:
		inp.fire_pressed = false
		inp.slice_pressed = false
		inp.barrage_pressed = false
		fire_down = false
		charging = false
		charge = 0.0
		shield_on = false
		suction_on = false
		if breath_t > 0.0:
			breath_t = maxf(0.0, breath_t - dt)
			world.apply_breath(origin, look, dt)
			vel -= look * (C.BREATH_RECOIL * dt)
			_cap_h_speed(C.BLAST_MAX_H_SPEED)
			if breath_t <= 0.0:
				events.append({"type": "breath_end"})
		else:
			quake_t = maxf(0.0, quake_t - dt)
			if quake_t <= 0.0:
				events.append({"type": "quake_end"})
		return

	# RMB boulder: first it is pulled out of the ground / wall / hill, then thrown where you are looking
	if not boulder_pull.is_empty():
		boulder_pull["t"] = float(boulder_pull["t"]) + dt
		if float(boulder_pull["t"]) >= C.BOULDER_PULL_TIME:
			boulder_pull = {}
			var bo := origin + look * C.BOULDER_HOLD_DIST + Vector3(0.0, 0.15, 0.0)
			var bp = world.spawn_proj("boulder", "player", bo, look * C.BOULDER_SPEED + Vector3(0.0, 1.5, 0.0),
					C.BOULDER_LIFE, C.BOULDER_RADIUS, C.BOULDER_DAMAGE * boulder_mult, C.BOULDER_KNOCKBACK, false)
			boulder_mult = 1.0
			bp.grav = C.BOULDER_GRAVITY
			events.append({"type": "boulder", "origin": origin, "dir": look})

	if element == "fire":
		_update_fire(dt, inp, look, origin)
		return

	if element == "water":
		_update_water(dt, inp, look, origin)
		return

	# Carrying an earth slab: left click throws it (it breaks on whatever it hits)
	if element == "earth" and not world.held.is_empty() and inp.fire_pressed:
		inp.fire_pressed = false
		if world.throw_held(origin, look):
			events.append({"type": "slab_throw", "dir": look})
		return

	# Left button: tap = Air Punch / Rock Throw, hold = charge, release = Air Blast / Earth Wave
	var tap_cost: float = C.ROCK_COST if element == "earth" else C.PUNCH_COST
	if inp.fire_pressed:
		inp.fire_pressed = false
		if (chi < tap_cost or melee_window > 0.0) and not charging:         # no chi for the bending move: fight with your hands
			melee_hold = true
			fire_down = false
			_try_melee(look, origin, false)
		else:
			melee_hold = false
			fire_down = true
			fire_time = 0.0
			charging = false
			charge = 0.0
	if melee_hold:
		if inp.fire_held:
			_try_melee(look, origin, false)               # holding keeps the combo going (cooldown-gated)
		else:
			melee_hold = false
	if fire_down:
		if inp.fire_held:
			fire_time += dt
			if fire_time >= C.TAP_TIME and (charging or chi >= 1.0):
				if not charging:
					charging = true
					events.append({"type": "charge_start"})
				chi_delay = C.CHI_REGEN_DELAY
				if element == "earth":
					_take_acc += dt
					if _take_acc >= 0.16:
						_take_acc = 0.0
						_take_earth_around(look)
				if charge < 1.0 and chi > 0.0:
					charge = minf(1.0, charge + dt / C.CHARGE_TIME)
					chi = maxf(0.0, chi - C.CHARGE_DRAIN * dt)
		else:
			if charging:
				if element == "earth":
					_fire_wave(charge, look, origin)
				else:
					_fire_blast(charge, look, origin)
			elif fire_time < C.TAP_TIME:
				if element == "earth":
					_try_rock(look, origin)
				else:
					_try_punch(look, origin)
			fire_down = false
			charging = false
			charge = 0.0

	# Right click: Air Slice / Boulder
	if inp.slice_pressed:
		inp.slice_pressed = false
		var rmb_cost: float = C.BOULDER_COST if element == "earth" else C.SLICE_COST
		if chi < rmb_cost and boulder_pull.is_empty():
			_try_melee(look, origin, true)
		elif element == "earth":
			_try_boulder(look, origin)
		else:
			_try_slice(look, origin)

	# Z: Stone Barrage (earth only)
	if inp.barrage_pressed:
		inp.barrage_pressed = false
		if element == "earth" and not charging:
			_try_barrage(look, origin)
		elif element == "air" and not charging:
			_try_air_dash(look)

	if element == "earth":
		shield_on = false
		suction_on = false
		if _e_edge and not charging:
			_try_wall(look)
		if _f_edge and not charging:
			_try_pillar(look, origin)
		return

	# Air Shield (hold E): drains chi, reflects enemy bolts (world.gd reads shield_on)
	if inp.shield_held and not charging:
		if not shield_on and chi >= C.SHIELD_MIN_CHI:
			shield_on = true
			events.append({"type": "shield_on"})
		if shield_on:
			chi = maxf(0.0, chi - C.SHIELD_DRAIN * dt)
			chi_delay = C.CHI_REGEN_DELAY
			if chi <= 0.0:
				shield_on = false
	else:
		shield_on = false

	# Air Suction (hold F): drags bots toward you
	if inp.suction_held and not charging:
		if not suction_on and chi >= C.SUCTION_MIN_CHI:
			suction_on = true
			events.append({"type": "suction_on"})
		if suction_on:
			chi = maxf(0.0, chi - C.SUCTION_DRAIN * dt)
			chi_delay = C.CHI_REGEN_DELAY
			world.apply_suction(origin, look, dt)
			if chi <= 0.0:
				suction_on = false
	else:
		suction_on = false


func can_switch_element() -> bool:
	return breath_t <= 0.0 and quake_t <= 0.0 and slam.is_empty() and mantle.is_empty() and octo_t <= 0.0 and rush_t <= 0.0


func _set_element(e: String) -> void:
	if e == element or not can_switch_element():
		return
	element = e
	chi = C.WATER_MAX if e == "water" else minf(chi, chi_cap())       # a waterbender starts with a full pouch
	armor_on = false
	heal_left = 0.0
	world.drop_held()
	world.octo_release()
	_release_channels()
	events.append({"type": "element", "element": e})


func _try_punch(look: Vector3, origin: Vector3) -> void:
	if punch_cd > 0.0 or chi < C.PUNCH_COST:
		return
	chi -= C.PUNCH_COST
	chi_delay = C.CHI_REGEN_DELAY
	punch_cd = C.PUNCH_COOLDOWN
	world.spawn_proj("punch", "player", origin + look * 0.7 + Vector3(0.0, -0.15, 0.0), look * C.PUNCH_SPEED,
			C.PUNCH_LIFE, C.PUNCH_RADIUS, C.PUNCH_DAMAGE, C.PUNCH_KNOCKBACK, false)
	events.append({"type": "punch", "origin": origin, "dir": look})


func _try_melee(look: Vector3, origin: Vector3, heavy: bool) -> void:
	if melee_cd > 0.0:
		return
	var earth := element == "earth"
	var step := 0
	var dmg: float
	var knock: float
	var rng: float = C.MELEE_RANGE
	if heavy:
		melee_combo = 0
		dmg = C.MELEE_EARTH_HEAVY if earth else C.MELEE_AIR_HEAVY
		knock = C.MELEE_HEAVY_KNOCK
		rng = C.MELEE_HEAVY_RANGE
		melee_cd = C.MELEE_HEAVY_CD
		step = 4
	else:
		if melee_window <= 0.0:
			melee_combo = 0
		step = melee_combo + 1
		var arr: Array = C.MELEE_EARTH_DMG if earth else C.MELEE_AIR_DMG
		dmg = arr[melee_combo]
		knock = C.MELEE_KNOCK[melee_combo]
		melee_cd = C.MELEE_EARTH_CD if earth else C.MELEE_AIR_CD
		melee_combo = (melee_combo + 1) % 3
		melee_window = C.MELEE_WINDOW
	var hits: int = world.apply_melee(origin, look, rng, dmg, knock, C.MELEE_COS)
	if hits > 0 and element != "water":              # a waterbender's pouch never refills from fighting
		chi = minf(chi_cap(), chi + C.MELEE_CHI_PER_HIT * hits)
	chi_delay = C.CHI_REGEN_DELAY * 0.5
	var f := _flat_fwd(look)
	if speed() < 9.0:
		var lunge: float = C.MELEE_LUNGE * (1.0 if on_ground else 0.5) * (1.4 if (heavy or step == 3) else 1.0)
		vel.x += f.x * lunge
		vel.z += f.z * lunge
	if earth and (heavy or step == 3) and on_ground:
		world.crater(pos + f * 1.6, 1.3, 0.25)
	events.append({"type": "melee", "step": step, "heavy": heavy, "hits": hits, "origin": origin, "dir": look, "element": element})


func _try_slice(look: Vector3, origin: Vector3) -> void:
	if slice_cd > 0.0 or chi < C.SLICE_COST:
		return
	chi -= C.SLICE_COST
	chi_delay = C.CHI_REGEN_DELAY
	slice_cd = C.SLICE_COOLDOWN
	slice_flip = not slice_flip
	world.spawn_proj("slice", "player", origin + look * 0.9 + Vector3(0.0, -0.2, 0.0), look * C.SLICE_SPEED,
			C.SLICE_LIFE, C.SLICE_RADIUS, C.SLICE_DAMAGE * _combo_mult("slice"), C.SLICE_KNOCKBACK, true, 0.95 if slice_flip else -0.95)
	events.append({"type": "slice", "origin": origin, "dir": look})


func _fire_blast(c: float, look: Vector3, origin: Vector3) -> void:
	var hits: int = world.apply_blast(origin, look, c)
	punch_cd = maxf(punch_cd, 0.3)
	var boosted := false
	if look.y < C.BLAST_BOOST_LOOK_Y:
		var hit: Dictionary = world.raycast_solid(origin, look, C.BLAST_BOOST_RANGE)
		if hit["hit"]:
			boosted = true
			vel += -look * C.BLAST_SELF_PUSH * (0.5 + c)
			_cap_h_speed(C.BLAST_MAX_H_SPEED)
			if vel.y > 1.0:
				on_ground = false
				coyote = 0.0
				air_time = 0.0
				if sliding:
					_end_slide()
	events.append({"type": "blast", "origin": origin, "dir": look, "charge": c, "hits": hits, "boosted": boosted})


# ------------------------------------------------------------------ earthbending

func _flat_fwd(look: Vector3) -> Vector3:
	var f := Vector3(look.x, 0.0, look.z)
	return f.normalized() if f.length() > 0.05 else Vector3(-sin(yaw), 0.0, -cos(yaw))


func _try_rock(look: Vector3, origin: Vector3) -> void:
	if punch_cd > 0.0 or chi < C.ROCK_COST:
		return
	chi -= C.ROCK_COST
	chi_delay = C.CHI_REGEN_DELAY
	punch_cd = C.ROCK_COOLDOWN
	if on_ground:                                   # the rock is torn out of the ground in front of you
		world.crater(pos + _flat_fwd(look) * 1.8, 1.1, 0.35)
	var p = world.spawn_proj("rock", "player", origin + look * 1.0 + Vector3(0.0, -0.25, 0.0),
			look * C.ROCK_SPEED + Vector3(0.0, 2.5, 0.0), C.ROCK_LIFE, C.ROCK_RADIUS, C.ROCK_DAMAGE, C.ROCK_KNOCKBACK, false)
	p.grav = C.ROCK_GRAVITY
	events.append({"type": "rock", "origin": origin, "dir": look})


func _try_boulder(look: Vector3, origin: Vector3) -> void:
	if boulder_cd > 0.0 or chi < C.BOULDER_COST or not boulder_pull.is_empty():
		return
	chi -= C.BOULDER_COST
	chi_delay = C.CHI_REGEN_DELAY
	boulder_cd = C.BOULDER_COOLDOWN
	boulder_mult = _combo_mult("boulder")
	# the nearest ground, wall or hillside along your sight line (or just ahead of your feet) is the source
	var src: Vector3
	var r: Dictionary = world.aim_point(origin, look, C.BOULDER_REACH)
	if bool(r["hit"]):
		src = r["point"]
	else:
		var f := pos + _flat_fwd(look) * 4.0
		src = Vector3(f.x, world.height_at(f.x, f.z), f.z)
	world.crater(src, C.BOULDER_PULL_RADIUS, C.BOULDER_PULL_DEPTH)
	boulder_pull = {"t": 0.0, "src": src}
	events.append({"type": "boulder_pull", "src": src, "origin": origin})


# Earthbending charge: the ground around you gives up a little earth every moment
func _take_earth_around(look: Vector3) -> void:
	var a := randf() * TAU
	var rr := randf_range(1.3, 2.6)
	var at := Vector3(pos.x + cos(a) * rr, 0.0, pos.z + sin(a) * rr)
	at.y = world.height_at(at.x, at.z)
	if absf(at.y - pos.y) > 3.0:
		return
	world.crater(at, 1.2, 0.14)
	events.append({"type": "earth_take", "src": at})


func _try_barrage(look: Vector3, origin: Vector3) -> void:
	if barrage_cd > 0.0 or chi < C.BARRAGE_COST:
		return
	chi -= C.BARRAGE_COST
	chi_delay = C.CHI_REGEN_DELAY
	barrage_cd = C.BARRAGE_COOLDOWN
	if on_ground:
		world.crater(pos + _flat_fwd(look) * 1.8, 1.6, 0.5)
	var right := look.cross(Vector3.UP)
	right = right.normalized() if right.length() > 0.01 else Vector3.RIGHT
	var up := right.cross(look).normalized()
	var n := C.BARRAGE_COUNT
	for k in range(n):
		var t := float(k) - float(n - 1) * 0.5              # fan out left to right, alternating height
		var lift := 0.05 if k % 2 == 0 else -0.03
		var d := (look + right * t * C.BARRAGE_SPREAD + up * lift).normalized()
		var p = world.spawn_proj("rock", "player", origin + look * 1.0 + right * t * 0.28 + Vector3(0.0, -0.3, 0.0),
				d * C.BARRAGE_SPEED + Vector3(0.0, 1.5, 0.0), C.ROCK_LIFE, 0.5, C.BARRAGE_DAMAGE, C.ROCK_KNOCKBACK * 0.7, false)
		p.grav = C.ROCK_GRAVITY
		p.splash = C.BARRAGE_SPLASH_DAMAGE
	events.append({"type": "barrage", "origin": origin, "dir": look})
	_combo_open("barrage")


func _fire_wave(c: float, look: Vector3, origin: Vector3) -> void:
	punch_cd = maxf(punch_cd, 0.35)
	world.earth_wave(pos, _flat_fwd(look), c)
	events.append({"type": "wave", "origin": origin, "dir": look, "charge": c})


func _toggle_armor() -> void:
	if armor_cd > 0.0:
		return
	if armor_on:
		armor_on = false
		armor_cd = C.ARMOR_TOGGLE_CD
		events.append({"type": "armor_off"})
	elif chi >= C.ARMOR_COST and armor_hp > 5.0:
		chi -= C.ARMOR_COST
		chi_delay = C.CHI_REGEN_DELAY
		armor_on = true
		armor_cd = C.ARMOR_TOGGLE_CD
		events.append({"type": "armor_on"})


func _grab_or_plant() -> void:
	var look := look_dir()
	if world.held.is_empty():
		if world.grab_wall(pos):
			events.append({"type": "grab"})
	else:
		if world.plant_wall(pos, _flat_fwd(look)):
			events.append({"type": "plant"})


func _try_wall(look: Vector3) -> void:
	if wall_cd > 0.0 or chi < C.WALL_COST or not world.held.is_empty():
		return
	chi -= C.WALL_COST
	chi_delay = C.CHI_REGEN_DELAY
	wall_cd = C.WALL_COOLDOWN
	world.earth_wall(pos, _flat_fwd(look))
	events.append({"type": "wall"})


# Pillar where the crosshair meets the ground; look at your own feet to ride it.
func _try_pillar(look: Vector3, origin: Vector3) -> void:
	if pillar_cd > 0.0 or pillar_charges <= 0 or chi < C.PILLAR_COST:
		return
	var ray: Dictionary = world.aim_point(origin, look, C.PILLAR_RANGE)
	var at := pos
	if ray["hit"]:
		at = ray["point"]
	var what: String = world.earth_spire(at)
	if what == "":
		events.append({"type": "need_earth"})              # open water is not earth: nothing is spent
		return
	chi -= C.PILLAR_COST
	chi_delay = C.CHI_REGEN_DELAY
	pillar_cd = C.PILLAR_COOLDOWN
	pillar_charges -= 1
	events.append({"type": "pillar", "pos": at, "what": what, "charges": pillar_charges})


# ------------------------------------------------------------------ waterbending
# The chi bar is the water pouch. Nothing refills it except F near water (and that never lowers the map's water).

func _flat_heading(look: Vector3) -> Vector3:
	var hv := Vector3(vel.x, 0.0, vel.z)
	return hv.normalized() if hv.length() > 1.0 else _flat_fwd(look)


# Q: toggles the Ice Skate. In Octopus Form it grabs an enemy, and pressed again throws them.
func _water_q() -> void:
	if octo_t > 0.0:
		if octo_q_cd > 0.0:
			return
		var look := look_dir()
		var origin := pos + Vector3(0.0, eye_height(), 0.0)
		if world.grabbed != null:
			world.octo_throw(look)
			octo_q_cd = C.OCTO_GRAB_COOLDOWN
			events.append({"type": "octo_throw", "origin": origin, "dir": look})
		elif world.octo_grab(origin, look):
			octo_q_cd = 0.4
			events.append({"type": "octo_grab", "origin": origin, "dir": look})
		return
	if skating:
		skating = false
	elif not _wet_within(C.ICE_SKATE_WATER_RANGE):
		events.append({"type": "need_water"})            # an ice skate needs water or ice to glide on
	elif chi >= _cost(C.ICE_SKATE_COST) and not sliding and not jet_on:
		skating = true
		skate_dry_t = 0.0
		events.append({"type": "skate_on", "pos": pos})


# In or right next to water or ice, waterbending costs nothing.
func _cost(c: float) -> float:
	return 0.0 if (element == "water" and near_water) else c


# Spend pouch water. What was spent lands on the ground at `at` as a puddle, ready to be gathered again.
func _spend(c: float, at: Vector3) -> void:
	var amt := _cost(c)
	chi -= amt
	if amt > 0.0:
		world.deposit_water(at, amt)


# Where a move aimed along `look` comes down: the first ground it meets, or the ground below its far end.
func _landing(origin: Vector3, look: Vector3, reach: float) -> Vector3:
	var r: Dictionary = world.aim_point(origin, look, reach)
	if bool(r["hit"]):
		return r["point"]
	var e := origin + look * reach
	return Vector3(e.x, world.height_at(e.x, e.z), e.z)


# Is there water, a film of it, or ice (frozen water) under you or within `r` metres?
func _wet_within(r: float) -> bool:
	var t = world.terrain
	if t.water_depth_at(pos.x, pos.z) > 0.05 or t.ice_at(pos.x, pos.z):
		return true
	return t.nearest_water(pos.x, pos.z, r) != null


func _update_water(dt: float, inp: InputState, look: Vector3, origin: Vector3) -> void:
	shield_on = false
	suction_on = false
	charging = false
	charge = 0.0

	if heal_left > 0.0:                                 # a heal pours in over a moment
		var amt := minf(heal_left, C.HEAL_AMOUNT / C.HEAL_TIME * dt)
		heal_left -= amt
		hp = minf(C.PLAYER_HP, hp + amt)

	# X: held = Tidal Wave (needs water close by), tapped = Octopus Form
	if ult_hold >= 0.0:
		if inp.ult_held:
			ult_hold += dt
			if ult_hold >= C.ULT_HOLD_TIME:
				ult_hold = -1.0
				_start_tide(look, origin)
		else:
			ult_hold = -1.0
			_start_octopus()

	if octo_t > 0.0:
		octo_t = maxf(0.0, octo_t - dt)
		_update_octopus(inp, look, origin)
		if octo_t <= 0.0:
			_end_octopus()
		return

	# T: freeze / unfreeze. On: the water around and just ahead of you turns to ice as you move. Pressed again: it turns
	# off and the ice around you thaws back into water.
	if inp.freeze_pressed:
		inp.freeze_pressed = false
		if freezing:
			freezing = false
			world.thaw_near(pos, C.FREEZE_THAW_RADIUS)
			events.append({"type": "freeze_off", "pos": pos})
		elif _wet_within(C.ICE_SKATE_WATER_RANGE):
			freezing = true
			freeze_dry_t = 0.0
			freeze_acc = C.ICE_FREEZE_STEP                  # freeze right away
			events.append({"type": "freeze_on", "pos": pos})
		else:
			events.append({"type": "need_water"})
	if freezing:
		freeze_acc += dt
		if freeze_acc >= C.ICE_FREEZE_STEP:
			freeze_acc = 0.0
			world.freeze_water_near(pos + _flat_heading(look) * C.ICE_FREEZE_AHEAD, C.ICE_FREEZE_RADIUS)
		if _wet_within(C.ICE_SKATE_WATER_RANGE):
			freeze_dry_t = 0.0
		else:
			freeze_dry_t += dt
			if freeze_dry_t >= C.FREEZE_DRY_GRACE:          # no water or ice left around: the freeze switches itself off
				freezing = false

	# Ice Skate (Q): glide fast over ice and water. It never freezes anything by itself.
	if skating:
		if _wet_within(C.ICE_SKATE_WATER_RANGE):         # with no water or ice around, the skate gives out
			skate_dry_t = 0.0
		else:
			skate_dry_t += dt
			if skate_dry_t >= C.ICE_SKATE_DRY_GRACE:
				skating = false
				events.append({"type": "skate_off", "pos": pos})

	# Hold F: draw water into the pouch from the water under you, close by, or where you are looking
	gathering = false
	if inp.suction_held and not inp.fire_held and chi < chi_cap() - 0.01:
		var wf: Dictionary = world.find_water(pos, origin, look, C.GATHER_REACH, C.GATHER_NEAR)
		if bool(wf["found"]):
			gathering = true
			chi = minf(chi_cap(), chi + C.GATHER_RATE * dt)
			gather_acc += dt
			if gather_acc >= C.GATHER_STEP:
				gather_acc = 0.0
				events.append({"type": "gather", "src": wf["point"], "origin": origin})

	# Left button: tap = Water Whip, hold = Water Jet. An empty pouch means fists.
	if inp.fire_pressed:
		inp.fire_pressed = false
		if chi < _cost(C.WHIP_COST) or melee_window > 0.0:
			melee_hold = true
			fire_down = false
			_try_melee(look, origin, false)
		else:
			melee_hold = false
			fire_down = true
			fire_time = 0.0
			jet_on = false
	if melee_hold:
		if inp.fire_held:
			_try_melee(look, origin, false)
		else:
			melee_hold = false
	if fire_down:
		if inp.fire_held:
			fire_time += dt
			if fire_time >= C.TAP_TIME and bullet_cd <= 0.0 and chi >= _cost(C.BULLET_COST):
				_fire_bullet(look, origin)                                   # hold: a quick stream of water bullets
		else:
			if fire_time < C.TAP_TIME:
				_try_whip(look, origin)
			fire_down = false

	# Right click: heal yourself (fists when the pouch is too low)
	if inp.slice_pressed:
		inp.slice_pressed = false
		if chi < _cost(C.HEAL_COST):
			_try_melee(look, origin, true)
		elif heal_cd <= 0.0 and heal_left <= 0.0 and hp < C.PLAYER_HP - 0.5:
			_spend(C.HEAL_COST, pos)
			chi_delay = C.WATER_PASSIVE_DELAY
			heal_cd = C.HEAL_COOLDOWN
			heal_left = C.HEAL_AMOUNT
			events.append({"type": "heal", "origin": origin})

	# Z: Ice Shards
	if inp.barrage_pressed:
		inp.barrage_pressed = false
		_try_shards(look, origin)

	# E: Ice Wall (or freeze the enemy right in front of you)
	if _e_edge and not jet_on:
		_try_ice_wall(look)


func _fire_bullet(look: Vector3, origin: Vector3) -> void:
	var water := _cost(C.BULLET_COST)
	chi -= water
	chi_delay = C.WATER_PASSIVE_DELAY
	bullet_cd = C.BULLET_COOLDOWN
	var right := look.cross(Vector3.UP)
	right = right.normalized() if right.length() > 0.01 else Vector3.RIGHT
	whip_flip = not whip_flip
	var side := 0.28 if whip_flip else -0.28
	var bp = world.spawn_proj("wbullet", "player", origin + look * 0.9 + right * side + Vector3(0.0, -0.22, 0.0),
			look * C.BULLET_SPEED, C.BULLET_LIFE, C.BULLET_RADIUS, C.BULLET_DAMAGE, C.BULLET_KNOCKBACK, false)
	bp.water = water * 2.0                                   # what it carried lands as a puddle where it ends
	events.append({"type": "bullet", "dir": look})


# Hold Space with water (or ice) under your feet: a jet lifts you steadily. Stops on release, when the water is not
# below you any more, or above PROPEL_REACH. Then PROPEL_COOLDOWN of rest.
func _update_propel(dt: float, inp) -> void:
	var was := propelling
	propelling = false
	if not was and not propel_armed and not inp.jump_held and (on_ground or (water_depth > 0.05 and pos.y - world.terrain.surface_at(pos.x, pos.z) <= C.PROPEL_REARM_HEIGHT)):
		propel_armed = true
	if element == "water" and inp.jump_held and propel_armed and propel_cd <= 0.0 and not skating and not sliding:
		var t = world.terrain
		if water_depth > 0.05 or t.ice_at(pos.x, pos.z):
			if pos.y - t.surface_at(pos.x, pos.z) <= C.PROPEL_REACH and (was or chi >= _cost(C.PROPEL_MIN)) and (chi > 0.0 or near_water):
				propelling = true
	if propelling:
		if not was:
			events.append({"type": "propel", "pos": pos})
		jump_buf = 0.0
		on_ground = false
		coyote = 0.0
		chi = maxf(0.0, chi - _cost(C.PROPEL_DRAIN) * dt)
		chi_delay = C.WATER_PASSIVE_DELAY
	elif was:
		propel_cd = C.PROPEL_COOLDOWN
		propel_armed = false


func _propel_forces(dt: float, wish: Vector3, wl: float) -> void:
	air_time = 0.0
	ground_time = 0.0
	elevating = false
	vel.y = move_toward(vel.y, C.PROPEL_VY, C.PROPEL_ACCEL * dt)
	_air_control(dt, wish, wl, C.PROPEL_AIR_ACCEL, C.PROPEL_SPEED)
	var drag := maxf(0.0, 1.0 - C.PROPEL_DRAG * dt)
	if speed() > C.PROPEL_SPEED:
		vel.x *= drag
		vel.z *= drag


func _try_whip(look: Vector3, origin: Vector3) -> void:
	if punch_cd > 0.0 or chi < _cost(C.WHIP_COST):
		return
	_spend(C.WHIP_COST, _landing(origin, look, C.WHIP_REACH))
	chi_delay = C.WATER_PASSIVE_DELAY
	punch_cd = C.WHIP_COOLDOWN
	var hits: int = world.apply_whip(origin, look, C.WHIP_REACH, C.WHIP_WIDTH, C.WHIP_DAMAGE * _combo_mult("whip"), C.WHIP_KNOCKBACK)
	whip_flip = not whip_flip
	events.append({"type": "whip", "origin": origin, "dir": look, "hits": hits, "flip": whip_flip})


func _try_shards(look: Vector3, origin: Vector3) -> void:
	if barrage_cd > 0.0 or chi < _cost(C.SHARD_COST) or jet_on:
		return
	var shard_water := _cost(C.SHARD_COST)                 # each spike carries its share and lands as a puddle where it ends
	chi -= shard_water
	chi_delay = C.WATER_PASSIVE_DELAY
	barrage_cd = C.SHARD_COOLDOWN
	var right := look.cross(Vector3.UP)
	right = right.normalized() if right.length() > 0.01 else Vector3.RIGHT
	var up := right.cross(look).normalized()
	var n := C.SHARD_COUNT
	for k in range(n):
		var t := float(k) - float(n - 1) * 0.5
		var lift := 0.03 if k % 2 == 0 else -0.02
		var d := (look + right * t * C.SHARD_SPREAD + up * lift).normalized()
		var sp = world.spawn_proj("shard", "player", origin + look * 0.9 + right * t * 0.22 + Vector3(0.0, -0.25, 0.0),
				d * C.SHARD_SPEED, C.SHARD_LIFE, C.SHARD_RADIUS, C.SHARD_DAMAGE, C.SHARD_KNOCKBACK, false)
		sp.water = shard_water / float(n) * 3.0           # (a bit more than its share: a tiny puddle is no use to anyone)
	events.append({"type": "shards", "origin": origin, "dir": look})
	_combo_open("shards")


func _try_ice_wall(look: Vector3) -> void:
	var wall: int = world.ice_wall_near(pos, C.DISC_NEAR)
	if wall >= 0 and not world.freeze_target_near(pos, _flat_fwd(look)):   # close to your own wall: E throws discs of ice from it
		if disc_cd > 0.0 or chi < _cost(C.DISC_COST):
			return
		_spend(C.DISC_COST, pos + _flat_fwd(look) * 6.0)
		chi_delay = C.WATER_PASSIVE_DELAY
		disc_cd = C.DISC_COOLDOWN
		world.ice_discs(wall, pos + Vector3(0.0, eye_height(), 0.0), look, "player", C.DISC_DAMAGE)
		events.append({"type": "disc_throw", "dir": look})
		return
	if iwall_cd > 0.0 or chi < _cost(C.ICE_WALL_COST):
		return
	_spend(C.ICE_WALL_COST, pos + _flat_fwd(look) * 1.5)
	chi_delay = C.WATER_PASSIVE_DELAY
	iwall_cd = C.ICE_WALL_COOLDOWN
	var what: String = world.ice_wall(pos, _flat_fwd(look))
	events.append({"type": "ice_wall", "what": what, "pos": pos, "dir": look})


# ---- ultimates: Tidal Wave (hold X near water) and Octopus Form (tap X)

func _start_tide(look: Vector3, origin: Vector3) -> void:
	var wf: Dictionary = world.find_water(pos, origin, look, C.TIDE_WATER_RANGE, C.TIDE_WATER_RANGE)
	if not bool(wf["found"]):
		events.append({"type": "need_water"})            # the meter is kept: find water and try again
		return
	ult = 0.0
	_release_channels()
	var tw: Dictionary = world.tidal_wave(pos, _flat_fwd(look), wf["point"])
	ult_lock = float(tw["len"]) / C.TIDE_SPEED + 0.5
	events.append({"type": "tide", "origin": origin, "dir": look, "src": wf["point"], "strength": tw["strength"], "half": tw["half"]})


func _start_octopus() -> void:
	ult = 0.0
	octo_t = C.OCTO_TIME
	octo_cd = 0.0
	octo_cd_r = 0.0
	octo_slam_cd = 0.0
	octo_q_cd = 0.0
	_release_channels()
	events.append({"type": "octo_start"})


func _end_octopus() -> void:
	world.octo_release()
	ult_lock = 0.5
	events.append({"type": "octo_end"})


# In Octopus Form the moves change: LMB / RMB lash with the left / right arm, E slams both from above, Q grabs / throws.
func _update_octopus(inp: InputState, look: Vector3, origin: Vector3) -> void:
	jet_on = false
	gathering = false
	fire_down = false
	melee_hold = false
	inp.barrage_pressed = false
	inp.freeze_pressed = false
	if inp.fire_pressed or inp.fire_held:
		inp.fire_pressed = false
		if octo_cd <= 0.0:
			octo_cd = C.OCTO_SWIPE_COOLDOWN
			_octo_swipe(0, look, origin)
	if inp.slice_pressed:
		inp.slice_pressed = false
		if octo_cd_r <= 0.0:
			octo_cd_r = C.OCTO_SWIPE_COOLDOWN
			_octo_swipe(1, look, origin)
	if _e_edge and octo_slam_cd <= 0.0:
		octo_slam_cd = C.OCTO_SLAM_COOLDOWN
		var c := pos + _flat_fwd(look) * C.OCTO_SLAM_DIST
		c.y = world.height_at(c.x, c.z)
		var hits: int = world.octo_slam(c, C.OCTO_SLAM_RADIUS, C.OCTO_SLAM_DAMAGE)
		events.append({"type": "octo_slam", "pos": c, "hits": hits, "origin": origin})


func _octo_swipe(side: int, look: Vector3, origin: Vector3) -> void:
	var hits: int = world.apply_whip(origin, look, C.OCTO_REACH, C.OCTO_WIDTH, C.OCTO_SWIPE_DAMAGE, C.OCTO_SWIPE_KNOCK, true)
	events.append({"type": "octo_swipe", "side": side, "origin": origin, "dir": look, "hits": hits})


# ------------------------------------------------------------------ ultimates

func _try_ult() -> void:
	if not ult_ready():
		return
	match ult_kind():
		"bomb", "quake":
			_start_slam()
		"clap":
			_start_clap()
		_:
			_start_breath()


func _release_channels() -> void:
	fire_down = false
	charging = false
	charge = 0.0
	shield_on = false
	suction_on = false
	scooter = false
	skating = false
	elevating = false
	sliding = false
	jet_on = false
	fcharging = false
	light_t = -1.0
	gathering = false
	freezing = false
	ult_hold = -1.0


func _start_breath() -> void:
	ult = 0.0
	breath_t = C.BREATH_DURATION
	_release_channels()
	events.append({"type": "breath_start"})


# Earth Clap: two slabs open from the ground around the target and slam together.
func _start_clap() -> void:
	ult = 0.0
	_release_channels()
	var info: Dictionary = world.earth_clap(pos, look_dir())
	events.append({"type": "clap", "pos": info["pos"], "dir": info["dir"]})


func _begin_quake() -> void:
	quake_t = C.QUAKE_DURATION
	_release_channels()
	world.earth_quake(pos)
	events.append({"type": "quake_start", "pos": pos})


func _start_slam() -> void:
	slam = {"phase": "wind", "t": 0.0, "h0": height_above_ground(), "earth": element == "earth"}
	ult = 0.0
	_release_channels()
	gliding = false
	vel = Vector3.ZERO
	events.append({"type": "bomb_wind", "pos": pos, "earth": element == "earth"})


func _update_slam(dt: float, wish: Vector3) -> void:
	slam["t"] = float(slam["t"]) + dt
	if String(slam["phase"]) == "wind":
		vel = vel.move_toward(Vector3(0.0, 1.2, 0.0), 40.0 * dt)       # hang in the air, gathering
		if float(slam["t"]) >= C.BOMB_WINDUP:
			slam["phase"] = "dive"
			vel = Vector3(0.0, -C.BOMB_DIVE_SPEED, 0.0)
			events.append({"type": "bomb_dive", "pos": pos, "earth": bool(slam.get("earth", false))})
	else:
		var hx := vel.x + wish.x * C.BOMB_STEER * dt
		var hz := vel.z + wish.z * C.BOMB_STEER * dt
		var hs := Vector2(hx, hz).length()
		if hs > C.BOMB_STEER_MAX:
			hx *= C.BOMB_STEER_MAX / hs
			hz *= C.BOMB_STEER_MAX / hs
		vel = Vector3(hx, -C.BOMB_DIVE_SPEED, hz)
	_integrate(dt)
	if on_ground:
		_slam_impact()


func _slam_impact() -> void:
	if bool(slam.get("earth", false)):                  # Earthquake dive: a shockwave, then the ground shakes
		var hit_n: int = world.apply_slam(pos, C.QUAKE_LAND_RADIUS, C.QUAKE_LAND_DAMAGE, 16.0)
		events.append({"type": "quake_land", "pos": pos, "radius": C.QUAKE_LAND_RADIUS, "hits": hit_n})
		pos.y = world.height_at(pos.x, pos.z)
		slam = {}
		vel = Vector3.ZERO
		jump_buf = 0.0
		_begin_quake()
		return
	var h0: float = slam["h0"]
	var k := clampf((h0 - C.BOMB_MIN_HEIGHT) / 20.0, 0.0, 1.0)
	var r := C.BOMB_RADIUS * (0.7 + 0.3 * k)
	var dmg := C.BOMB_DAMAGE * (0.8 + 0.2 * k)
	var hits: int = world.apply_slam(pos, r, dmg, C.BOMB_KNOCKBACK)
	events.append({"type": "bomb", "pos": pos, "radius": r, "hits": hits})
	pos.y = world.height_at(pos.x, pos.z)        # the crater opened under you: settle on its floor
	slam = {}
	vel = Vector3.ZERO
	jump_buf = 0.0


# ------------------------------------------------------------------ firebending
# Resource: the heat meter (no chi). Every attack adds heat; above HEAT_HOT you hit 20% harder and dash further; at 100%
# you overheat (no moves, slow). Heat only falls when you have not attacked for a moment. Standing in water cools it fast.

func _add_heat(h: float) -> void:
	heat += h
	heat_idle = 0.0


func _update_heat(dt: float) -> void:
	heat_idle += dt
	var wet: bool = water_depth >= C.SOAK_DEPTH
	if wet:
		soak_t = C.SOAK_TIME
		heat -= C.HEAT_SOAK_DROP * dt
		if fcharging:
			fcharging = false
		if guard_t > 0.0:
			guard_t = 0.0                                 # water puts the ring out
			events.append({"type": "too_wet"})
		if light_t >= 0.0:
			light_t = -1.0
			events.append({"type": "lightning_cancel"})
	elif soak_t > 0.0:
		soak_t = maxf(0.0, soak_t - dt)
	elif heat_idle >= C.HEAT_IDLE and overheat_t <= 0.0:
		heat -= C.HEAT_DECAY * dt
	heat = clampf(heat, 0.0, C.HEAT_MAX)
	if overheat_t > 0.0:
		overheat_t -= dt
		if overheat_t <= 0.0:
			overheat_t = 0.0
			heat = C.OVERHEAT_RESET
			events.append({"type": "overheat_end"})
	elif heat >= C.HEAT_MAX - 0.001 and not debug_nocd:
		overheat_t = C.OVERHEAT_TIME
		fcharging = false
		fire_down = false
		dash_t = 0.0
		dash_kick = false
		if light_t >= 0.0:
			light_t = -1.0
		events.append({"type": "overheat", "pos": pos})


func _update_fire(dt: float, inp: InputState, look: Vector3, origin: Vector3) -> void:
	shield_on = false
	suction_on = false
	charging = false
	charge = 0.0
	if overheat_t > 0.0:                                 # overheated: nothing works until it passes
		_clear_edges(inp)
		inp.fire_held = false
		fcharging = false
		fire_down = false
		ult_hold = -1.0
		_e_edge = false
		_f_edge = false
		return

	if rush_t > 0.0:                                     # the rush has its own controls (steer with the mouse)
		_clear_edges(inp)
		fcharging = false
		fire_down = false
		return

	# X: tap = Dragon Rush, hold = Lightning (about 2 s standing focused, then the bolt)
	if ult_hold >= 0.0:
		if inp.ult_held:
			ult_hold += dt
			if ult_hold >= C.ULT_HOLD_TIME:
				ult_hold = -1.0
				_start_lightning()
		else:
			ult_hold = -1.0
			_start_rush(look)
			return
	if light_t >= 0.0:
		_clear_edges(inp)
		fcharging = false
		fire_down = false
		if water_depth >= C.SOAK_DEPTH:
			light_t = -1.0                                # stepped into water: the charge is lost, the meter is kept
			events.append({"type": "lightning_cancel"})
			events.append({"type": "too_wet"})
		elif not inp.ult_held:
			if light_t >= C.LIGHT_MIN_CHARGE:
				_fire_lightning(look, origin)             # let go after the minimum: the bolt goes, scaled by the charge
			else:
				light_t = -1.0                            # let go early: the charge fizzles, the meter is kept
				events.append({"type": "lightning_cancel"})
		else:
			light_t += dt
			if light_t >= C.LIGHT_CHARGE:
				_fire_lightning(look, origin)
		return

	# Left button: tap = small fireball, hold and let go = big fireball
	if inp.fire_pressed:
		inp.fire_pressed = false
		fire_down = true
		fire_time = 0.0
		fcharging = false
	if fire_down:
		if inp.fire_held:
			fire_time += dt
			if fire_time >= C.TAP_TIME and not fcharging:
				fcharging = true
				events.append({"type": "fbig_charge"})
		else:
			if fcharging:
				_try_fbig(look, origin)
			elif fire_time < C.TAP_TIME:
				_try_fpunch(look, origin)
			fcharging = false
			fire_down = false

	# Right click: flame burst
	if inp.slice_pressed:
		inp.slice_pressed = false
		_try_fburst(look, origin)

	# Z: fire kick, F: fire ring
	if inp.barrage_pressed:
		inp.barrage_pressed = false
		_try_fkick()
	if _f_edge:
		_try_ring(origin)


func _try_fpunch(look: Vector3, origin: Vector3) -> void:
	if fpunch_cd > 0.0:
		return
	fpunch_cd = C.FPUNCH_COOLDOWN
	_add_heat(C.FPUNCH_HEAT)
	world.spawn_proj("fpunch", "player", origin + look * 0.7 + Vector3(0.0, -0.15, 0.0), look * C.FPUNCH_SPEED,
			C.FPUNCH_LIFE, C.FPUNCH_RADIUS, C.FPUNCH_DAMAGE * _hot_mult(), C.FPUNCH_KNOCK, false)
	events.append({"type": "fpunch", "origin": origin, "dir": look})


# Big fireball: a hit hurts, and it bursts for splash damage around where it lands.
func _try_fbig(look: Vector3, origin: Vector3) -> void:
	if fbig_cd > 0.0:
		return
	fbig_cd = C.FBIG_COOLDOWN
	fpunch_cd = maxf(fpunch_cd, 0.3)                      # no small fireball right on its heels
	_add_heat(C.FBIG_HEAT)
	var p = world.spawn_proj("fbig", "player", origin + look * 0.9 + Vector3(0.0, -0.2, 0.0), look * C.FBIG_SPEED,
			C.FBIG_LIFE, C.FBIG_RADIUS, C.FBIG_DAMAGE * _hot_mult(), C.FBIG_KNOCK, false)
	p.splash = C.FBIG_SPLASH_DAMAGE * _hot_mult()
	events.append({"type": "fbig", "origin": origin, "dir": look})


# Flame burst: a spread of pellets in a fixed sunflower pattern (no random numbers: the sim stays deterministic).
func _try_fburst(look: Vector3, origin: Vector3) -> void:
	if fburst_cd > 0.0:
		return
	fburst_cd = C.FBURST_COOLDOWN
	_add_heat(C.FBURST_HEAT)
	var cm := _combo_mult("fburst")
	var right := look.cross(Vector3.UP)
	right = right.normalized() if right.length() > 0.01 else Vector3.RIGHT
	var up := right.cross(look)
	var n := C.FBURST_PELLETS
	for k in range(n):
		var ang := float(k) * 2.39996
		var rad := sqrt((float(k) + 0.5) / float(n)) * C.FBURST_SPREAD
		var d := (look + (right * cos(ang) + up * sin(ang)) * rad).normalized()
		world.spawn_proj("fpellet", "player", origin + look * 0.8 + Vector3(0.0, -0.2, 0.0), d * C.FBURST_SPEED,
				C.FBURST_LIFE, C.FBURST_RADIUS, C.FBURST_DAMAGE * _hot_mult() * cm, C.FBURST_KNOCK, false)
	events.append({"type": "fburst", "origin": origin, "dir": look})


func _try_ring(origin: Vector3) -> void:
	if ring_cd > 0.0 or soak_t > 0.0:
		if soak_t > 0.0:
			events.append({"type": "too_wet"})
		return
	ring_cd = C.RING_COOLDOWN
	guard_t = C.RING_GUARD_TIME
	_add_heat(C.RING_HEAT)
	var hits: int = world.fire_ring(pos, C.RING_RADIUS, C.RING_DAMAGE * _hot_mult(), C.RING_KNOCK)
	events.append({"type": "fring", "pos": pos, "radius": C.RING_RADIUS, "hits": hits})


# Z (fire): a lunge forward, then an axe kick where you land. Not while swimming. In the air it uses the one dash per landing.
func _try_fkick() -> void:
	if dash_cd > 0.0 or overheat_t > 0.0 or rush_t > 0.0 or light_t >= 0.0 or swimming or dash_t > 0.0:
		return
	if not on_ground and dash_air_used:
		return
	var d := Vector3(-sin(yaw), 0.0, -cos(yaw))
	_start_dash(d, C.FKICK_LUNGE_DIST / C.FKICK_LUNGE_TIME, C.FKICK_LUNGE_TIME, C.FKICK_EXIT_SPEED, C.FKICK_COOLDOWN)
	dash_kick = true
	_add_heat(C.FKICK_HEAT)
	events.append({"type": "fkick", "pos": pos, "dir": d})
	_combo_open("fkick")


# Z (air): a burst of ADASH_DIST metres along where you look, pitch included (look up and you climb). One in the air per
# landing; a dash that leaves the ground counts as that one. Costs chi, short cooldown, ends at a capped exit speed.
func _try_air_dash(look: Vector3) -> void:
	if dash_cd > 0.0 or dash_t > 0.0 or swimming or chi < C.ADASH_COST or not slam.is_empty() or breath_t > 0.0 or quake_t > 0.0:
		return
	if not on_ground and dash_air_used:
		return
	chi = maxf(0.0, chi - C.ADASH_COST)
	chi_delay = C.CHI_REGEN_DELAY
	gliding = false
	scooter = false
	if look.y > 0.05:
		on_ground = false                                 # climbing: leaves the ground at once (and uses the air dash)
		ground_time = 0.0
	_start_dash(look, C.ADASH_DIST / C.ADASH_TIME, C.ADASH_TIME, C.ADASH_EXIT_SPEED, C.ADASH_COOLDOWN)
	events.append({"type": "adash", "pos": pos, "dir": look})
	_combo_open("adash")


func _start_dash(d: Vector3, spd: float, t: float, exit_speed: float, cd: float) -> void:
	dash_dir = d
	dash_t = t
	dash_speed = spd
	dash_exit = exit_speed
	dash_cd = cd
	dash_kick = false
	if not on_ground:
		dash_air_used = true
	if sliding:
		_end_slide()


func _step_dash(dt: float) -> void:
	dash_t -= dt
	vel.x = dash_dir.x * dash_speed
	vel.z = dash_dir.z * dash_speed
	if dash_dir.y > 0.001 or (dash_dir.y < -0.001 and not on_ground):
		vel.y = dash_dir.y * dash_speed
	elif not on_ground:
		vel.y = 0.0                                       # no falling mid-dash
	_integrate(dt)
	if dash_dir.y > 0.05 and not on_ground:
		dash_air_used = true                              # a climbing dash that left the ground (even on a slope) is the air dash
	if dash_t <= 0.0:
		dash_t = 0.0
		var k := minf(1.0, dash_exit / maxf(vel.length(), 0.001))
		vel *= k
		if dash_kick:
			dash_kick = false
			_kick_hit()


# The axe kick: a short arc in front of where the lunge ended.
func _kick_hit() -> void:
	var d := Vector3(dash_dir.x, 0.0, dash_dir.z)
	var c := pos + Vector3(0.0, 1.0, 0.0)
	var hits: int = world.apply_kick(c, d, C.FKICK_REACH, C.FKICK_CONE_COS, C.FKICK_DAMAGE * _hot_mult(), C.FKICK_KNOCK, C.FKICK_STUN)
	events.append({"type": "fkick_hit", "pos": c, "dir": d, "hits": hits})


# ---- ultimates: Dragon Rush (tap X) and Lightning (hold X)

func _start_rush(look: Vector3) -> void:
	ult = 0.0
	rush_t = C.RUSH_TIME
	rush_dir = look
	heat = 0.0
	fcharging = false
	fire_down = false
	_release_channels()
	on_ground = false
	if vel.y < 3.0:
		vel.y = 3.0
	events.append({"type": "rush_start", "pos": pos})


func _update_rush(dt: float, wish: Vector3) -> void:
	rush_t = maxf(0.0, rush_t - dt)
	ult_lock = 0.5
	water_depth = world.terrain.water_depth_at(pos.x, pos.z)
	if water_depth >= C.SOAK_DEPTH and pos.y <= world.terrain.surface_at(pos.x, pos.z) + 0.3:
		rush_t = 0.0                                      # the flame hits the water and goes out
		soak_t = C.SOAK_TIME
	heat = 0.0
	var want := look_dir()
	var gh := height_above_ground()
	if gh < C.RUSH_MIN_CLEARANCE and want.y < 0.0:
		want.y = 0.0                                      # skims the ground rather than ploughing into it
		want = want.normalized() if want.length() > 0.01 else rush_dir
	var ang := rush_dir.angle_to(want)
	if ang > 0.0001:
		rush_dir = rush_dir.slerp(want, minf(1.0, C.RUSH_TURN * dt / ang)) if ang < 3.1 else want
	vel = rush_dir * C.RUSH_SPEED
	on_ground = false
	air_time = 0.0
	_integrate(dt)
	if not events.is_empty() and events.back()["type"] == "land":
		events.pop_back()                                 # skimming the ground is not a landing
	on_ground = false
	world.apply_rush(pos + Vector3(0.0, 1.0, 0.0), rush_dir, dt)
	_rush_fx_acc += dt
	if rush_t <= 0.0:
		var k := minf(1.0, 12.0 / maxf(vel.length(), 0.001))
		vel *= k
		events.append({"type": "rush_end", "pos": pos})


func _start_lightning() -> void:
	if not ult_ready() or soak_t > 0.0 or swimming:
		if soak_t > 0.0 or swimming:
			events.append({"type": "too_wet"})
		return
	light_t = 0.0
	_release_channels()
	light_t = 0.0
	events.append({"type": "lightning_charge", "pos": pos})


func _fire_lightning(look: Vector3, origin: Vector3) -> void:
	var frac := lerpf(C.LIGHT_MIN_FRAC, 1.0, clampf((light_t - C.LIGHT_MIN_CHARGE) / (C.LIGHT_CHARGE - C.LIGHT_MIN_CHARGE), 0.0, 1.0))
	light_t = -1.0
	ult = 0.0
	ult_lock = 0.6
	var res: Dictionary = world.lightning(origin + Vector3(0.0, -0.15, 0.0), look, C.LIGHT_RANGE, C.LIGHT_DAMAGE * frac, frac >= 0.999)
	events.append({"type": "lightning_fire", "origin": origin, "dir": look, "frac": frac, "hit": res["hit"], "blocked": res["blocked"]})



# ------------------------------------------------------------------ mantle

func _start_mantle(ledge: Dictionary, fwd: Vector3) -> void:
	var dy: float = float(ledge["y"]) - pos.y
	mantle = {
		"t": 0.0,
		"dur": C.MANTLE_BASE + dy * C.MANTLE_PER_METER,
		"s": pos,
		"target": Vector3(float(ledge["x"]), float(ledge["y"]), float(ledge["z"])),
		"fx": fwd.x,
		"fz": fwd.z,
		"exit": minf(maxf(speed() * 0.7, C.MANTLE_EXIT_SPEED), C.SPRINT_SPEED + 1.0),
	}
	_release_channels()
	crouching = false
	gliding = false
	height = C.STAND_HEIGHT
	vel = Vector3.ZERO
	on_ground = false
	events.append({"type": "mantle"})


func _update_mantle(dt: float) -> void:
	mantle["t"] += dt
	var u := minf(1.0, float(mantle["t"]) / float(mantle["dur"]))
	var yu := C.ss(0.0, 0.7, u)
	var hu := C.ss(0.3, 1.0, u)
	var s: Vector3 = mantle["s"]
	var t: Vector3 = mantle["target"]
	pos.x = lerpf(s.x, t.x, hu)
	pos.y = lerpf(s.y, t.y, yu)
	pos.z = lerpf(s.z, t.z, hu)
	if u >= 1.0:
		var ex: float = mantle["exit"]
		vel = Vector3(float(mantle["fx"]) * ex, 0.0, float(mantle["fz"]) * ex)
		mantle = {}
		var g: Dictionary = world.ground_at(pos.x, pos.z, pos.y)
		ground_normal = Vector3(g["nx"], g["ny"], g["nz"])
		on_ground = true
		ground_time = 0.0
		mantle_cd = C.MANTLE_COOLDOWN
		events.append({"type": "mantle_end"})


# ------------------------------------------------------------------ integration

func _integrate(dt: float) -> void:
	var was_ground := on_ground
	# Ground that rose under us since last tick (earthbending): carried up gently, or thrown if it burst up fast.
	var h0: float = world.height_at(pos.x, pos.z)
	if h0 > pos.y + 0.02 and (was_ground or vel.y <= 0.0):
		var dy := h0 - pos.y
		pos.y = h0
		if dy / dt > C.LIFT_LAUNCH_RATE and not world.terrain.ice_at(pos.x, pos.z):      # freezing water lifts you gently
			vel.y = maxf(vel.y, minf(dy / dt, C.LIFT_LAUNCH_MAX))
			on_ground = false
			was_ground = false
			coyote = 0.0
			air_time = 0.0
			if sliding:
				_end_slide()
			events.append({"type": "launched"})
	var old := pos
	pos += vel * dt
	world.resolve_horizontal(self, old)
	world.clamp_bounds(self)
	var g: Dictionary = world.ground_at(pos.x, pos.z, pos.y)
	var gy: float = g["y"]
	var gn := Vector3(g["nx"], g["ny"], g["nz"])
	if was_ground:
		var rise := gy - pos.y
		var tol := C.LAUNCH_TOLERANCE if speed() > C.STICK_SPEED else C.STEP_HEIGHT
		if rise >= 0.0 or -rise <= tol:
			pos.y = gy
			ground_normal = gn
		else:
			on_ground = false
			coyote = C.COYOTE_TIME * (C.AIR_COYOTE_MULT if element == "air" else 1.0)
	elif pos.y <= gy:
		var impact := maxf(0.0, -vel.y)
		pos.y = gy
		on_ground = true
		ground_time = 0.0
		ground_normal = gn
		dash_air_used = false
		events.append({"type": "land", "impact": impact})
