extends SceneTree
const WorldScript = preload("res://scripts/world.gd")
const SimScript = preload("res://scripts/player_sim.gd")
const TICK := 1.0 / 120.0

func _init() -> void:
	for seed_v in [1337, 7, 42]:
		for nat in ["air", "earth"]:
			var w := WorldScript.new(seed_v)
			var p := SimScript.new(w)
			w.duel_nation = nat
			w.set_bot_mode("duel", "earth" if nat == "air" else "air", p.pos, p.yaw)
			p.respawn()
			for i in range(30):
				p.step(TICK, SimScript.InputState.new())
			var b = w.bots[0]
			var arrived := -1.0
			var stuck := 0.0
			var lastp: Vector3 = b.pos
			var chk := 0.0
			var hops := 0
			for k in range(120 * 150):
				p.step(TICK, SimScript.InputState.new())
				for ev in w.events:
					if ev["type"] == "bot_cast" and (ev["kind"] == "gust" or ev["kind"] == "stomp"):
						hops += 1
				w.events.clear()
				p.hp = 100.0
				var d := Vector2(p.pos.x - b.pos.x, p.pos.z - b.pos.z).length()
				if arrived < 0.0 and d < 24.0:
					arrived = float(k) * TICK
				chk += TICK
				if chk >= 2.0:
					chk = 0.0
					if Vector2(b.pos.x - lastp.x, b.pos.z - lastp.z).length() < 0.5 and d > 26.0:
						stuck += 2.0
					lastp = b.pos
			var dend := Vector2(p.pos.x - b.pos.x, p.pos.z - b.pos.z).length()
			print("NAV seed ", seed_v, " ", nat, ": reached range at ", snappedf(arrived, 0.1), " s, stuck-time ", stuck, " s, final dist ", snappedf(dend, 0.1), " hops ", hops)
	quit()
