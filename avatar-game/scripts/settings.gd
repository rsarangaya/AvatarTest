extends RefCounted
## Settings that survive restarts: key bindings, mouse sensitivity and field of view.
## Also holds the hidden debug switch (not saved: it resets every launch).
## Everything is static, so any script can use it: `const Settings = preload("res://scripts/settings.gd")`.

const SAVE_PATH := "user://avatar_settings.cfg"

# The rebindable keys. Mouse buttons (fire, secondary) and the mouse wheel (jump) are fixed.
const ACTIONS := [
	{"id": "move_forward", "label": "Move forward", "key": KEY_W, "group": "Movement"},
	{"id": "move_back", "label": "Move back", "key": KEY_S, "group": "Movement"},
	{"id": "move_left", "label": "Move left", "key": KEY_A, "group": "Movement"},
	{"id": "move_right", "label": "Move right", "key": KEY_D, "group": "Movement"},
	{"id": "sprint", "label": "Sprint", "key": KEY_SHIFT, "group": "Movement"},
	{"id": "crouch", "label": "Crouch / slide", "key": KEY_C, "group": "Movement"},
	{"id": "jump", "label": "Jump / gust / glide / elevator", "key": KEY_SPACE, "group": "Movement"},
	{"id": "ability_q", "label": "Q move: scooter, skate, octopus grab", "key": KEY_Q, "group": "Bending"},
	{"id": "ability_e", "label": "E move: shield, wall, ice wall, slam (hold)", "key": KEY_E, "group": "Bending"},
	{"id": "ability_f", "label": "F move: suction, pillar, gather (hold)", "key": KEY_F, "group": "Bending"},
	{"id": "ability_z", "label": "Z move: stone barrage, ice shards", "key": KEY_Z, "group": "Bending"},
	{"id": "ability_g", "label": "G move: grab / plant earth wall", "key": KEY_G, "group": "Bending"},
	{"id": "ability_v", "label": "V move: earth armor", "key": KEY_V, "group": "Bending"},
	{"id": "ability_freeze", "label": "T move: freeze / unfreeze water (water), combustion beam (fire)", "key": KEY_T, "group": "Bending"},
	{"id": "ultimate", "label": "Ultimate (tap or hold for water and fire)", "key": KEY_X, "group": "Bending"},
	{"id": "respawn", "label": "Respawn / reset", "key": KEY_R, "group": "Game"},
]

# Only listed in the options screen once debug mode is on. G (earth wall grab) and T (freeze) are taken, so the default is Y.
const DEBUG_ACTIONS := [
	{"id": "debug_ult", "label": "Fill the ultimate meter", "key": KEY_Y, "group": "Debug"},
]

# Keys that can never be bound: they are used by the game itself.
const RESERVED := [KEY_ESCAPE, KEY_F10, KEY_F11]

const KONAMI := [KEY_UP, KEY_UP, KEY_DOWN, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_LEFT, KEY_RIGHT, KEY_B, KEY_A]

const BASE_FOV := 92.0
const BASE_SENS := 0.0022

static var bindings := {}
static var mouse_sens := 1.0            # multiplier on BASE_SENS
static var fov := BASE_FOV
static var quality := 1                 # graphics: 0 low, 1 medium, 2 high (see profile())
static var debug_enabled := false
static var persist := true              # tests turn this off so they never touch the player's saved settings
static var _loaded := false
static var _konami_at := 0


static func _all_actions() -> Array:
	return ACTIONS + DEBUG_ACTIONS


static func _defaults() -> void:
	bindings = {}
	for a in _all_actions():
		bindings[String(a["id"])] = int(a["key"])


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_defaults()
	var cf := ConfigFile.new()
	if not persist or cf.load(SAVE_PATH) != OK:
		return
	for a in _all_actions():
		var id := String(a["id"])
		var code := int(cf.get_value("keys", id, bindings[id]))
		if not RESERVED.has(code) and code > 0:
			bindings[id] = code
	resolve_conflicts()
	mouse_sens = clampf(float(cf.get_value("mouse", "sensitivity", 1.0)), 0.2, 3.0)
	fov = clampf(float(cf.get_value("view", "fov", BASE_FOV)), 70.0, 110.0)
	quality = clampi(int(cf.get_value("view", "quality", 1)), 0, 2)


# Two actions must never share a key (an old saved file can clash with an action added later). The later action goes
# back to its default key, or is unbound when that one is taken as well.
static func resolve_conflicts() -> void:
	var used := {}
	for a in _all_actions():
		var id := String(a["id"])
		var code := int(bindings[id])
		if used.has(code):
			var d := int(a["key"])
			code = d if not used.has(d) else KEY_NONE
			bindings[id] = code
		if code != KEY_NONE:
			used[code] = id


static func save() -> void:
	ensure_loaded()
	if not persist:
		return
	var cf := ConfigFile.new()
	for id in bindings.keys():
		cf.set_value("keys", String(id), int(bindings[id]))
	cf.set_value("mouse", "sensitivity", mouse_sens)
	cf.set_value("view", "fov", fov)
	cf.set_value("view", "quality", quality)
	cf.save(SAVE_PATH)


static func reset_defaults() -> void:
	ensure_loaded()
	_defaults()
	mouse_sens = 1.0
	fov = BASE_FOV
	quality = 1
	save()


# ------------------------------------------------------------------ graphics

const QUALITY_NAMES := ["Low", "Medium", "High"]

# What each graphics level costs and shows. msaa: 0 off, 2 = 2x. shadow_dist 0 = no shadows. terrain_range / bot_range
# are view distances in metres (0 = unlimited): beyond them the ground and the bots are not drawn at all (fog hides it).
static func profile() -> Dictionary:
	match quality:
		0:
			return {"msaa": 0, "shadow_dist": 0.0, "shadow_splits": 1, "terrain_range": 230.0, "bot_range": 85.0, "far": 600.0}
		2:
			return {"msaa": 2, "shadow_dist": 130.0, "shadow_splits": 4, "terrain_range": 0.0, "bot_range": 0.0, "far": 2200.0}
	return {"msaa": 0, "shadow_dist": 75.0, "shadow_splits": 1, "terrain_range": 340.0, "bot_range": 140.0, "far": 900.0}


# ------------------------------------------------------------------ bindings

static func key(id: String) -> int:
	ensure_loaded()
	return int(bindings.get(id, KEY_NONE))


static func down(id: String) -> bool:
	return Input.is_physical_key_pressed(key(id) as Key)


static func label(id: String) -> String:
	for a in _all_actions():
		if String(a["id"]) == id:
			return String(a["label"])
	return id


# What the key is called on screen ("W", "Shift", "Space"). Uses the keyboard's own label for that physical key.
static func key_name(id: String) -> String:
	return code_name(key(id))


static func code_name(code: int) -> String:
	if code <= 0:
		return "(none)"
	var lab: int = DisplayServer.keyboard_get_label_from_physical(code as Key)
	var s := OS.get_keycode_string((lab if lab > 0 else code) as Key)
	return s if s != "" else "Key %d" % code


# Bind a key. If another action already uses it the two swap keys. Returns the label of the swapped action ("" if none),
# or "RESERVED" when the key cannot be used.
static func rebind(id: String, code: int) -> String:
	ensure_loaded()
	if RESERVED.has(code):
		return "RESERVED"
	var swapped := ""
	var old: int = key(id)
	for other in bindings.keys():
		if String(other) != id and int(bindings[other]) == code:
			bindings[other] = old
			swapped = label(String(other))
	bindings[id] = code
	save()
	return swapped


# ------------------------------------------------------------------ the hidden debug code

# Feed every key press here. Up Up Down Down Left Right Left Right B A turns debug mode on or off.
# Returns true on the press that completes the code.
static func feed_key(code: int) -> bool:
	if code == KONAMI[_konami_at]:
		_konami_at += 1
		if _konami_at >= KONAMI.size():
			_konami_at = 0
			debug_enabled = not debug_enabled
			return true
	else:
		_konami_at = 1 if code == KONAMI[0] else 0
	return false
