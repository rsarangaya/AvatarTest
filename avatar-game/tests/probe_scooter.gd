extends SceneTree

const WorldScript = preload("res://scripts/world.gd")
const SimScript = preload("res://scripts/player_sim.gd")
const C = preload("res://scripts/config.gd")
const TICK := 1.0 / 120.0


func inp(mx := 0, my := 0) -> SimScript.InputState:
	var i := SimScript.InputState.new()
	i.move_x = float(mx)
	i.move_y = float(my)
	return i


func _init() -> void:
	var w2 := WorldScript.new(1337)
	w2.bots.clear()
	var p := SimScript.new(w2)
	p.pos = Vector3(52.0, w2.height_at(52.0, -8.0), -8.0)
	p.yaw = PI / 2.0
	for k in range(30):
		p.step(TICK, inp())
	var i3 := inp(0, 1)
	i3.scooter_pressed = true
	p.step(TICK, i3)
	var peak := 0.0
	var minx := 999.0
	for k in range(480):
		p.step(TICK, inp(0, 1))
		peak = maxf(peak, p.speed())
		minx = minf(minx, p.pos.x)
	print("PEAK ", peak, " end ", p.pos, " scooter ", p.scooter, " wet ", w2.terrain.water_depth_at(p.pos.x, p.pos.z))
	for x in range(52, -30, -8):
		print("x ", x, " h ", w2.height_at(float(x), -8.0), " water ", w2.terrain.water_depth_at(float(x), -8.0))
	quit(0)
