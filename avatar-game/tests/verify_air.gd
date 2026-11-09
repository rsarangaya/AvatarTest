extends SceneTree
const WorldScript = preload("res://scripts/world.gd")
const SimScript = preload("res://scripts/player_sim.gd")
const TICK := 1.0 / 120.0

func _init() -> void:
	for nat in ["air", "earth"]:
		var w := WorldScript.new(1337)
		var p := SimScript.new(w)
		w.duel_nation = nat
		w.set_bot_mode("duel", "earth" if nat == "air" else "air", p.pos, p.yaw)
		p.respawn()
		var b = w.bots[0]
		b.pos = w._base_spawn + Vector3(0, 0, -24)
		b.pos.y = w.height_at(b.pos.x, b.pos.z)
		b.home = b.pos
		p.pos = w._base_spawn + Vector3(0, 0.05, 0)
		var seen := {}
		var evt := {}
		var h_before := _sample(w, b.pos)
		var maxdelta := 0.0
		for k in range(120 * 60):
			p.step(TICK, SimScript.InputState.new())
			for ev in w.events:
				evt[ev["type"]] = int(evt.get(ev["type"], 0)) + 1
				if ev["type"] == "bot_cast":
					seen[ev["kind"]] = int(seen.get(ev["kind"], 0)) + 1
			w.events.clear()
			if p.hp < 40.0:
				p.hp = 100.0
			if k % 120 == 0:
				var hs := _sample(w, b.pos)
				for i in range(hs.size()):
					maxdelta = maxf(maxdelta, absf(hs[i] - h_before[i]))
		print("NATION ", b.nation, " casts ", seen, " max terrain change near bot ", snappedf(maxdelta, 0.01), " m")
		print("   events ", evt)
	quit()

func _sample(w, c: Vector3) -> Array:
	var a := []
	for dx in range(-14, 15, 3):
		for dz in range(-14, 15, 3):
			a.append(w.height_at(c.x + dx, c.z + dz))
	return a
