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

	# 1. bots + HUD from the start position
	place(Vector3(0, 0, 4), 0.0, -0.05)
	await frames(4)
	await save("1_bots")

	# 2. punch + slice in flight
	place(Vector3(0, 0, 4), 0.0, -0.05)
	var a := ip()
	a.fire_pressed = true
	a.fire_held = true
	sim.step(TICK, a)
	sim.step(TICK, ip())                                    # release: the punch leaves
	await run(2, 5, func(f, t): return ip())
	var s := ip()
	s.slice_pressed = true
	sim.step(TICK, s)
	await run(3, 5, func(f, t): return ip())
	await save("2_punch_and_slice")

	# 3. charging a blast
	place(Vector3(0, 0, 4), 0.0, -0.05)
	var c0 := ip()
	c0.fire_pressed = true
	c0.fire_held = true
	sim.step(TICK, c0)
	await run(14, 7, func(f, t):
		var i := ip()
		i.fire_held = true
		return i)
	print("charge ", sim.charge, " charging ", sim.charging)
	await save("3_charge")
	sim.step(TICK, ip())                                    # release: fires the blast
	await frames(3)
	await save("3b_blast")

	# 4. shield up, with a bot bolt coming in
	place(Vector3(0, 0, 4), 0.0, -0.05)
	await run(10, 5, func(f, t):
		var i := ip()
		i.shield_held = true
		return i)
	print("shield ", sim.shield_on)
	await save("4_shield")

	# 5. suction pulling the bots in
	place(Vector3(0, 0, 4), 0.0, -0.05)
	await run(26, 5, func(f, t):
		var i := ip()
		i.suction_held = true
		return i)
	print("suction ", sim.suction_on)
	await save("5_suction")

	# 6. Air Breath
	world.reset_bots()
	place(Vector3(0, 0, 4), 0.0, 0.05)
	sim.ult = 100.0
	var u := ip()
	u.ult_pressed = true
	sim.step(TICK, u)
	await run(12, 6, func(f, t): return ip())
	print("breath ", sim.breath_t)
	await save("6_breath")

	# 7. Air Scooter, looking down at the bubble
	world.reset_bots()
	place(Vector3(0, 0, 4), 0.0, 0.0)
	var q := ip()
	q.scooter_pressed = true
	sim.step(TICK, q)
	await run(8, 6, func(f, t):
		var i := ip()
		i.move_y = 1.0
		return i)
	sim.pitch = -1.0
	await run(4, 6, func(f, t):
		var i := ip()
		i.move_y = 1.0
		return i)
	print("scooter ", sim.scooter, " speed ", sim.speed())
	await save("7_scooter_down")
	sim.pitch = -0.2
	await run(3, 4, func(f, t):
		var i := ip()
		i.move_y = 1.0
		return i)
	await save("7b_scooter_ahead")

	# 8. Air Bomb from the top of the Air Temple
	world.reset_bots()
	sim.respawn()
	sim.scooter = false
	var top: float = world.summit.y
	var cell := Vector2(world.summit.x, world.summit.z)
	var bots_at := Vector3(cell.x, world.height_at(cell.x, cell.y), cell.y + 3.0)
	for b in world.bots:
		b.pos = bots_at + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4))
		b.pos.y = world.height_at(b.pos.x, b.pos.z)
		b.home = b.pos
	sim.pos = Vector3(cell.x, top + 14.0, cell.y - 6.0)
	sim.on_ground = false
	sim.vel = Vector3.ZERO
	sim.yaw = PI
	sim.pitch = -0.5
	main.prev_pos = sim.pos
	sim.ult = 100.0
	await run(2, 2, func(f, t): return ip())
	var bx := ip()
	bx.ult_pressed = true
	sim.step(TICK, bx)
	await run(2, 4, func(f, t): return ip())
	print("bomb phase ", sim.slam.get("phase"), " alt ", sim.height_above_ground())
	await save("8_bomb_wind")
	await run(3, 8, func(f, t): return ip())
	await save("8b_bomb_dive")
	var guard := 0
	while not sim.slam.is_empty() and guard < 400:
		sim.step(TICK, ip())
		guard += 1
	main.prev_pos = sim.pos
	await frames(4)
	await save("9_bomb_impact")
	sim.pitch = 0.1
	sim.yaw = PI
	await frames(30)
	await save("9b_bomb_crater")

	# 10. the hills: overview from the start and from up the slope
	world.reset_bots()
	place(Vector3(-20, 0, -2), 0.0, 0.1)
	sim.yaw = 0.0
	await frames(4)
	await save("10_hills")
	place(Vector3(0, 0, 4), PI * 0.5, 0.15)
	await frames(3)
	await save("10b_hills_west")

	# 11. switch to earth, rock throw
	world.reset_bots()
	place(Vector3(0, 0, 4), 0.0, -0.05)
	var e2 := ip()
	e2.element_pressed = "earth"
	sim.step(TICK, e2)
	await frames(3)
	await save("11_earth_hud")
	var t0 := ip()
	t0.fire_pressed = true
	t0.fire_held = true
	sim.step(TICK, t0)
	sim.step(TICK, ip())
	await run(4, 6, func(f, t): return ip())
	await save("11b_rock")

	# 12. charged earth wave
	place(Vector3(0, 0, 4), 0.0, -0.05)
	sim.element = "earth"
	var w0 := ip()
	w0.fire_pressed = true
	w0.fire_held = true
	sim.step(TICK, w0)
	await run(14, 7, func(f, t):
		var i := ip()
		i.fire_held = true
		return i)
	sim.step(TICK, ip())
	await run(6, 6, func(f, t): return ip())
	await save("12_wave")

	# 13. pillar (F) and wall (E) and ramp (RMB)
	world.reset_bots()
	place(Vector3(0, 0, 4), 0.0, 0.0)
	sim.element = "earth"
	var f1 := ip()
	f1.suction_held = true
	sim.step(TICK, f1)
	sim.step(TICK, ip())
	await run(10, 6, func(f, t): return ip())
	await save("13_pillar")
	place(Vector3(0, 0, 4), 0.0, 0.0)
	sim.element = "earth"
	var e1 := ip()
	e1.shield_held = true
	sim.step(TICK, e1)
	sim.step(TICK, ip())
	await run(10, 6, func(f, t): return ip())
	await save("13b_wall")
	place(Vector3(14, 0, 4), 0.0, 0.0)
	sim.element = "earth"
	var r1 := ip()
	r1.slice_pressed = true
	sim.step(TICK, r1)
	await run(10, 6, func(f, t): return ip())
	await save("13c_ramp")

	# 14. earthquake
	world.reset_bots()
	place(Vector3(0, 0, 4), 0.0, 0.1)
	sim.element = "earth"
	sim.ult = 100.0
	var q1 := ip()
	q1.ult_pressed = true
	sim.step(TICK, q1)
	await run(10, 12, func(f, t): return ip())
	await save("14_quake")
	var g2 := 0
	while sim.quake_t > 0.0 and g2 < 1200:
		sim.step(TICK, ip())
		g2 += 1
	main.prev_pos = sim.pos
	await frames(4)
	await save("14b_after_quake")
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
