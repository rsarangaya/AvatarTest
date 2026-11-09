extends SceneTree
## Stages each airbending move in the real scene and saves screenshots (run under xvfb):
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --path . -s res://tests/shot.gd

const OUT := "/home/claude/shots/"
const TICK := 1.0 / 120.0
const SimScript = preload("res://scripts/player_sim.gd")

var main
var sim
var world


func ip() -> SimScript.InputState:
	return SimScript.InputState.new()


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.overlay.visible = false
	sim = main.sim
	world = main.world

	world.reset_bots()
	var e := ip()
	e.element_pressed = "earth"
	sim.step(TICK, e)
	# --- armor
	place(Vector3(0, 0, 4), 0.0, 0.0)
	sim.element = "earth"
	var av := ip()
	av.armor_pressed = true
	sim.step(TICK, av)
	await run(10, 6, func(f, t): return ip())
	sim.pitch = -0.6
	await frames(3)
	await save("n_armor")
	sim.armor_on = false
	# --- skate
	place(Vector3(0, 0, 4), 0.0, -0.15)
	sim.element = "earth"
	var qs := ip()
	qs.scooter_pressed = true
	sim.step(TICK, qs)
	await run(14, 6, func(f, t):
		var i := ip()
		i.move_y = 1.0
		return i)
	print("skating ", sim.skating, " speed ", sim.speed())
	await save("n_skate")
	sim.skating = false
	# --- elevator up a cliff
	world.terrain.raise_mound(0.0, -14.0, 4.0, 1.0, 12.0)
	place(Vector3(0, 0, -6), 0.0, 0.2)
	sim.element = "earth"
	await run(3, 4, func(f, t): return ip())
	await run(12, 6, func(f, t):
		var i := ip()
		i.move_y = 1.0
		i.jump_held = true
		return i)
	print("elevating ", sim.elevating, " y ", sim.pos.y)
	await save("n_elevator")
	# --- wall + grab
	world.terrain.heal_enabled = false
	place(Vector3(0, 0, 4), 0.0, 0.05)
	sim.element = "earth"
	sim.chi = 100.0
	var ew := ip()
	ew.shield_held = true
	sim.step(TICK, ew)
	sim.step(TICK, ip())
	await run(10, 6, func(f, t): return ip())
	await save("n_wall")
	var gg := ip()
	gg.grab_pressed = true
	sim.step(TICK, gg)
	await run(8, 6, func(f, t): return ip())
	print("held ", world.held.size())
	await save("n_held_slab")
	# --- clap
	world.reset_bots()
	world.held = {}
	for k in range(3):
		var b = world.bots[k]
		b.pos = Vector3(-2.0 + 2.0 * k, world.height_at(-2.0 + 2.0 * k, -18.0), -18.0)
		b.home = b.pos
	place(Vector3(0, 0, 4), 0.0, 0.0)
	sim.element = "earth"
	sim.ult = 100.0
	var cx := ip()
	cx.ult_pressed = true
	sim.step(TICK, cx)
	await run(5, 8, func(f, t): return ip())
	await save("n_clap_open")
	await run(8, 8, func(f, t): return ip())
	await save("n_clap_slam")
	# --- earthquake dive
	world.reset_bots()
	place(Vector3(0, 0, 4), 0.0, -0.3)
	sim.element = "earth"
	sim.pos.y += 14.0
	sim.on_ground = false
	sim.ult = 100.0
	main.prev_pos = sim.pos
	await run(2, 2, func(f, t): return ip())
	var qx := ip()
	qx.ult_pressed = true
	sim.step(TICK, qx)
	await run(4, 8, func(f, t): return ip())
	await save("n_quake_dive")
	var guard := 0
	while not sim.slam.is_empty() and guard < 600:
		sim.step(TICK, ip())
		guard += 1
	await run(4, 8, func(f, t): return ip())
	await save("n_quake_land")
	quit(0)


func place(at: Vector3, yaw: float, pitch: float) -> void:
	sim.respawn()
	sim.pos = Vector3(at.x, world.height_at(at.x, at.z) + 0.05, at.z)
	sim.yaw = yaw
	sim.pitch = pitch
	sim.on_ground = true
	sim.chi = 100.0
	main.prev_pos = sim.pos


func frames(n: int) -> void:
	for i in range(n):
		main.prev_pos = sim.pos
		await process_frame


func run(n_frames: int, ticks: int, maker: Callable) -> void:
	for f in range(n_frames):
		for t in range(ticks):
			sim.step(TICK, maker.call(f, t))
		main.prev_pos = sim.pos
		await process_frame


func save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var err := img.save_png(OUT + name + ".png")
	print("saved ", name, " err=", err)
