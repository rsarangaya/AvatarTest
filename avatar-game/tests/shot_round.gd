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

	main._capture(false)
	main.overlay.visible = true
	await frames(3)
	await save("b_menu")
	main._capture(true)
	main.overlay.visible = false
	main._pick_bots("duel")
	await frames(20)
	await save("r_start")
	await frames(200)
	main.round_t = 0.0
	print("ROUND t after wait ", main.round_t)
	var boss = world.bots[0]
	boss.hp = 1.0
	world.damage_bot(boss, 50.0, Vector3.ZERO, false)
	await frames(20)
	await save("r_win")
	print("ROUND msg ", main.round_msg, " t ", main.round_t)
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
