extends Node3D
## Draws the deformable terrain as a grid of chunk meshes. Chunks that the simulation edited are rebuilt
## a few per frame, so earthbending and craters show up live without hitching.

const C = preload("res://scripts/config.gd")
const TerrainScript = preload("res://scripts/terrain.gd")

var terrain
var rebuilt := 0                    # total chunk rebuilds (tests look at this)
var _chunks: Array = []             # MeshInstance3D per chunk
var _queue := {}
var _mat: StandardMaterial3D
var _cn := FastNoiseLite.new()
var _water_chunks: Array = []       # MeshInstance3D per chunk (mesh only where water touches the chunk)
var _water_mat: ShaderMaterial
var _chunk_indices := PackedInt32Array()
const REBUILD_MSEC := 2.5            # a frame spends at most about this long rebuilding edited chunks (one always goes)

const WATER_SRC := "
shader_type spatial;
render_mode blend_mix, cull_disabled, specular_schlick_ggx, depth_draw_never;
varying vec3 wpos;
varying float depth;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	depth = COLOR.a * 12.0;
}
void fragment() {
	float t = TIME;
	vec2 p = wpos.xz;
	float dx = cos(p.x * 0.35 + t * 0.9) * 0.35 + cos((p.x + p.y) * 0.8 + t * 1.7) * 0.5 + cos((p.x - p.y) * 1.3 - t * 1.1) * 0.35;
	float dz = cos(p.y * 0.29 - t * 0.7) * 0.29 + cos((p.x + p.y) * 0.8 + t * 1.7) * 0.5 - cos((p.x - p.y) * 1.3 - t * 1.1) * 0.35;
	vec3 nw = normalize(vec3(-dx * 0.06, 1.0, -dz * 0.06));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	float k = 1.0 - exp(-depth * 0.32);
	vec3 shallow = vec3(0.22, 0.60, 0.62);
	vec3 deep = vec3(0.04, 0.20, 0.38);
	vec3 col = mix(shallow, deep, k);
	float foam = 1.0 - smoothstep(0.0, 0.4, depth);
	float rip = 0.55 + 0.45 * sin(depth * 16.0 - t * 2.2 + p.x * 0.7 + p.y * 0.5);
	col = mix(col, vec3(0.95, 0.99, 1.0), foam * rip * 0.6);
	ALBEDO = col;
	ALPHA = clamp(mix(0.30, 0.90, 1.0 - exp(-depth * 0.9)) + foam * rip * 0.35, 0.0, 0.95);
	ROUGHNESS = 0.06;
	SPECULAR = 0.8;
}
"



func setup(t) -> void:
	terrain = t
	_cn.frequency = 0.09
	_mat = StandardMaterial3D.new()
	_mat.vertex_color_use_as_albedo = true
	_mat.vertex_color_is_srgb = true
	_mat.roughness = 1.0
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var wsh := Shader.new()
	wsh.code = WATER_SRC
	_water_mat = ShaderMaterial.new()
	_water_mat.shader = wsh
	for cz in range(TerrainScript.NCHUNK):
		for cx in range(TerrainScript.NCHUNK):
			var mi := MeshInstance3D.new()
			mi.mesh = ArrayMesh.new()
			mi.material_override = _mat
			add_child(mi)
			_chunks.append(mi)
			var wi := MeshInstance3D.new()
			wi.material_override = _water_mat
			wi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(wi)
			_water_chunks.append(wi)
			_build_chunk(cx, cz)
	_build_ocean()
	terrain.take_dirty()


# Chunks further than `metres` from the camera are not drawn (the fog hides the edge). 0 = draw everything.
func set_view_range(metres: float) -> void:
	for mi in _chunks:
		(mi as MeshInstance3D).visibility_range_end = metres
	for wi in _water_chunks:
		(wi as MeshInstance3D).visibility_range_end = metres


# Rebuild up to `budget` queued chunks. Returns how many are still waiting.
func update(budget: int = 3) -> int:
	for k in terrain.take_dirty():
		_queue[k] = true
	var n := 0
	var t0 := Time.get_ticks_usec()
	for k in _queue.keys():
		if n >= budget or (n > 0 and budget < 50 and float(Time.get_ticks_usec() - t0) > REBUILD_MSEC * 1000.0):
			break
		_build_chunk(int(k) % TerrainScript.NCHUNK, int(k) / TerrainScript.NCHUNK)
		_queue.erase(k)
		n += 1
	return _queue.size()


func flush() -> void:
	while update(100) > 0:
		pass


func _color(x: float, z: float, y: float, ny: float, i: int) -> Color:
	var grass_a := Color(0.24, 0.42, 0.17)
	var grass_b := Color(0.33, 0.52, 0.2)
	var rock := Color(0.40, 0.36, 0.30)
	var sand := Color(0.80, 0.72, 0.52)
	var raw_earth := Color(0.40, 0.27, 0.16)
	var raw_rock := Color(0.48, 0.44, 0.38)
	var scorch := Color(0.27, 0.24, 0.21)
	var c := grass_a.lerp(grass_b, _cn.get_noise_2d(x, z) * 0.5 + 0.5)
	var wsv: float = terrain.ws[i]
	var wet: bool = wsv > -1.0e8 and wsv > y
	var shore := 0.0
	if not wet:
		var nw := 0
		var ixx: int = i % TerrainScript.N
		var izz: int = i / TerrainScript.N
		if ixx > 0 and terrain.ws[i - 1] > -1.0e8: nw += 1
		if ixx < TerrainScript.N - 1 and terrain.ws[i + 1] > -1.0e8: nw += 1
		if izz > 0 and terrain.ws[i - TerrainScript.N] > -1.0e8: nw += 1
		if izz < TerrainScript.N - 1 and terrain.ws[i + TerrainScript.N] > -1.0e8: nw += 1
		shore = 1.0 if nw > 0 else 0.0
		shore = maxf(shore, C.ss(TerrainScript.SEA_Y + 1.6, TerrainScript.SEA_Y + 0.2, y))
	c = c.lerp(sand, shore * 0.9)
	if wet:
		var dd := clampf((wsv - y) / 6.0, 0.0, 1.0)
		c = sand.lerp(Color(0.18, 0.30, 0.34), dd)
	c = c.lerp(rock, clampf(C.ss(0.78, 0.58, ny) + C.ss(10.0, 20.0, y) * 0.45, 0.0, 1.0))
	var d: float = y - terrain.built[i]
	if d > 0.15:                                # freshly raised earth
		var e := raw_earth.lerp(raw_rock, clampf(C.ss(0.95, 0.7, ny) + C.ss(2.5, 7.0, d) * 0.4, 0.0, 1.0))
		c = c.lerp(e, C.ss(0.1, 0.9, d))
	elif d < -0.15:                             # craters and scoured ground
		c = c.lerp(scorch, C.ss(0.1, 1.2, -d) * 0.85)
	var ice_kind: int = terrain.ice[i]
	if ice_kind != 0:                           # frozen water (pale, mottled) and ice walls (deeper blue)
		var mott := _cn.get_noise_2d(x * 2.3, z * 2.3) * 0.5 + 0.5
		var ice_col := Color(0.80, 0.91, 0.98).lerp(Color(0.62, 0.80, 0.95), mott * 0.7) if ice_kind == 1 \
				else Color(0.55, 0.78, 0.97).lerp(Color(0.80, 0.93, 1.0), mott * 0.6)
		c = c.lerp(ice_col, 0.94)
	return c


func _build_chunk(cx: int, cz: int) -> void:
	var n: int = TerrainScript.CHUNK
	var w := n + 1
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	verts.resize(w * w)
	normals.resize(w * w)
	colors.resize(w * w)
	var ix0 := cx * n
	var iz0 := cz * n
	for j in range(w):
		for i in range(w):
			var ix := ix0 + i
			var iz := iz0 + j
			var gi: int = iz * TerrainScript.N + ix
			var x: float = ix * TerrainScript.CELL - TerrainScript.HALF
			var z: float = iz * TerrainScript.CELL - TerrainScript.HALF
			var y: float = terrain.h[gi]
			var nrm: Vector3 = terrain.vertex_normal(ix, iz)
			var k := j * w + i
			verts[k] = Vector3(x, y, z)
			normals[k] = nrm
			colors[k] = _color(x, z, y, nrm.y, gi)
	if _chunk_indices.is_empty():                       # the same for every chunk: built once
		var idx := PackedInt32Array()
		idx.resize(n * n * 6)
		var q := 0
		for j in range(n):
			for i in range(n):
				var i0 := j * w + i
				var i1 := i0 + 1
				var i2 := i0 + w
				var i3 := i2 + 1
				idx[q] = i0
				idx[q + 1] = i1
				idx[q + 2] = i2
				idx[q + 3] = i1
				idx[q + 4] = i3
				idx[q + 5] = i2
				q += 6
		_chunk_indices = idx
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = _chunk_indices
	var mi: MeshInstance3D = _chunks[cz * TerrainScript.NCHUNK + cx]
	var mesh := mi.mesh as ArrayMesh
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	rebuilt += 1
	_build_water(cx, cz)


func _build_water(cx: int, cz: int) -> void:
	var wi: MeshInstance3D = _water_chunks[cz * TerrainScript.NCHUNK + cx]
	if not terrain.wet_chunks.has(cz * TerrainScript.NCHUNK + cx):
		wi.mesh = null
		return
	var n: int = TerrainScript.CHUNK
	var w := n + 1
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	verts.resize(w * w)
	normals.resize(w * w)
	colors.resize(w * w)
	var any_depth := false
	for j in range(w):
		for i in range(w):
			var ix := cx * n + i
			var iz := cz * n + j
			var gi: int = iz * TerrainScript.N + ix
			var hv: float = terrain.h[gi]
			var sv: float = terrain.ws[gi]
			var d := maxf(sv - hv, 0.0)
			var yv := sv
			if sv < -1.0e8:                     # no water here: borrow the level of a wet neighbour so the sheet stays flat
				yv = hv
				var nbest := -1.0e9
				if ix > 0: nbest = maxf(nbest, terrain.ws[gi - 1])
				if ix < TerrainScript.N - 1: nbest = maxf(nbest, terrain.ws[gi + 1])
				if iz > 0: nbest = maxf(nbest, terrain.ws[gi - TerrainScript.N])
				if iz < TerrainScript.N - 1: nbest = maxf(nbest, terrain.ws[gi + TerrainScript.N])
				if nbest > -1.0e8:
					yv = minf(nbest, hv + 0.4)
			var k := j * w + i
			verts[k] = Vector3(ix * TerrainScript.CELL - TerrainScript.HALF, yv, iz * TerrainScript.CELL - TerrainScript.HALF)
			normals[k] = Vector3.UP
			colors[k] = Color(1, 1, 1, clampf(d / 12.0, 0.0, 1.0))
			if d > 0.0:
				any_depth = true
	if not any_depth:
		wi.mesh = null
		return
	var indices := PackedInt32Array()
	for j in range(n):
		for i in range(n):
			var i0 := j * w + i
			var i1 := i0 + 1
			var i2 := i0 + w
			var i3 := i2 + 1
			if colors[i0].a <= 0.0 and colors[i1].a <= 0.0 and colors[i2].a <= 0.0 and colors[i3].a <= 0.0:
				continue
			indices.append_array(PackedInt32Array([i0, i1, i2, i1, i3, i2]))
	if indices.is_empty():
		wi.mesh = null
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	wi.mesh = mesh


# The open sea around the map: a big frame of water at sea level, deep everywhere.
func _build_ocean() -> void:
	var inner := TerrainScript.HALF
	var outer := 1600.0
	var y := TerrainScript.SEA_Y
	var verts := PackedVector3Array([
		Vector3(-outer, y, -outer), Vector3(outer, y, -outer), Vector3(outer, y, outer), Vector3(-outer, y, outer),
		Vector3(-inner, y, -inner), Vector3(inner, y, -inner), Vector3(inner, y, inner), Vector3(-inner, y, inner)])
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for k in range(8):
		normals.append(Vector3.UP)
		colors.append(Color(1, 1, 1, 1.0))
	var idx := PackedInt32Array()
	for e in range(4):
		var a := e
		var b := (e + 1) % 4
		idx.append_array(PackedInt32Array([a, b, 4 + a, b, 4 + b, 4 + a]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _water_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
