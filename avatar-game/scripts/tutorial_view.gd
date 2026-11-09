extends PanelContainer
## A scrolling panel with one nation's move list / tutorial. Call show_nation() to change what it shows.

const Moveset = preload("res://scripts/moveset.gd")

var _text: RichTextLabel
var _nation := ""


func _init() -> void:
	custom_minimum_size = Vector2(520.0, 300.0)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = false
	_text.scroll_active = true
	_text.selection_enabled = false
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_text)


func show_nation(nation: String) -> void:
	_nation = nation
	_text.text = Moveset.rich_text(nation)
	_text.scroll_to_line(0)


# Any other text (a hint before something is picked, a note about a choice).
func show_text(bbcode: String) -> void:
	_nation = ""
	_text.text = bbcode


# Re-read the key bindings (used when the options screen changed them).
func refresh() -> void:
	if _nation != "":
		var keep := _text.get_v_scroll_bar().value
		_text.text = Moveset.rich_text(_nation)
		_text.get_v_scroll_bar().value = keep
