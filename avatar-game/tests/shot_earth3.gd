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
	place(Vector3(0, 0, 4), 0.0, 0.0)
	sim.element = "earth"
	# charge
	var ci := ip()
	ci.fire_pressed = true
	ci.fire_held = true
	sim.step(TICK, ci)
	await run(30, 6, func(f, t):
		var i := ip()
		i.fire_held = true
		return i)
	await save("e3_charge")
	sim.fire_down = false
	sim.charging = false
	# boulder pull
	place(Vector3(0, 0, 4), 0.0, -0.2)
	var ri := ip()
	ri.slice_pressed = true
	sim.step(TICK, ri)
	await run(3, 6, func(f, t): return ip())
	await save("e3_pull")
	await run(2, 6, func(f, t): return ip())
	await save("e3_pull2")
	# skate
	place(Vector3(0, 0, 4), 0.0, -0.25)
	var si := ip()
	si.scooter_pressed = true
	sim.step(TICK, si)
	await run(40, 6, func(f, t): return _fwd())
	sim.pitch = -0.75
	await save("e3_skate_a")
	await run(5, 6, func(f, t): return _fwd())
	await save("e3_skate_b")
	# book
	place(Vector3(0, 0, 4), 0.0, -0.1)
	sim.ult = 100.0
	var ui := ip()
	ui.ult_pressed = true
	sim.step(TICK, ui)
	await run(4, 6, func(f, t): return ip())
	await save("e3_book_a")
	await run(5, 6, func(f, t): return ip())
	await save("e3_book_b")
	await run(4, 6, func(f, t): return ip())
	await save("e3_book_c")
	await run(8, 6, func(f, t): return ip())
	await save("e3_book_d")
	quit(0)


func _fwd() -> SimScript.InputState:
	var i := ip()
	i.move_y = 1.0
	return i


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
