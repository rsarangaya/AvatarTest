extends RefCounted
## Small helpers so the menus, the pause menu and the options screen all look the same.

const BG := Color(0.04, 0.07, 0.12, 0.92)
const PANEL := Color(0.09, 0.13, 0.20, 0.96)
const BUTTON := Color(0.13, 0.19, 0.29, 1.0)
const BUTTON_HOVER := Color(0.20, 0.30, 0.44, 1.0)
const BUTTON_ON := Color(0.28, 0.46, 0.68, 1.0)
const TEXT := Color(0.92, 0.96, 1.0)
const DIM := Color(0.62, 0.70, 0.80)

const NATION_COLORS := {
	"air": Color(0.78, 0.93, 1.0),
	"earth": Color(0.9, 0.68, 0.38),
	"water": Color(0.55, 0.82, 1.0),
	"fire": Color(1.0, 0.55, 0.25),
}


static func _box(c: Color, radius := 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	return sb


static func make_theme() -> Theme:
	var t := Theme.new()
	t.set_font_size("font_size", "Button", 20)
	t.set_font_size("font_size", "Label", 16)
	t.set_font_size("normal_font_size", "RichTextLabel", 16)
	t.set_font_size("bold_font_size", "RichTextLabel", 17)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.56, 0.64))
	t.set_color("font_color", "Label", TEXT)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_stylebox("normal", "Button", _box(BUTTON))
	t.set_stylebox("hover", "Button", _box(BUTTON_HOVER))
	t.set_stylebox("pressed", "Button", _box(BUTTON_ON))
	t.set_stylebox("disabled", "Button", _box(Color(0.10, 0.13, 0.18, 0.8)))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_stylebox("panel", "PanelContainer", _box(PANEL, 12))
	return t


static func button(text: String, min_size := Vector2(260.0, 52.0)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	return b


static func label(text: String, size := 16, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


# A button with a toggled look (the chosen nation, the active mode).
static func set_selected(b: Button, on: bool, tint := Color.WHITE) -> void:
	b.add_theme_stylebox_override("normal", _box(BUTTON_ON if on else BUTTON))
	b.add_theme_color_override("font_color", tint if on else TEXT)
