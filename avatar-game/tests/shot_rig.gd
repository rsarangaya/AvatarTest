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
	sim.element = "air"
	await run(10, 6, func(f, t): return ip())
	await save("r_idle")
	# bots up close
	for k in range(3):
		var b = world.bots[k]
		b.pos = Vector3(-3.0 + 3.0 * k, world.height_at(-3.0 + 3.0 * k, -2.0), -2.0)
		b.home = b.pos
		b.fighter = false
	await run(8, 6, func(f, t): return ip())
	await save("r_bots")
	# melee combo, no chi
	sim.chi = 0.0
	var mi := ip()
	mi.fire_pressed = true
	mi.fire_held = true
	sim.step(TICK, mi)
	await run(3, 6, func(f, t): return ip())
	await save("r_punch")
	await run(12, 6, func(f, t): return ip())
	var m2 := ip()
	m2.fire_pressed = true
	m2.fire_held = true
	sim.step(TICK, m2)
	await run(3, 6, func(f, t): return ip())
	await save("r_punch2")
	# charge pose
	sim.chi = 150.0
	var ci := ip()
	ci.fire_pressed = true
	ci.fire_held = true
	sim.step(TICK, ci)
	await run(30, 6, func(f, t):
		var i := ip()
		i.fire_held = true
		return i)
	await save("r_charge")
	var stack: Array = [main]
	while not stack.is_empty():
		var nd = stack.pop_back()
		for ch in nd.get_children():
			stack.append(ch)
		if nd is MeshInstance3D and nd.visible and nd.mesh is BoxMesh and nd.get_parent() != null and nd.global_position.distance_to(main.cam.global_position) < 14.0:
			var sz: Vector3 = nd.mesh.size * nd.global_transform.basis.get_scale()
			if sz.length() > 1.0:
				print("BIG ", nd.get_path(), " size ", sz, " pos ", nd.global_position)
	for n in []:
		if n is MeshInstance3D and n.visible:
			var d: float = n.global_position.distance_to(main.cam.global_position)
			if d < 12.0:
				print("NODE ", n.name, " ", n.mesh.get_class(), " pos ", n.global_position, " scale ", n.scale, " d=", d)
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
