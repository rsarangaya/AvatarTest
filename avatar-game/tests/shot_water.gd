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

	print("startup chunks rebuilt ", main.terrain_view.rebuilt)
	world.bots.clear()
	# lake from the shore near the start
	place(Vector3(28, 0, -30), 0.0, -0.05)
	sim.pos.y = world.height_at(28, -30) + 0.05
	await frames(5)
	await save("w_lake_shore")
	# aerial over the coast
	sim.pos = Vector3(150, 40, 90)
	sim.on_ground = false
	sim.yaw = -PI * 0.25
	sim.pitch = -0.35
	main.prev_pos = sim.pos
	sim.vel = Vector3.ZERO
	await frames(5)
	await save("w_coast_air")
	sim.pos = Vector3(0, 90, 4)
	sim.yaw = 0.0
	sim.pitch = -0.6
	main.prev_pos = sim.pos
	await frames(5)
	await save("w_overview")
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
