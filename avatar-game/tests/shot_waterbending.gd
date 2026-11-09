extends SceneTree
## Stages each waterbending move in the real scene and saves screenshots. Needs a display:
##   set SHOT_OUT to an existing folder, then
##   godot --path . --resolution 1280x720 -s res://tests/shot_waterbending.gd

const TICK := 1.0 / 120.0
const SimScript = preload("res://scripts/player_sim.gd")
const TerrainScript = preload("res://scripts/terrain.gd")
const C = preload("res://scripts/config.gd")

var out := ""
var main
var sim
var world
var spot := {}


func ip() -> SimScript.InputState:
	return SimScript.InputState.new()


func _initialize() -> void:
	out = OS.get_environment("SHOT_OUT")
	if out == "":
		out = OS.get_user_data_dir()
	out += "/"
	DirAccess.make_dir_recursive_absolute(out)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.overlay.visible = false
	sim = main.sim
	world = main.world
	spot = find_spot()
	sim.element = "water"
	sim.chi = C.WATER_MAX

	# pause menu with the three nations
	main._capture(false)
	main.overlay.visible = true
	await frames(3)
	await save("wb_menu")
	main.overlay.visible = false

	# water whip on a dummy
	world.bots.clear()
	place(Vector3(0, 0, 4), 0.0, 0.02)
	var b1 = add_bot(0.0, -2.0)
	var a := ip()
	a.fire_pressed = true
	a.fire_held = true
	sim.step(TICK, a)
	sim.step(TICK, ip())
	await run(3, 6, func(f, t): return ip())
	await save("wb_whip")

	# water jet
	place(Vector3(0, 0, 4), 0.0, 0.02)
	b1.pos = Vector3(0.0, world.height_at(0.0, -6.0), -6.0)
	await run(14, 6, func(f, t):
		var h := ip()
		h.fire_held = true
		h.fire_pressed = f == 0 and t == 0
		return h)
	await save("wb_jet")
	await run(2, 6, func(f, t): return ip())

	# ice wall, then a bolt breaks it
	place(Vector3(0, 0, 4), 0.0, 0.02)
	var e := ip()
	e.shield_held = true
	sim.step(TICK, e)
	await run(10, 6, func(f, t): return ip())
	await save("wb_icewall")

	# freeze an enemy
	world.bots.clear()
	place(Vector3(0, 0, 4), 0.0, 0.0)
	var fb = add_bot(0.0, 2.5)
	var e2 := ip()
	e2.shield_held = true
	sim.step(TICK, e2)
	await run(6, 6, func(f, t): return ip())
	sim.pitch = 0.05
	await save("wb_freeze")

	# ice shards
	world.bots.clear()
	place(Vector3(0, 0, 4), -1.5708, 0.02)              # facing away from the ice wall made above
	add_bot(-22.0, 4.0)
	var z := ip()
	z.barrage_pressed = true
	sim.step(TICK, z)
	await run(2, 4, func(f, t): return ip())
	await save("wb_shards")

	# ice skate across the lake
	world.bots.clear()
	place(spot["land"], atan2(-(spot["water"].x - spot["land"].x), -(spot["water"].z - spot["land"].z)), -0.15)
	var q := ip()
	q.scooter_pressed = true
	sim.step(TICK, q)
	await run(22, 6, func(f, t):
		var m := ip()
		m.move_y = 1.0
		return m)
	sim.pitch = -0.4
	await run(2, 6, func(f, t):
		var m2 := ip()
		m2.move_y = 1.0
		return m2)
	await save("wb_skate")
	var q2 := ip()
	q2.scooter_pressed = true
	sim.step(TICK, q2)

	# tidal wave
	place(spot["land"], atan2(-(spot["water"].x - spot["land"].x), -(spot["water"].z - spot["land"].z)), 0.0)
	sim.ult = C.ULT_MAX
	var tb = add_bot_at(spot["land"], 9.0)
	for i in range(40):
		var h2 := ip()
		h2.ult_held = true
		h2.ult_pressed = i == 0
		sim.step(TICK, h2)
	await run(10, 6, func(f, t): return ip())
	sim.pitch = -0.1
	await save("wb_tide_start")
	await run(20, 6, func(f, t): return ip())
	await save("wb_tide_mid")
	await run(60, 6, func(f, t): return ip())
	sim.pitch = -0.5
	await save("wb_tide_wake")

	# octopus form
	world.bots.clear()
	place(Vector3(0, 0, 4), 0.0, 0.02)
	sim.ult = C.ULT_MAX
	var ob = add_bot(0.0, -3.0)
	var xt := ip()
	xt.ult_pressed = true
	xt.ult_held = true
	sim.step(TICK, xt)
	sim.step(TICK, ip())
	await run(14, 6, func(f, t): return ip())
	await save("wb_octo_idle")
	var gq := ip()
	gq.scooter_pressed = true
	sim.step(TICK, gq)
	await run(10, 6, func(f, t): return ip())
	await save("wb_octo_grab")
	var gq2 := ip()
	gq2.scooter_pressed = true
	sim.step(TICK, gq2)
	await run(3, 6, func(f, t): return ip())
	await save("wb_octo_throw")
	place(Vector3(0, 0, 4), 0.0, 0.02)
	sim.octo_t = C.OCTO_TIME
	ob.pos = Vector3(0.0, world.height_at(0.0, -3.0), -3.0)
	ob.vel = Vector3.ZERO
	var l := ip()
	l.fire_pressed = true
	l.fire_held = true
	sim.step(TICK, l)
	await run(3, 6, func(f, t): return ip())
	await save("wb_octo_swipe")
	quit(0)


func find_spot() -> Dictionary:
	var t = world.terrain
	var n: int = TerrainScript.N
	for iz in range(30, n - 30, 5):
		for ix in range(30, n - 30, 5):
			var i: int = iz * n + ix
			if t.ws[i] < TerrainScript.NO_WATER * 0.5 or t.ws[i] - t.h[i] < 1.8:
				continue
			var wx: float = ix * TerrainScript.CELL - TerrainScript.HALF
			var wz: float = iz * TerrainScript.CELL - TerrainScript.HALF
			if absf(wx) > 150.0 or absf(wz) > 150.0:
				continue
			for a8 in range(8):
				var d := Vector2(cos(float(a8) * TAU / 8.0), sin(float(a8) * TAU / 8.0))
				for r in [5.0, 7.0, 9.0, 11.0]:
					var q: Vector2 = Vector2(wx, wz) + d * float(r)
					var flat := true
					for k in range(8):
						var o: Vector2 = q + Vector2(cos(float(k) * TAU / 8.0), sin(float(k) * TAU / 8.0)) * 2.5
						if t.water_depth_at(o.x, o.y) > 0.0 or absf(t.height_at(o.x, o.y) - t.height_at(q.x, q.y)) > 0.7:
							flat = false
					if flat and t.water_depth_at(q.x, q.y) == 0.0 and absf(q.x) < 170.0 and absf(q.y) < 170.0:
						return {"water": Vector3(wx, t.ws[i], wz), "land": Vector3(q.x, t.height_at(q.x, q.y), q.y)}
	return {"water": Vector3(0, 0, 40), "land": Vector3(0, 0, 4)}


func add_bot(x: float, z: float):
	var bp := Vector3(x, world.height_at(x, z), z)
	var b = load("res://scripts/world.gd").Bot.new(bp)
	b.fire_cd = 99999.0
	b.fighter = false
	b.wander_t = 99999.0
	b.wander_to = bp
	b.on_ground = true
	world.bots.append(b)
	main.fx.rebuild_bots()
	return b


func add_bot_at(from: Vector3, dist: float):
	var f := Vector3(-sin(sim.yaw), 0.0, -cos(sim.yaw))
	return add_bot(from.x + f.x * dist, from.z + f.z * dist)


func place(at: Vector3, yaw: float, pitch: float) -> void:
	sim.respawn()
	sim.pos = Vector3(at.x, world.height_at(at.x, at.z) + 0.05, at.z)
	sim.yaw = yaw
	sim.pitch = pitch
	sim.on_ground = true
	sim.chi = C.WATER_MAX
	sim.iwall_cd = 0.0
	sim.barrage_cd = 0.0
	sim.punch_cd = 0.0
	sim.heal_cd = 0.0
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
	var err := img.save_png(out + name + ".png")
	print("saved ", name, " err=", err)
