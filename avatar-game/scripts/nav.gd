extends RefCounted
## Coarse route planner for the duelist: an A* search over a 5 m grid of the map.
## Cliffs it cannot climb are walls, deep water is walkable but costly (bots swim), steep climbs cost extra.
## Heights are sampled once; the local steering in bender_ai.gd handles anything the coarse grid misses.

const CELL := 5.0
const HALF := 200.0
const N := 81                          # nodes per side (-200 .. 200)

var h := PackedFloat32Array()
var wet := PackedFloat32Array()
var edge := PackedByteArray()          # per node, 8 neighbours: 0 open, 1 needs a hop, 2 blocked by a cliff
var ready := false
const DIRS := [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]


func setup(terrain) -> void:
	h.resize(N * N)
	wet.resize(N * N)
	for iz in range(N):
		for ix in range(N):
			var x := -HALF + float(ix) * CELL
			var z := -HALF + float(iz) * CELL
			h[iz * N + ix] = terrain.height_at(x, z)
			wet[iz * N + ix] = terrain.water_depth_at(x, z)
	edge.resize(N * N * 8)
	for iz in range(2, N - 2):
		for ix in range(2, N - 2):
			var x0 := -HALF + float(ix) * CELL
			var z0 := -HALF + float(iz) * CELL
			for k in range(8):
				var dv: Vector2i = DIRS[k]
				var steps := 4 if (dv.x != 0 and dv.y != 0) else 4
				var len_e: float = CELL * (1.4142 if (dv.x != 0 and dv.y != 0) else 1.0)
				var prev: float = h[iz * N + ix]
				var worst := 0.0
				for st in range(1, steps + 1):
					var f: float = float(st) / float(steps)
					var hh: float = terrain.height_at(x0 + float(dv.x) * CELL * f, z0 + float(dv.y) * CELL * f)
					worst = maxf(worst, (hh - prev) / (len_e / float(steps)) * 1.25)
					prev = hh
				edge[(iz * N + ix) * 8 + k] = 2 if worst > 2.2 else (1 if worst > 1.3 else 0)
	ready = true


func _node(p: Vector2) -> int:
	var ix: int = clampi(roundi((p.x + HALF) / CELL), 0, N - 1)
	var iz: int = clampi(roundi((p.y + HALF) / CELL), 0, N - 1)
	return iz * N + ix


func _pos(i: int) -> Vector2:
	return Vector2(-HALF + float(i % N) * CELL, -HALF + float(i / N) * CELL)


# Waypoints (world x, z) from `from` to `to`, or an empty array when there is no route.
func find(from: Vector2, to: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	if not ready:
		return out
	var s := _node(from)
	var g := _node(to)
	if s == g:
		return out
	var gcost := PackedFloat32Array()
	gcost.resize(N * N)
	gcost.fill(1.0e9)
	var came := PackedInt32Array()
	came.resize(N * N)
	came.fill(-1)
	var closed := PackedByteArray()
	closed.resize(N * N)
	var heap_f: Array[float] = []
	var heap_i: Array[int] = []
	gcost[s] = 0.0
	_push(heap_f, heap_i, 0.0, s)
	var gp := _pos(g)
	var found := false
	var guard := 0
	while not heap_i.is_empty() and guard < 20000:
		guard += 1
		var cur := _pop(heap_f, heap_i)
		if closed[cur] == 1:
			continue
		closed[cur] = 1
		if cur == g:
			found = true
			break
		var cx: int = cur % N
		var cz: int = cur / N
		for k in range(8):
			var dv: Vector2i = DIRS[k]
			var dx: int = dv.x
			var dz: int = dv.y
			if true:
				var nx: int = cx + dx
				var nz: int = cz + dz
				if nx < 2 or nz < 2 or nx > N - 3 or nz > N - 3:
					continue
				var ni: int = nz * N + nx
				if closed[ni] == 1:
					continue
				var d: float = CELL * (1.4142 if (dx != 0 and dz != 0) else 1.0)
				var dh: float = h[ni] - h[cur]
				var ef: int = edge[cur * 8 + k]
				if ef == 2 or dh > 3.2:
					continue                               # a cliff
				var c: float = d + maxf(dh, 0.0) * 2.5
				if ef == 1:
					c += 10.0                              # needs a hop
				if dh < -6.0:
					c += 12.0                              # a big drop
				var wd: float = wet[ni]
				if wd > 1.2:
					c += d * 3.0                           # swimming
				elif wd > 0.5:
					c += d * 0.6
				var ng: float = gcost[cur] + c
				if ng < gcost[ni]:
					gcost[ni] = ng
					came[ni] = cur
					_push(heap_f, heap_i, ng + _pos(ni).distance_to(gp), ni)
	if not found:
		return out
	var rev: Array[int] = []
	var k := g
	while k != -1 and k != s:
		rev.append(k)
		k = came[k]
	rev.reverse()
	for n in rev:
		out.append(_pos(n))
	return out


func _push(hf: Array[float], hi: Array[int], f: float, i: int) -> void:
	hf.append(f)
	hi.append(i)
	var c := hf.size() - 1
	while c > 0:
		var p := (c - 1) / 2
		if hf[p] <= hf[c]:
			break
		var tf := hf[p]
		hf[p] = hf[c]
		hf[c] = tf
		var ti := hi[p]
		hi[p] = hi[c]
		hi[c] = ti
		c = p


func _pop(hf: Array[float], hi: Array[int]) -> int:
	var top := hi[0]
	var lf: float = hf.pop_back()
	var li: int = hi.pop_back()
	if not hi.is_empty():
		hf[0] = lf
		hi[0] = li
		var c := 0
		var n := hi.size()
		while true:
			var l := c * 2 + 1
			var r := l + 1
			var m := c
			if l < n and hf[l] < hf[m]:
				m = l
			if r < n and hf[r] < hf[m]:
				m = r
			if m == c:
				break
			var tf := hf[m]
			hf[m] = hf[c]
			hf[c] = tf
			var ti := hi[m]
			hi[m] = hi[c]
			hi[c] = ti
			c = m
	return top
