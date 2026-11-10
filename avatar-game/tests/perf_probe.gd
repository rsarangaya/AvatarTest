extends SceneTree
## Frame-time probe. Needs a window (vsync is switched off to see what the game could do):
##   godot --path . --resolution 1600x900 -s res://tests/perf_probe.gd
## Optional env: PERF_NATION=water|air|earth (default water), PERF_MODE=bots|duel (default bots)

const Session = preload("res://scripts/session.gd")
const Settings = preload("res://scripts/settings.gd")
const C = preload("res://scripts/config.gd")

var main
var sim
var world


func _initialize() -> void:
	Settings.persist = false
	Settings.ensure_loaded()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var nation := OS.get_environment("PERF_NATION")
	Session.player_nation = nation if nation != "" else "water"
	var mode := OS.get_environment("PERF_MODE")
	Session.mode = mode if mode != "" else "bots"
	Session.bot_kind = "benders"
	Session.bot_nation = "water"
	var q := OS.get_environment("PERF_Q")
	Settings.quality = int(q) if q != "" else Settings.quality
	print("QUALITY ", Settings.QUALITY_NAMES[Settings.quality])
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	sim = main.sim
	world = main.world
	main._capture(true)
	main.overlay.visible = false
	_census(main, "")
	await _measure("spawn, standing still", 4.0, func(): pass)
	await _measure("look around (turning)", 4.0, func(): sim.yaw += 0.03)
	sim.pos = Vector3(0, world.height_at(0, 4) + 120.0, 4)
	sim.on_ground = false
	sim.pitch = -0.5
	await _measure("high up, looking down", 3.0, func(): sim.vel = Vector3.ZERO)
	sim.respawn()
	var n := 0
	await _measure("ultimate running (octopus)", 4.0, func():
		sim.octo_t = 8.0
		sim.yaw += 0.02)
	sim.octo_t = 0.0
	await _measure("walking forward, spending chi", 4.0, func():
		sim.yaw += 0.01
		main.inp.move_y = 1.0)
	print("bots alive: ", world.bots.size(), "  projectiles: ", world.projectiles.size())
	quit(0)


func _census(n: Node, path: String) -> void:
	var meshes := 0
	var visible := 0
	var stack: Array = [n]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		if c is MeshInstance3D:
			meshes += 1
			if (c as MeshInstance3D).is_visible_in_tree():
				visible += 1
		stack.append_array(c.get_children())
	for ch in n.get_children():
		var count := 0
		var st: Array = [ch]
		while not st.is_empty():
			var c2: Node = st.pop_back()
			if c2 is MeshInstance3D:
				count += 1
			st.append_array(c2.get_children())
		if count > 20:
			print("CENSUS %s%s (%s): %d meshes" % [path, ch.name, ch.get_class(), count])
	print("CENSUS total meshes ", meshes, " visible-in-tree ", visible)


func _measure(label: String, secs: float, step: Callable) -> void:
	for i in range(20):
		step.call()
		await process_frame
	var t_end := Time.get_ticks_msec() + int(secs * 1000.0)
	var frames := 0
	var worst := 0.0
	var last := Time.get_ticks_usec()
	var proc := 0.0
	var phys := 0.0
	var calls := 0.0
	var prims := 0.0
	var objs := 0.0
	while Time.get_ticks_msec() < t_end:
		step.call()
		await process_frame
		var now := Time.get_ticks_usec()
		worst = maxf(worst, float(now - last) / 1000.0)
		last = now
		frames += 1
		proc += Performance.get_monitor(Performance.TIME_PROCESS)
		phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		objs += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	var f := float(maxi(frames, 1))
	print("%-30s %6.1f fps  (%.2f ms/frame, worst %.1f ms)  script %.2f ms  physics %.2f ms  draws %d  tris %dk  objects %d" % [
			label, frames / secs, 1000.0 * secs / f, worst, 1000.0 * proc / f, 1000.0 * phys / f, calls / f, prims / f / 1000.0, objs / f])
