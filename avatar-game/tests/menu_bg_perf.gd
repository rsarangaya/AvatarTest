extends SceneTree
## Main-menu frame time with the 3D backdrop, per quality tier, and node counts before / after it is freed. Needs a window:
##   PERF_Q=0|1|2 godot --path . --resolution 1600x900 -s res://tests/menu_bg_perf.gd

const Settings = preload("res://scripts/settings.gd")


func _initialize() -> void:
	Settings.persist = false
	Settings.ensure_loaded()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var q := OS.get_environment("PERF_Q")
	Settings.quality = int(q) if q != "" else Settings.quality
	var base := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var menu = load("res://scenes/menu.tscn").instantiate()
	menu.skip_scene_change = true
	root.add_child(menu)
	for i in range(30):
		await process_frame
	var n_on := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var t0 := Time.get_ticks_usec()
	var frames := 300
	var worst := 0.0
	var last := t0
	for i in range(frames):
		await process_frame
		var now := Time.get_ticks_usec()
		worst = maxf(worst, float(now - last) / 1000.0)
		last = now
	var avg := float(Time.get_ticks_usec() - t0) / 1000.0 / frames
	var draws := int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	print("QUALITY ", Settings.QUALITY_NAMES[Settings.quality], "  menu avg %.2f ms  worst %.2f ms  draws %d" % [avg, worst, draws])
	menu._start_game()
	for i in range(5):
		await process_frame
	var n_off := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	print("nodes: before menu %d, menu with backdrop %d, after start (backdrop freed) %d" % [base, n_on, n_off])
	quit(0)
