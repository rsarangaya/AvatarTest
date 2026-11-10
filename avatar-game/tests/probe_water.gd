extends SceneTree
## Prints how wet the map is and where the duel pads end up (run headless, for tuning the stream network).

const WorldScript = preload("res://scripts/world.gd")
const TerrainScript = preload("res://scripts/terrain.gd")


func _init() -> void:
	for sd in [1337, 7, 42]:
		var w := WorldScript.new(sd)
		var t = w.terrain
		var n: int = TerrainScript.N
		var wet := 0
		var inner := 0
		var inner_wet := 0
		for iz in range(0, n, 2):
			for ix in range(0, n, 2):
				var x: float = ix * TerrainScript.CELL - TerrainScript.HALF
				var z: float = iz * TerrainScript.CELL - TerrainScript.HALF
				var d: bool = t.water_depth_at(x, z) > 0.2
				if absf(x) < 120.0 and absf(z) < 120.0:
					inner += 1
					if d:
						inner_wet += 1
				if d:
					wet += 1
		var sides: Array = w._duel_sides()
		for s in sides:
			var nw = t.nearest_water(s.x, s.y, 60.0)
			print("  pad ", s, " nearest water ", "none within 60 m" if nw == null else "%.0f m" % Vector2(nw.x - s.x, nw.z - s.y).length())
		print("seed %d: wet %.1f%% of map, %.1f%% of the middle 240 m, ponds %d, pads %s %s" % [sd, 100.0 * wet / float((n / 2) * (n / 2)), 100.0 * inner_wet / float(inner), t.ponds.size(), sides[0], sides[1]])
	quit(0)
