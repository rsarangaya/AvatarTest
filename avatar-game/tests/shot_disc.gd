extends SceneTree
## Screenshot: an ice disc in flight and a thrown earth wall. Needs a display; set SHOT_OUT to an existing folder.

const TICK := 1.0 / 120.0
const SimScript = preload("res://scripts/player_sim.gd")
const Session = preload("res://scripts/session.gd")
const Settings = preload("res://scripts/settings.gd")
const C = preload("res://scripts/config.gd")

var out := ""
var main
var sim
var world


func ip() -> SimScript.InputState:
	return SimScript.InputState.new()


func _initialize() -> void:
	Settings.persist = false
	Settings.ensure_loaded()
	out = OS.get_environment("SHOT_OUT")
	if out == "":
		out = OS.get_user_data_dir()
	out += "/"
	DirAccess.make_dir_recursive_absolute(out)
	Session.mode = "bots"
	Session.bot_kind = "fighters"
	Session.player_nation = "water"
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	sim = main.sim
	world = main.world
	await frames(4)
	main._capture(true)
	main.overlay.visible = false
	world.bots.clear()
	main.fx.rebuild_bots()
	sim.respawn()
	sim.pos = Vector3(0, world.height_at(0, 4) + 0.05, 4)
	sim.yaw = 0.0
	sim.pitch = 0.0
	main.prev_pos = sim.pos
	var e := ip()
	e.shield_held = true
	sim.step(TICK, e)
	await run(40, 6)
	sim.chi = C.WATER_MAX
	sim.step(TICK, e)                       # a disc leaves the wall
	for k in range(3):
		await run(1, 6)
		await save("disc_%d" % k)
	await run(30, 6)
	# a thrown earth wall
	sim.set_nation("earth")
	world.earth_wall(sim.pos, Vector3(0, 0, -1))
	await run(40, 6)
	var g := ip()
	g.grab_pressed = true
	sim.step(TICK, g)
	await frames(3)
	await save("slab_held")
	var l := ip()
	l.fire_pressed = true
	l.fire_held = true
	sim.step(TICK, l)
	await run(2, 6)
	await save("slab_flying")
	quit(0)


func frames(n: int) -> void:
	for i in range(n):
		main.prev_pos = sim.pos
		await process_frame


func run(n_frames: int, ticks: int) -> void:
	for f in range(n_frames):
		for t in range(ticks):
			sim.step(TICK, ip())
		main.prev_pos = sim.pos
		await process_frame


func save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var err := img.save_png(out + name + ".png")
	print("saved ", name, " err=", err)
