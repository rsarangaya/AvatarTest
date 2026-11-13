extends SceneTree
## Frame-time probe for the fire nation (needs a window; vsync off):
##   godot --path . --resolution 1600x900 -s res://tests/perf_fire.gd
## Optional env: PERF_Q=0|1|2

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
	Session.player_nation = "fire"
	Session.mode = "bots"
	Session.bot_kind = "benders"
	Session.bot_nation = "fire"
	var q := OS.get_environment("PERF_Q")
	Settings.quality = int(q) if q != "" else Settings.quality
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	sim = main.sim
	world = main.world
	sim.debug_god = true
	sim.debug_nocd = true
	main._capture(true)
	main.overlay.visible = false
	await _measure("fire: standing still", 3.0, func(): pass)
	await _measure("big fireball held", 4.0, func():
		main.inp.fire_held = true
		sim.yaw += 0.02)
	main.inp.fire_held = false
	var n := [0]
	await _measure("spamming every move", 5.0, func():
		n[0] += 1
		sim.yaw += 0.02
		main.inp.fire_held = n[0] % 90 < 45
		if n[0] % 12 == 0:
			main.inp.fire_pressed = true
		if n[0] % 20 == 0:
			main.inp.slice_pressed = true
		if n[0] % 15 == 0:
			main.inp.barrage_pressed = true
		if n[0] % 30 == 0:
			main.inp.freeze_pressed = true
		main.inp.suction_held = n[0] % 60 < 5)
	main.inp.fire_held = false
	main.inp.suction_held = false
	sim.respawn()
	await _measure("dragon rush", 4.0, func():
		sim.ult = C.ULT_MAX
		if sim.rush_t <= 0.0:
			sim.rush_t = 8.0
			sim.rush_dir = sim.look_dir()
		sim.yaw += 0.015)
	sim.rush_t = 0.0
	await _measure("lightning charge + bolts", 4.0, func():
		sim.light_t = 1.2
		n[0] += 1
		if n[0] % 40 == 0:
			world.events.append({"type": "lightning", "from": sim.pos + Vector3(0, 2, 0), "to": sim.pos + Vector3(0, 2, -30), "hit": true, "blocked": false}))
	sim.light_t = -1.0
	print("bots alive: ", world.bots.size(), "  projectiles: ", world.projectiles.size(), "  fx effects: ", main.fx._effects.size())
	quit(0)


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
