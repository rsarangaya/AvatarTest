extends SceneTree
## Cost of rebuilding terrain chunks (headless): what an earthbending edit costs the frame.

const WorldScript = preload("res://scripts/world.gd")
const ViewScript = preload("res://scripts/terrain_view.gd")


func _initialize() -> void:
	var w := WorldScript.new(1337)
	var v := ViewScript.new()
	root.add_child(v)
	v.setup(w.terrain)
	v.flush()
	var t0 := Time.get_ticks_usec()
	var n := 0
	for k in range(60):
		w.terrain.raise_mound(float(k % 20) * 10.0 - 100.0, float(k / 20) * 10.0, 3.0, 4.0, 8.0)
	var d: Dictionary = {}
	for k in w.terrain.take_dirty():
		d[k] = true
	print("dirty chunks after 60 mounds: ", d.size())
	for k in d.keys():
		w.terrain.dirty[k] = true
	var t1 := Time.get_ticks_usec()
	while v.update(1000) > 0:
		pass
	var t2 := Time.get_ticks_usec()
	print("CHUNKS rebuilt %d in %.1f ms = %.2f ms per chunk" % [v.rebuilt, float(t2 - t1) / 1000.0, float(t2 - t1) / 1000.0 / maxf(float(d.size()), 1.0)])
	quit(0)
