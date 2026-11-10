extends Control
## One ability indicator for the HUD: a dark sweep that shrinks as the cooldown runs down (seconds shown above 1 s),
## a brief bright flash when it is ready again, a dimmed look when it cannot be used, a gold border while it is on.
## Cheap by design: one _draw, and it only redraws when something visible changed.

const Settings = preload("res://scripts/settings.gd")
const SIZE := Vector2(48.0, 48.0)
const FLASH_TIME := 0.35
const FLASH_MIN_CD := 0.5              # shorter cooldowns (punches) would just flicker

var title := ""
var key_text := ""
var key_id := ""                       # a Settings action id; the label follows rebinds (empty = fixed text)
var accent := Color(0.8, 0.9, 1.0)

var _sweep_px := 0                     # height of the dark sweep in pixels
var _secs := 0                         # whole seconds shown (0 = none)
var _usable := true
var _active := false
var _badge := -1
var _flash := 0.0
var _flash_q := 0
var _prev_cd := 0.0
var _secs_text := ""
var _badge_text := ""
var _font: Font = ThemeDB.fallback_font


func _init() -> void:
	custom_minimum_size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE


# `what` is a Settings action id (then the label tracks the binding) or a fixed label such as "LMB".
func set_key(what: String) -> void:
	key_id = what if Settings.bindings.has(what) else ""
	key_text = Settings.key_name(key_id) if key_id != "" else what
	queue_redraw()


# Call after bindings may have changed.
func refresh_keys() -> void:
	if key_id == "":
		return
	var t := Settings.key_name(key_id)
	if t != key_text:
		key_text = t
		queue_redraw()


# cd = seconds left (0 = ready), cd_max = full cooldown, badge >= 0 draws a count (pillar charges).
func update_slot(dt: float, cd: float, cd_max: float, usable: bool, active: bool, badge: int = -1, show_secs: bool = true) -> void:
	var dirty := false
	if _prev_cd > 0.0 and cd <= 0.0 and cd_max >= FLASH_MIN_CD:
		_flash = FLASH_TIME
	_prev_cd = cd
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - dt)
		var fq := int(ceil(_flash * 10.0))
		if fq != _flash_q:
			_flash_q = fq
			dirty = true
	var px := 0
	var secs := 0
	if cd > 0.0 and cd_max > 0.0:
		px = int(clampf(cd / cd_max, 0.0, 1.0) * (SIZE.y - 2.0) + 0.99)
		if show_secs and cd > 1.0:
			secs = int(ceil(cd))
	if px != _sweep_px:
		_sweep_px = px
		dirty = true
	if secs != _secs:
		_secs = secs
		_secs_text = str(secs) if secs > 0 else ""
		dirty = true
	if usable != _usable:
		_usable = usable
		dirty = true
	if active != _active:
		_active = active
		dirty = true
	if badge != _badge:
		_badge = badge
		_badge_text = "x%d" % badge if badge >= 0 else ""
		dirty = true
	if dirty:
		queue_redraw()


func _draw() -> void:
	var w := SIZE.x
	var h := SIZE.y
	draw_rect(Rect2(0.0, 0.0, w, h), Color(0.0, 0.0, 0.0, 0.45))
	var inner := Rect2(1.0, 1.0, w - 2.0, h - 2.0)
	if _usable:
		draw_rect(inner, Color(accent.r, accent.g, accent.b, 0.28))
	if _sweep_px > 0:
		draw_rect(Rect2(1.0, 1.0, w - 2.0, float(_sweep_px)), Color(0.0, 0.0, 0.0, 0.7))
	elif not _usable:
		draw_rect(inner, Color(0.0, 0.0, 0.0, 0.55))
	if _flash > 0.0:
		draw_rect(inner, Color(1.0, 1.0, 1.0, 0.7 * _flash / FLASH_TIME))
	var border := Color(1.0, 0.85, 0.35, 0.95) if _active else (Color(1.0, 1.0, 1.0, 0.25 + 0.6 * _flash / FLASH_TIME) if _flash > 0.0 else Color(1.0, 1.0, 1.0, 0.25))
	draw_rect(Rect2(0.5, 0.5, w - 1.0, h - 1.0), border, false, 1.5 if _active else 1.0)
	var dim := 1.0 if (_usable and _sweep_px == 0) else 0.55
	draw_string(_font, Vector2(0.0, 15.0), title, HORIZONTAL_ALIGNMENT_CENTER, w, 10, Color(1, 1, 1, dim))
	if _secs > 0:
		draw_string(_font, Vector2(0.0, 33.0), _secs_text, HORIZONTAL_ALIGNMENT_CENTER, w, 18, Color(1, 1, 1, 0.95))
	elif _badge >= 0:
		draw_string(_font, Vector2(0.0, 33.0), _badge_text, HORIZONTAL_ALIGNMENT_CENTER, w, 16, Color(1.0, 0.95, 0.7, dim))
	draw_string(_font, Vector2(0.0, h - 4.0), key_text, HORIZONTAL_ALIGNMENT_CENTER, w, 10, Color(1, 1, 1, 0.6 * dim))
