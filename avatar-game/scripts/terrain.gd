extends RefCounted
## Deformable heightfield. Physics and rendering share this one grid, and height_at() interpolates
## over exactly the same triangles the renderer draws, so what you see is what you stand on.
##
## Earthbending raises it, impacts crater it. `base` remembers the untouched ground so craters
## have a floor (you cannot dig forever) and raises have a ceiling.

const C = preload("res://scripts/config.gd")

const CELL := 1.0
const HALF := 200.0
const N := 401                  # samples per side: 400 x 400 cells
const CHUNK := 20               # cells per render chunk side
const NCHUNK := 20              # chunks per side
const SEA_Y := -3.0             # level of the sea and every lake below it
const NO_WATER := -1.0e9
const FLOOR_DEPTH := 3.5        # deepest a crater may go below the original ground
const MAX_RAISE := 45.0         # tallest a spire may stand above the original ground

var h := PackedFloat32Array()       # current heights
var base := PackedFloat32Array()    # untouched ground (no hills): the dig floor
var built := PackedFloat32Array()   # the finished level, before anyone bent anything (for tinting new earth)
var dirty := {}                     # chunk index -> true, consumed by the renderer
var version := 0
var heal_enabled := true
var cool := PackedFloat32Array()    # seconds until a cell starts healing
var pinned := {}                    # cells held up for good (an earth wall); they never heal until knocked down
var active := {}                    # cell index -> true for every cell that differs from `built`
var _heal_acc := 0.0

var ws := PackedFloat32Array()      # water surface height per vertex (NO_WATER where there is none)
var wet_chunks := {}                # chunk index -> true when any water touches it

var ice := PackedByteArray()        # per vertex: 0 none, 1 frozen water, 2 ice wall (tinted by the renderer)
var ice_orig := {}                  # vertex index -> {h: ground height before it froze, t: seconds until it melts}
var puddle_orig := {}               # vertex index -> {w: the water level before a puddle landed, t: seconds until it dries}
var ponds: Array = []               # ponds carved into the level: {x, z, r, level}
var _ice_acc := 0.0

var _noise := FastNoiseLite.new()
var _low := FastNoiseLite.new()     # the first octave of _noise on its own: the broad shape rivers follow
var _basin := FastNoiseLite.new()
var _mtn := FastNoiseLite.new()
var _riv := FastNoiseLite.new()
var _warp := FastNoiseLite.new()
var _rs := PackedFloat32Array()     # river surface candidate per vertex (only while generating)
var _rg := PackedFloat32Array()     # how much each vertex belongs to a river valley (0..1)
var _rc := PackedFloat32Array()     # how much of it is the river channel itself (0..1)
var _rough := FastNoiseLite.new()
var _locked := false                # true while the level is being generated (no floor/ceiling clamps)


# ------------------------------------------------------------------ generation

func generate(seed_value: int) -> void:
	_noise.seed = seed_value
	_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_noise.frequency = 1.0 / 38.0
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = 4
	_low.seed = seed_value
	_low.noise_type = FastNoiseLite.TYPE_PERLIN
	_low.frequency = 1.0 / 38.0
	_low.fractal_type = FastNoiseLite.FRACTAL_NONE
	_basin.seed = seed_value + 11
	_basin.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_basin.frequency = 1.0 / 130.0
	_mtn.seed = seed_value + 23
	_mtn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_mtn.frequency = 1.0 / 95.0
	_mtn.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_mtn.fractal_octaves = 3
	_riv.seed = seed_value + 31
	_riv.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_riv.frequency = 1.0 / 110.0
	_warp.seed = seed_value + 41
	_warp.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_warp.frequency = 1.0 / 70.0
	_rough.seed = seed_value + 5
	_rough.noise_type = FastNoiseLite.TYPE_PERLIN
	_rough.frequency = 0.9
	h.resize(N * N)
	base.resize(N * N)
	_rs.resize(N * N)
	_rg.resize(N * N)
	_rc.resize(N * N)
	_locked = true
	for iz in range(N):
		for ix in range(N):
			var x := ix * CELL - HALF
			var z := iz * CELL - HALF
			var i := iz * N + ix
			var g := _ground_height(x, z)
			var rs := -1.0e4
			var wgt := 0.0
			var cw := 0.0
			var d := Vector2(x, z).length()
			var e := maxf(absf(x), absf(z))
			# rivers: valleys cut by warped noise, only on low ground, fading out towards the highlands, the
			# training meadow and the sea
			var gate := C.ss(55.0, 82.0, d) * (1.0 - C.ss(SEA_Y + 7.0, SEA_Y + 20.0, _glow(x, z))) * (1.0 - C.ss(150.0, 182.0, e))
			if gate > 0.001:
				var wx := x + _warp.get_noise_2d(x, z) * 34.0
				var wz := z + _warp.get_noise_2d(z + 400.0, x - 400.0) * 34.0
				var f := absf(_riv.get_noise_2d(wx, wz))
				var valley := (1.0 - C.ss(0.05, 0.22, f)) * gate
				var core := (1.0 - C.ss(0.022, 0.07, f)) * gate
				if valley > 0.0:
					rs = _glow(x, z) - 0.9
					var banks := lerpf(g, minf(g, rs + 1.0), valley)
					g = lerpf(banks, rs - 2.3, core)
					wgt = valley
					cw = core
			h[i] = g
			base[i] = g
			_rs[i] = rs
			_rg[i] = wgt
			_rc[i] = cw
	dirty.clear()


# Everything except the fine noise: the broad shape of the land. Rivers follow this.
func _glow(x: float, z: float) -> float:
	var d := Vector2(x, z).length()
	var flat := 1.0 - C.ss(22.0, 38.0, d)
	return _low.get_noise_2d(x, z) * 0.533 * 16.0 * (1.0 - flat) + _shape(x, z, d)


# Hills, basins, mountains and the coast: the parts of the ground that are not noise.
func _shape(x: float, z: float, d: float) -> float:
	var flat := 1.0 - C.ss(22.0, 38.0, d)
	var e := maxf(absf(x), absf(z))
	var v := 11.0 * exp(-((pow(x - 52.0, 2.0) + pow(z + 8.0, 2.0)) / (2.0 * 17.0 * 17.0)))
	v *= 1.0 - flat
	v += C.ss(38.0, 80.0, d) * 7.0                                   # the outlands sit a little higher than the meadow
	# lakes and bays: broad basins in the outlands plus one lake not far from the meadow
	v -= C.ss(0.22, 0.6, _basin.get_noise_2d(x, z)) * C.ss(70.0, 120.0, d) * 20.0
	v -= 17.0 * exp(-((pow(x - 28.0, 2.0) + pow(z + 66.0, 2.0)) / (2.0 * 12.0 * 12.0)))
	# mountain ranges in the highlands
	var m := maxf(0.0, _mtn.get_noise_2d(x, z) * 0.5 + 0.5 - 0.58)
	v += m * 62.0 * C.ss(75.0, 125.0, d) * (1.0 - C.ss(140.0, 175.0, e))
	# the land sinks into the sea towards the edge of the map
	v -= C.ss(140.0, 198.0, e) * 34.0
	return v


# The natural ground: rolling noise on top of that shape.
func _ground_height(x: float, z: float) -> float:
	var d := Vector2(x, z).length()
	var flat := 1.0 - C.ss(22.0, 38.0, d)
	return _noise.get_noise_2d(x, z) * 16.0 * (1.0 - flat) + _shape(x, z, d)


# Carve a round pond (call while the level is being built, before finish_generation). The bowl sinks below `level`, the
# average-low height of the rim, so the water fills it exactly; the shore is where the ground comes back above it.
func add_pond(cx: float, cz: float, radius: float, depth: float) -> void:
	var rim := 1.0e9
	for k in range(12):
		var a := float(k) * TAU / 12.0
		rim = minf(rim, height_at(cx + cos(a) * radius, cz + sin(a) * radius))
	var level := minf(rim, height_at(cx, cz) + 1.0) - 0.15
	var rg := _cell_range(cx, cz, radius * 1.15)
	for iz in range(rg[2], rg[3] + 1):
		for ix in range(rg[0], rg[1] + 1):
			var d := Vector2(ix * CELL - HALF - cx, iz * CELL - HALF - cz).length()
			if d >= radius * 1.15:
				continue
			var i := iz * N + ix
			var floor_y := level - depth * (1.0 - C.ss(0.0, radius * 0.9, d))
			if d <= radius and floor_y < h[i]:
				h[i] = floor_y
				base[i] = minf(base[i], floor_y)             # the pond floor is natural ground: the dig floor sits below it
	ponds.append({"x": cx, "z": cz, "r": radius, "level": level})


func finish_generation() -> void:
	_locked = false
	built = h.duplicate()
	ws.resize(N * N)
	wet_chunks.clear()
	for i in range(N * N):
		var surf := NO_WATER
		if h[i] < SEA_Y:
			surf = SEA_Y
		if _rc[i] > 0.1 and h[i] < _rs[i]:
			surf = maxf(surf, _rs[i])
		ws[i] = surf
		if surf > NO_WATER * 0.5:
			var ix := i % N
			var iz := i / N
			wet_chunks[clampi(iz / CHUNK, 0, NCHUNK - 1) * NCHUNK + clampi(ix / CHUNK, 0, NCHUNK - 1)] = true
			if ix % CHUNK == 0 and ix > 0:
				wet_chunks[clampi(iz / CHUNK, 0, NCHUNK - 1) * NCHUNK + ix / CHUNK - 1] = true
			if iz % CHUNK == 0 and iz > 0:
				wet_chunks[(iz / CHUNK - 1) * NCHUNK + clampi(ix / CHUNK, 0, NCHUNK - 1)] = true
	for pd in ponds:                                   # ponds: water fills every vertex of the bowl that sits below the level
		var prg := _cell_range(float(pd["x"]), float(pd["z"]), float(pd["r"]) * 1.15)
		for iz in range(prg[2], prg[3] + 1):
			for ix in range(prg[0], prg[1] + 1):
				var pi := iz * N + ix
				if h[pi] < float(pd["level"]) - 0.02 and Vector2(ix * CELL - HALF - float(pd["x"]), iz * CELL - HALF - float(pd["z"])).length() <= float(pd["r"]) * 1.15:
					ws[pi] = maxf(ws[pi], float(pd["level"]))
					_mark_wet(ix, iz)
	cool.resize(N * N)
	active.clear()
	pinned.clear()
	dirty.clear()
	ice.resize(N * N)
	ice.fill(0)
	ice_orig.clear()
	puddle_orig.clear()
	version += 1


# ------------------------------------------------------------------ queries

func height_at(x: float, z: float) -> float:
	var gx := clampf((x + HALF) / CELL, 0.0, float(N - 1) - 0.0001)
	var gz := clampf((z + HALF) / CELL, 0.0, float(N - 1) - 0.0001)
	var ix := int(gx)
	var iz := int(gz)
	var fx := gx - ix
	var fz := gz - iz
	var i := iz * N + ix
	var h0 := h[i]
	var h1 := h[i + 1]
	var h2 := h[i + N]
	if fx + fz <= 1.0:
		return h0 + fx * (h1 - h0) + fz * (h2 - h0)
	var h3 := h[i + N + 1]
	return h3 + (1.0 - fx) * (h2 - h3) + (1.0 - fz) * (h1 - h3)


# Depth of the water at (x, z): 0 on dry land. Interpolated over the same triangles as height_at, so the shoreline
# you see is the shoreline you wade through. Digging deepens water; digging dry ground never floods it.
func water_depth_at(x: float, z: float) -> float:
	var gx := clampf((x + HALF) / CELL, 0.0, float(N - 1) - 0.0001)
	var gz := clampf((z + HALF) / CELL, 0.0, float(N - 1) - 0.0001)
	var ix := int(gx)
	var iz := int(gz)
	var i := iz * N + ix
	var w0 := ws[i]
	var w1 := ws[i + 1]
	var w2 := ws[i + N]
	var w3 := ws[i + N + 1]
	if w0 < -1.0e8 and w1 < -1.0e8 and w2 < -1.0e8 and w3 < -1.0e8:
		return 0.0
	var d0 := maxf(w0 - h[i], 0.0)
	var d1 := maxf(w1 - h[i + 1], 0.0)
	var d2 := maxf(w2 - h[i + N], 0.0)
	var fx := gx - ix
	var fz := gz - iz
	if fx + fz <= 1.0:
		return d0 + fx * (d1 - d0) + fz * (d2 - d0)
	var d3 := maxf(w3 - h[i + N + 1], 0.0)
	return d3 + (1.0 - fx) * (d2 - d3) + (1.0 - fz) * (d1 - d3)


func surface_at(x: float, z: float) -> float:
	return height_at(x, z) + water_depth_at(x, z)


# True where a hill or camp should not be placed: low ground or a river valley (usable while generating).
func water_possible(x: float, z: float) -> bool:
	var gx := clampi(int(round((x + HALF) / CELL)), 0, N - 1)
	var gz := clampi(int(round((z + HALF) / CELL)), 0, N - 1)
	var i := gz * N + gx
	if h[i] < SEA_Y + 3.0:
		return true
	return _rg.size() == N * N and _rg[i] > 0.02


# Slope of the triangle under (x, z): d(height)/dx, d(height)/dz.
func gradient_at(x: float, z: float) -> Vector2:
	var gx := clampf((x + HALF) / CELL, 0.0, float(N - 1) - 0.0001)
	var gz := clampf((z + HALF) / CELL, 0.0, float(N - 1) - 0.0001)
	var ix := int(gx)
	var iz := int(gz)
	var i := iz * N + ix
	var h0 := h[i]
	var h1 := h[i + 1]
	var h2 := h[i + N]
	if (gx - ix) + (gz - iz) <= 1.0:
		return Vector2((h1 - h0) / CELL, (h2 - h0) / CELL)
	var h3 := h[i + N + 1]
	return Vector2((h3 - h2) / CELL, (h3 - h1) / CELL)


func base_at(x: float, z: float) -> float:
	var gx := clampf((x + HALF) / CELL, 0.0, float(N - 1))
	var gz := clampf((z + HALF) / CELL, 0.0, float(N - 1))
	return base[int(round(gz)) * N + int(round(gx))]


# Smoothed normal at a grid vertex (for lighting only).
func vertex_normal(ix: int, iz: int) -> Vector3:
	var xl := maxi(ix - 1, 0)
	var xr := mini(ix + 1, N - 1)
	var zl := maxi(iz - 1, 0)
	var zr := mini(iz + 1, N - 1)
	var dx := (h[iz * N + xr] - h[iz * N + xl]) / (float(xr - xl) * CELL)
	var dz := (h[zr * N + ix] - h[zl * N + ix]) / (float(zr - zl) * CELL)
	return Vector3(-dx, 1.0, -dz).normalized()


func take_dirty() -> Array:
	var out := dirty.keys()
	dirty.clear()
	return out


# ------------------------------------------------------------------ editing

func _mark(ix0: int, iz0: int, ix1: int, iz1: int) -> void:
	version += 1
	if not _locked and cool.size() == N * N:
		for iz in range(clampi(iz0, 0, N - 1), clampi(iz1, 0, N - 1) + 1):
			for ix in range(clampi(ix0, 0, N - 1), clampi(ix1, 0, N - 1) + 1):
				var i := iz * N + ix
				var d: float = h[i] - built[i]
				if pinned.has(i):
					if d > 0.3:
						continue                      # a standing wall stays as it is
					pinned.erase(i)                   # knocked down: it heals like any other ground
				if absf(d) > 0.02:
					cool[i] = C.HEAL_DELAY_RAISED if d > 0.0 else C.HEAL_DELAY_DUG
					active[i] = true
	var c0x := clampi((ix0 - 1) / CHUNK, 0, NCHUNK - 1)
	var c1x := clampi((ix1 + 1) / CHUNK, 0, NCHUNK - 1)
	var c0z := clampi((iz0 - 1) / CHUNK, 0, NCHUNK - 1)
	var c1z := clampi((iz1 + 1) / CHUNK, 0, NCHUNK - 1)
	for cz in range(c0z, c1z + 1):
		for cx in range(c0x, c1x + 1):
			dirty[cz * NCHUNK + cx] = true


func _cell_range(cx: float, cz: float, r: float) -> Array:
	return [maxi(0, int(floor((cx - r + HALF) / CELL))), mini(N - 1, int(ceil((cx + r + HALF) / CELL))),
			maxi(0, int(floor((cz - r + HALF) / CELL))), mini(N - 1, int(ceil((cz + r + HALF) / CELL)))]


func _store(i: int, v: float) -> void:
	if not _locked:
		v = clampf(v, base[i] - FLOOR_DEPTH, base[i] + MAX_RAISE)
	h[i] = v


# Pull the ground up toward top_y inside a round footprint: flat on top (r_top), sloping out to r_top + r_flank.
# Never lowers anything. Returns how many cells rose. Pass `orig` (a copy of h taken before an animated raise
# began) so repeated calls with a growing top_y blend from the ORIGINAL ground instead of compounding.
func raise_mound(cx: float, cz: float, r_top: float, r_flank: float, top_y: float, rough := 0.0,
		orig := PackedFloat32Array()) -> int:
	var R := r_top + r_flank
	var rg := _cell_range(cx, cz, R)
	var n := 0
	for iz in range(rg[2], rg[3] + 1):
		for ix in range(rg[0], rg[1] + 1):
			var x := ix * CELL - HALF
			var z := iz * CELL - HALF
			var d := Vector2(x - cx, z - cz).length()
			if d >= R:
				continue
			var p := 1.0 - C.ss(r_top, R, d)
			var i := iz * N + ix
			var t := lerpf(h[i] if orig.is_empty() else orig[i], top_y, p)
			if rough > 0.0 and p < 0.98:
				t += rough * _rough.get_noise_2d(x, z) * p * (1.0 - p) * 4.0
			if t > h[i] + 0.001:
				_store(i, t)
				n += 1
	if n > 0:
		_mark(rg[0], rg[2], rg[1], rg[3])
	return n


# Same, along a segment. top_y runs from y0 at (x0,z0) to y1 at (x1,z1).
func raise_ridge(x0: float, z0: float, x1: float, z1: float, w_top: float, w_flank: float,
		y0: float, y1: float, rough := 0.0, orig := PackedFloat32Array()) -> int:
	var R := w_top + w_flank
	var a := Vector2(x0, z0)
	var b := Vector2(x1, z1)
	var ab := b - a
	var len2 := maxf(ab.length_squared(), 0.0001)
	var rg := _cell_range((x0 + x1) * 0.5, (z0 + z1) * 0.5, ab.length() * 0.5 + R)
	var n := 0
	for iz in range(rg[2], rg[3] + 1):
		for ix in range(rg[0], rg[1] + 1):
			var x := ix * CELL - HALF
			var z := iz * CELL - HALF
			var q := Vector2(x, z)
			var t := clampf((q - a).dot(ab) / len2, 0.0, 1.0)
			var d := (q - (a + ab * t)).length()
			if d >= R:
				continue
			var p := 1.0 - C.ss(w_top, R, d)
			var i := iz * N + ix
			var target := lerpf(h[i] if orig.is_empty() else orig[i], lerpf(y0, y1, t), p)
			if rough > 0.0 and p < 0.98:
				target += rough * _rough.get_noise_2d(x, z) * p * (1.0 - p) * 4.0
			if target > h[i] + 0.001:
				_store(i, target)
				n += 1
	if n > 0:
		_mark(rg[0], rg[2], rg[1], rg[3])
	return n


# Smooth bowl. Returns the total height removed (use it to size debris). Respects the dig floor.
func carve_crater(cx: float, cz: float, radius: float, depth: float) -> float:
	var rg := _cell_range(cx, cz, radius)
	var removed := 0.0
	for iz in range(rg[2], rg[3] + 1):
		for ix in range(rg[0], rg[1] + 1):
			var d := Vector2(ix * CELL - HALF - cx, iz * CELL - HALF - cz).length()
			if d >= radius:
				continue
			var i := iz * N + ix
			var p := 1.0 - C.ss(0.0, radius, d)
			var v := maxf(h[i] - depth * p, base[i] - FLOOR_DEPTH)
			removed += h[i] - v
			h[i] = v
	if removed > 0.0:
		_mark(rg[0], rg[2], rg[1], rg[3])
	return removed


# Notch a narrow groove along a segment (an air slice cutting through an earth wall).
func cut_line(x0: float, z0: float, x1: float, z1: float, half_width: float, depth: float) -> float:
	var a := Vector2(x0, z0)
	var b := Vector2(x1, z1)
	var ab := b - a
	var len2 := maxf(ab.length_squared(), 0.0001)
	var rg := _cell_range((x0 + x1) * 0.5, (z0 + z1) * 0.5, ab.length() * 0.5 + half_width)
	var removed := 0.0
	for iz in range(rg[2], rg[3] + 1):
		for ix in range(rg[0], rg[1] + 1):
			var q := Vector2(ix * CELL - HALF, iz * CELL - HALF)
			var t := clampf((q - a).dot(ab) / len2, 0.0, 1.0)
			var d := (q - (a + ab * t)).length()
			if d >= half_width:
				continue
			var i := iz * N + ix
			var v := maxf(h[i] - depth * (1.0 - C.ss(0.0, half_width, d)), base[i] - FLOOR_DEPTH)
			removed += h[i] - v
			h[i] = v
	if removed > 0.0:
		_mark(rg[0], rg[2], rg[1], rg[3])
	return removed


# Earthquake heave. The ground follows a moving noise field: each call applies the CHANGE in that field between
# phase_a and phase_b, so the ground shakes while the quake runs and is left rumpled (never runaway) afterwards.
func heave(cx: float, cz: float, radius: float, amount: float, phase_a: float, phase_b: float) -> void:
	var rg := _cell_range(cx, cz, radius)
	for iz in range(rg[2], rg[3] + 1):
		for ix in range(rg[0], rg[1] + 1):
			var x := ix * CELL - HALF
			var z := iz * CELL - HALF
			var d := Vector2(x - cx, z - cz).length()
			if d >= radius:
				continue
			var fall := 1.0 - C.ss(radius * 0.5, radius, d)
			var i := iz * N + ix
			var dn := _rough.get_noise_3d(x * 0.45, z * 0.45, phase_b) - _rough.get_noise_3d(x * 0.45, z * 0.45, phase_a)
			_store(i, h[i] + amount * fall * dn)
	_mark(rg[0], rg[2], rg[1], rg[3])


# Blur the ground inside a circle (softens terrace edges and sharp seams into hill shapes).
func smooth(cx: float, cz: float, radius: float, passes := 1) -> void:
	var rg := _cell_range(cx, cz, radius)
	for _p in range(passes):
		var src := h.duplicate()
		for iz in range(maxi(rg[2], 1), mini(rg[3], N - 2) + 1):
			for ix in range(maxi(rg[0], 1), mini(rg[1], N - 2) + 1):
				var d := Vector2(ix * CELL - HALF - cx, iz * CELL - HALF - cz).length()
				if d >= radius:
					continue
				var i := iz * N + ix
				var avg := (src[i - N - 1] + src[i - N] + src[i - N + 1] + src[i - 1] + src[i] + src[i + 1] \
						+ src[i + N - 1] + src[i + N] + src[i + N + 1]) / 9.0
				h[i] = lerpf(src[i], avg, 1.0 - C.ss(radius * 0.75, radius, d))
	_mark(rg[0], rg[2], rg[1], rg[3])


# Level ground inside r_in and blend back to the natural ground by r_out.
func flatten(cx: float, cz: float, r_in: float, r_out: float, y: float) -> void:
	var rg := _cell_range(cx, cz, r_out)
	for iz in range(rg[2], rg[3] + 1):
		for ix in range(rg[0], rg[1] + 1):
			var d := Vector2(ix * CELL - HALF - cx, iz * CELL - HALF - cz).length()
			if d >= r_out:
				continue
			var i := iz * N + ix
			_store(i, lerpf(h[i], y, 1.0 - C.ss(r_in, r_out, d)))
	_mark(rg[0], rg[2], rg[1], rg[3])


# A permanent level pad (a duel start spot): flattened to the middle's height and baked in so it never heals away.
func make_pad(cx: float, cz: float, r_in: float, r_out: float) -> void:
	var was := _locked
	_locked = true
	flatten(cx, cz, r_in, r_out, height_at(cx, cz))
	_locked = was
	var rg := _cell_range(cx, cz, r_out)
	for iz in range(rg[2], rg[3] + 1):
		for ix in range(rg[0], rg[1] + 1):
			var i := iz * N + ix
			base[i] = h[i]
			built[i] = h[i]
			active.erase(i)
	version += 1


# A mountain of stacked terraces: every ring is `rise` taller than the one outside it.
func raise_terraces(cx: float, cz: float, r_top: float, ring_w: float, rise: float, count: int, base_y: float) -> void:
	var R := r_top + ring_w * count
	var rg := _cell_range(cx, cz, R)
	for iz in range(rg[2], rg[3] + 1):
		for ix in range(rg[0], rg[1] + 1):
			var d := Vector2(ix * CELL - HALF - cx, iz * CELL - HALF - cz).length()
			if d >= R:
				continue
			var k := count if d <= r_top else mini(count, int(floor((R - d) / ring_w)))
			var i := iz * N + ix
			var t := base_y + rise * k
			if t > h[i]:
				_store(i, t)
	_mark(rg[0], rg[2], rg[1], rg[3])


# ------------------------------------------------------------------ healing

# Called every tick. Cells that nobody has touched for a while drift back toward the level as it was built:
# craters fill in from the edges, raised earth settles. Work happens ten times a second, only on edited cells.
func heal(dt: float) -> void:
	if not heal_enabled or active.is_empty():
		return
	_heal_acc += dt
	if _heal_acc < 0.1:
		return
	var step := _heal_acc
	_heal_acc = 0.0
	var moved := false
	for key in active.keys():
		var i: int = key
		if cool[i] > 0.0:
			cool[i] -= step
			continue
		var diff: float = built[i] - h[i]
		var ad := absf(diff)
		if ad < 0.01:
			h[i] = built[i]
			active.erase(i)
		else:
			var amt := minf(ad, (C.HEAL_MIN_RATE + C.HEAL_FRAC * ad) * step)
			h[i] += signf(diff) * amt
		moved = true
		var ix := i % N
		var iz := i / N
		var c0x := clampi(ix / CHUNK, 0, NCHUNK - 1)
		var c0z := clampi(iz / CHUNK, 0, NCHUNK - 1)
		dirty[c0z * NCHUNK + c0x] = true
		var lx := ix % CHUNK                          # cells on a chunk edge are also drawn by the neighbour
		var lz := iz % CHUNK
		var nx := c0x - 1 if lx == 0 else (c0x + 1 if lx == CHUNK - 1 else c0x)
		var nz := c0z - 1 if lz == 0 else (c0z + 1 if lz == CHUNK - 1 else c0z)
		if nx != c0x and nx >= 0 and nx < NCHUNK:
			dirty[c0z * NCHUNK + nx] = true
		if nz != c0z and nz >= 0 and nz < NCHUNK:
			dirty[nz * NCHUNK + c0x] = true
		if nx != c0x and nz != c0z and nx >= 0 and nx < NCHUNK and nz >= 0 and nz < NCHUNK:
			dirty[nz * NCHUNK + nx] = true
	if moved:
		version += 1


# ------------------------------------------------------------------ permanent walls and moving slabs

# Mark the ground raised along a segment as permanent (it stops healing).
func pin_ridge(x0: float, z0: float, x1: float, z1: float, reach: float, min_rise: float) -> int:
	var a := Vector2(x0, z0)
	var b := Vector2(x1, z1)
	var ab := b - a
	var len2 := maxf(ab.length_squared(), 0.0001)
	var rg := _cell_range((x0 + x1) * 0.5, (z0 + z1) * 0.5, ab.length() * 0.5 + reach)
	var n := 0
	for iz in range(rg[2], rg[3] + 1):
		for ix in range(rg[0], rg[1] + 1):
			var q := Vector2(ix * CELL - HALF, iz * CELL - HALF)
			var t := clampf((q - a).dot(ab) / len2, 0.0, 1.0)
			if (q - (a + ab * t)).length() >= reach:
				continue
			var i := iz * N + ix
			if h[i] - built[i] > min_rise:
				pinned[i] = true
				active.erase(i)
				n += 1
	return n


# Lower every pinned cell along a segment back to the original ground (a wall being picked up).
func release_ridge(x0: float, z0: float, x1: float, z1: float, reach: float) -> int:
	var a := Vector2(x0, z0)
	var b := Vector2(x1, z1)
	var ab := b - a
	var len2 := maxf(ab.length_squared(), 0.0001)
	var rg := _cell_range((x0 + x1) * 0.5, (z0 + z1) * 0.5, ab.length() * 0.5 + reach)
	var n := 0
	for iz in range(rg[2], rg[3] + 1):
		for ix in range(rg[0], rg[1] + 1):
			var q := Vector2(ix * CELL - HALF, iz * CELL - HALF)
			var t := clampf((q - a).dot(ab) / len2, 0.0, 1.0)
			if (q - (a + ab * t)).length() >= reach:
				continue
			var i := iz * N + ix
			if pinned.has(i):
				pinned.erase(i)
				h[i] = built[i]
				active.erase(i)
				n += 1
	if n > 0:
		_mark(rg[0], rg[2], rg[1], rg[3])
	return n


# Height of the tallest pinned cell near a point (0 when there is no wall): used to find walls to grab.
func pinned_near(x: float, z: float, r: float) -> bool:
	var rg := _cell_range(x, z, r)
	for iz in range(rg[2], rg[3] + 1):
		for ix in range(rg[0], rg[1] + 1):
			if pinned.has(iz * N + ix):
				return true
	return false


# Put the heights in a rectangle of cells back to a saved copy (for slabs that move).
func restore_rect(orig: PackedFloat32Array, ix0: int, iz0: int, ix1: int, iz1: int) -> void:
	ix0 = clampi(ix0, 0, N - 1)
	ix1 = clampi(ix1, 0, N - 1)
	iz0 = clampi(iz0, 0, N - 1)
	iz1 = clampi(iz1, 0, N - 1)
	for iz in range(iz0, iz1 + 1):
		for ix in range(ix0, ix1 + 1):
			var i := iz * N + ix
			h[i] = orig[i]
	_mark(ix0, iz0, ix1, iz1)


# ------------------------------------------------------------------ waterbending: flooding and ice
# Water and ice are not earth: they redraw chunks but never register cells with the healing system.

func _touch_cells(ix0: int, iz0: int, ix1: int, iz1: int) -> void:
	version += 1
	var c0x := clampi((ix0 - 1) / CHUNK, 0, NCHUNK - 1)
	var c1x := clampi((ix1 + 1) / CHUNK, 0, NCHUNK - 1)
	var c0z := clampi((iz0 - 1) / CHUNK, 0, NCHUNK - 1)
	var c1z := clampi((iz1 + 1) / CHUNK, 0, NCHUNK - 1)
	for cz in range(c0z, c1z + 1):
		for cx in range(c0x, c1x + 1):
			dirty[cz * NCHUNK + cx] = true


func _mark_wet(ix: int, iz: int) -> void:
	wet_chunks[clampi(iz / CHUNK, 0, NCHUNK - 1) * NCHUNK + clampi(ix / CHUNK, 0, NCHUNK - 1)] = true
	if ix % CHUNK == 0 and ix > 0:
		wet_chunks[clampi(iz / CHUNK, 0, NCHUNK - 1) * NCHUNK + ix / CHUNK - 1] = true
	if iz % CHUNK == 0 and iz > 0:
		wet_chunks[(iz / CHUNK - 1) * NCHUNK + clampi(ix / CHUNK, 0, NCHUNK - 1)] = true


# Water poured over the ground (a Tidal Wave's wake): the surface sits `depth` above the ground, fading to nothing at
# the rim, and it stays until something moves it. Returns how many vertices got wetter.
func flood_disc(cx: float, cz: float, radius: float, depth: float, life := -1.0) -> int:
	var rg := _cell_range(cx, cz, radius)
	var n := 0
	for iz in range(rg[2], rg[3] + 1):
		for ix in range(rg[0], rg[1] + 1):
			var d := Vector2(ix * CELL - HALF - cx, iz * CELL - HALF - cz).length()
			if d >= radius:
				continue
			var i := iz * N + ix
			if ice[i] != 0:
				continue
			var p := 1.0 - C.ss(radius * 0.5, radius, d)
			var level := h[i] + depth * p
			if p > 0.05 and level > ws[i] + 0.01:
				if life > 0.0:                          # a puddle: remember what was here so it can dry back to it
					if puddle_orig.has(i):
						(puddle_orig[i] as Dictionary)["t"] = maxf(float((puddle_orig[i] as Dictionary)["t"]), life)
					else:
						puddle_orig[i] = {"w": ws[i], "t": life}
				ws[i] = level
				_mark_wet(ix, iz)
				n += 1
	if n > 0:
		_touch_cells(rg[0], rg[2], rg[1], rg[3])
	return n


# Freeze every bit of water inside a circle into ice at the level of the water surface. Ice is solid ground you can
# stand on and skate over. It melts after C.ICE_MELT seconds and the water comes back. Returns vertices frozen.
func freeze_area(cx: float, cz: float, radius: float) -> int:
	var rg := _cell_range(cx, cz, radius)
	var n := 0
	for iz in range(rg[2], rg[3] + 1):
		for ix in range(rg[0], rg[1] + 1):
			var d := Vector2(ix * CELL - HALF - cx, iz * CELL - HALF - cz).length()
			if d >= radius:
				continue
			var i := iz * N + ix
			if ice[i] == 1:
				(ice_orig[i] as Dictionary)["t"] = C.ICE_MELT      # fresh ice: the melt timer starts over
				continue
			var w := ws[i]
			if ice[i] != 0 or w < NO_WATER * 0.5 or w - h[i] < 0.05:
				continue
			ice_orig[i] = {"h": h[i], "t": C.ICE_MELT}
			h[i] = w
			ice[i] = 1
			n += 1
	if n > 0:
		_touch_cells(rg[0], rg[2], rg[1], rg[3])
	return n


func ice_at(x: float, z: float) -> bool:
	var gx := clampi(int(round((x + HALF) / CELL)), 0, N - 1)
	var gz := clampi(int(round((z + HALF) / CELL)), 0, N - 1)
	return ice[gz * N + gx] != 0


# Is there water (or a wading-deep film of it, or ice: frozen water is still water to a waterbender) within `radius`
# of a point? Returns the nearest wet spot or null.
func nearest_water(x: float, z: float, radius: float, min_depth := 0.15):
	var best = null
	var best_d := radius
	var rg := _cell_range(x, z, radius)
	for iz in range(rg[2], rg[3] + 1):
		for ix in range(rg[0], rg[1] + 1):
			var i := iz * N + ix
			var frozen := ice[i] == 1
			if not frozen and (ws[i] < NO_WATER * 0.5 or ws[i] - h[i] < min_depth):
				continue
			var d := Vector2(ix * CELL - HALF - x, iz * CELL - HALF - z).length()
			if d < best_d:
				best_d = d
				best = Vector3(ix * CELL - HALF, h[i] if frozen else ws[i], iz * CELL - HALF)
	return best


# How much water is around a point, in square metres of "full" water: every wet or frozen vertex inside the radius
# counts by how deep it is up to 3 m, so a puddle counts a little and a lake or the sea counts a lot.
func water_amount(x: float, z: float, radius: float) -> float:
	var rg := _cell_range(x, z, radius)
	var r2 := radius * radius
	var total := 0.0
	for iz in range(rg[2], rg[3] + 1):
		for ix in range(rg[0], rg[1] + 1):
			var dx := ix * CELL - HALF - x
			var dz := iz * CELL - HALF - z
			if dx * dx + dz * dz > r2:
				continue
			var i := iz * N + ix
			if ice[i] == 1:
				total += 1.0
			elif ws[i] > NO_WATER * 0.5 and ws[i] > h[i]:
				total += minf((ws[i] - h[i]) / 3.0, 1.0)
	return total


# Called every tick: ice that has sat long enough turns back into water, and puddles dry up.
func tick_water(dt: float) -> void:
	if ice_orig.is_empty() and puddle_orig.is_empty():
		return
	_ice_acc += dt
	if _ice_acc < 0.25:
		return
	var step := _ice_acc
	_ice_acc = 0.0
	for key in ice_orig.keys():
		var e: Dictionary = ice_orig[key]
		e["t"] = float(e["t"]) - step
		if float(e["t"]) <= 0.0:
			var i: int = key
			if ice[i] == 1:
				h[i] = float(e["h"])
				ice[i] = 0
			ice_orig.erase(key)
			_touch_cells(i % N, i / N, i % N, i / N)
	for key in puddle_orig.keys():
		var pe: Dictionary = puddle_orig[key]
		pe["t"] = float(pe["t"]) - step
		if float(pe["t"]) <= 0.0:
			var pi: int = key
			if ice[pi] != 0:
				pe["t"] = 5.0                           # frozen: it dries once it has thawed
				continue
			ws[pi] = float(pe["w"])
			puddle_orig.erase(key)
			_touch_cells(pi % N, pi / N, pi % N, pi / N)


# Unfreeze: every frozen vertex inside the circle turns back into water. Returns how many thawed.
func thaw_area(cx: float, cz: float, radius: float) -> int:
	var rg := _cell_range(cx, cz, radius)
	var n := 0
	for iz in range(rg[2], rg[3] + 1):
		for ix in range(rg[0], rg[1] + 1):
			if Vector2(ix * CELL - HALF - cx, iz * CELL - HALF - cz).length() >= radius:
				continue
			var i := iz * N + ix
			if ice[i] == 1 and ice_orig.has(i):
				h[i] = float((ice_orig[i] as Dictionary)["h"])
				ice[i] = 0
				ice_orig.erase(i)
				n += 1
	if n > 0:
		_touch_cells(rg[0], rg[2], rg[1], rg[3])
	return n


# An ice wall's footprint: every cell standing clearly above the ground it was raised from becomes wall ice.
func tint_wall_cells(orig: PackedFloat32Array, ix0: int, iz0: int, ix1: int, iz1: int) -> int:
	var n := 0
	for iz in range(clampi(iz0, 0, N - 1), clampi(iz1, 0, N - 1) + 1):
		for ix in range(clampi(ix0, 0, N - 1), clampi(ix1, 0, N - 1) + 1):
			var i := iz * N + ix
			if ice[i] == 0 and h[i] - orig[i] > 0.35:
				ice[i] = 2
				n += 1
	_touch_cells(ix0, iz0, ix1, iz1)
	return n


# The wall shatters: its cells drop back to the ground they came from, and the ice tint goes with them.
func shatter_wall(orig: PackedFloat32Array, ix0: int, iz0: int, ix1: int, iz1: int) -> void:
	ix0 = clampi(ix0, 0, N - 1)
	ix1 = clampi(ix1, 0, N - 1)
	iz0 = clampi(iz0, 0, N - 1)
	iz1 = clampi(iz1, 0, N - 1)
	for iz in range(iz0, iz1 + 1):
		for ix in range(ix0, ix1 + 1):
			var i := iz * N + ix
			if ice[i] == 2:
				ice[i] = 0
				if h[i] > orig[i]:
					h[i] = orig[i]
	_mark(ix0, iz0, ix1, iz1)
