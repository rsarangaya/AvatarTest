extends SceneTree
## How long one 120 Hz simulation tick takes (headless): the game runs two of these per frame at 60 fps.
##   godot --headless --path . -s res://tests/sim_cost.gd

const WorldScript = preload("res://scripts/world.gd")
const SimScript = preload("res://scripts/player_sim.gd")
const TICK := 1.0 / 120.0


func _init() -> void:
	for mode in ["bots", "duel"]:
		var w := WorldScript.new(1337)
		var p := SimScript.new(w)
		var a := SimScript.InputState.new()
		a.element_pressed = "water"
		p.step(TICK, a)
		if mode == "duel":
			w.set_bot_mode("duel", "water")
		else:
			w.set_bot_mode("benders", "water")
		for i in range(240):
			p.step(TICK, SimScript.InputState.new())
		var t0 := Time.get_ticks_usec()
		var n := 1200
		for i in range(n):
			p.step(TICK, SimScript.InputState.new())
		var dt := float(Time.get_ticks_usec() - t0) / 1000.0
		print("%-5s %d bots: %.3f ms per tick (%.2f ms per 60 fps frame)" % [mode, w.bots.size(), dt / n, dt / n * 2.0])
	quit(0)
