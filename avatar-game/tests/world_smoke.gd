extends SceneTree
## Compile/run check for world.gd + terrain.gd: build the level, run bots for 20 simulated seconds.
const WorldScript = preload("res://scripts/world.gd")

func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var w := WorldScript.new(1337)
	print("world built in %d ms, bots=%d summit y=%.1f" % [Time.get_ticks_msec() - t0, w.bots.size(), w.summit.y])
	var mx := -INF
	var mn := INF
	for i in range(w.terrain.h.size()):
		mx = maxf(mx, w.terrain.h[i])
		mn = minf(mn, w.terrain.h[i])
	print("height range %.1f .. %.1f" % [mn, mx])
	for i in range(120 * 20):
		w.update_combat(1.0 / 120.0, null)
	var moved := 0
	var finite_ok := true
	for b in w.bots:
		if b.pos.distance_to(b.home) > 0.5:
			moved += 1
		if not (is_finite(b.pos.x) and is_finite(b.pos.y) and is_finite(b.pos.z)):
			finite_ok = false
	print("bots that wandered=%d finite=%s" % [moved, str(finite_ok)])
	quit(0 if finite_ok else 1)
