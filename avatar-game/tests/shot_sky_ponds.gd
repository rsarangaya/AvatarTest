extends SceneTree
## Screenshots: the map's ponds, a puddle left by a whip, and the darkened sky during an ultimate. Needs a display:
##   set SHOT_OUT to an existing folder, then
##   godot --path . --resolution 1280x720 -s res://tests/shot_sky_ponds.gd

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
	if OS.get_environment("SHOT_Q") != "":
		Settings.quality = int(OS.get_environment("SHOT_Q"))
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
	await process_frame                      # the game scene sets itself up when it enters the tree
	sim = main.sim
	world = main.world
	await frames(4)
	main._capture(true)
	main.overlay.visible = false
	world.bots.clear()
	main.fx.rebuild_bots()

	# the whole map from high up: ponds in the middle too
	sim.pos = Vector3(0, 175, 0)
	sim.on_ground = false
	sim.pitch = -1.5
	sim.yaw = 0.0
	main.prev_pos = sim.pos
	await frames(4)
	await save("pd_overview")

	# at the shore of the first pond
	var pd: Dictionary = world.terrain.ponds[0]
	var px: float = pd["x"]
	var pz: float = pd["z"]
	var pr: float = pd["r"]
	var from := Vector2(px, pz) + Vector2(1.0, 0.0) * (pr + 5.0)
	place(Vector3(from.x, 0, from.y), atan2(-(px - from.x), -(pz - from.y)), -0.12)
	await frames(6)
	await save("pd_pond")

	# a whip leaves a puddle on the dry ground where it lands
	place(Vector3(0, 0, 4), 0.0, -0.45)
	sim.chi = C.WATER_MAX
	var a := ip()
	a.fire_pressed = true
	a.fire_held = true
	sim.step(TICK, a)
	sim.step(TICK, ip())
	await run(8, 6)
	await save("pd_puddle")

	# the sky darkens during an ultimate
	place(Vector3(0, 0, 4), 0.0, 0.05)
	await frames(3)
	await save("pd_sky_day")
	sim.octo_t = 8.0
	for k in range(120):
		await process_frame
	await save("pd_sky_dark")
	sim.octo_t = 0.0
	quit(0)


func place(at: Vector3, yaw: float, pitch: float) -> void:
	sim.respawn()
	sim.pos = Vector3(at.x, world.height_at(at.x, at.z) + 0.05, at.z)
	sim.yaw = yaw
	sim.pitch = pitch
	sim.on_ground = true
	sim.chi = C.WATER_MAX
	main.prev_pos = sim.pos


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
