extends SceneTree
## How long one 120 Hz simulation tick takes (headless): the game runs two of these per frame at 60 fps.
##   godot --headless --path . -s res://tests/sim_cost.gd
## Water bots as before, plus a firebender player holding the big fireball / spamming moves among fire bots.

const WorldScript = preload("res://scripts/world.gd")
const SimScript = preload("res://scripts/player_sim.gd")
const TICK := 1.0 / 120.0


func _init() -> void:
	for nation in ["water", "fire"]:
		for mode in ["bots", "duel"]:
			var w := WorldScript.new(1337)
			var p := SimScript.new(w)
			var a := SimScript.InputState.new()
			a.element_pressed = nation
			p.step(TICK, a)
			w.bot_nation = nation
			w.duel_nation = nation
			if mode == "duel":
				w.set_bot_mode("duel", nation)
			else:
				w.set_bot_mode("benders", nation)
			p.debug_god = true
			p.debug_nocd = nation == "fire"
			for i in range(240):
				p.step(TICK, SimScript.InputState.new())
			var t0 := Time.get_ticks_usec()
			var n := 1200
			for i in range(n):
				var inp := SimScript.InputState.new()
				if nation == "fire":                       # the firebender keeps fireballs going and throws moves around
					inp.fire_held = true
					if i % 120 == 0:
						inp.fire_pressed = true
					if i % 90 == 0:
						inp.barrage_pressed = true
					if i % 200 == 0:
						inp.suction_held = true
					if i % 150 == 0:
						inp.slice_pressed = true
				p.step(TICK, inp)
				w.events.clear()
				p.events.clear()
			var dt := float(Time.get_ticks_usec() - t0) / 1000.0
			print("%-5s %-5s %d bots: %.3f ms per tick (%.2f ms per 60 fps frame)" % [nation, mode, w.bots.size(), dt / n, dt / n * 2.0])
	quit(0)
