extends SceneTree
## Turns the raw Higgsfield texture generations into game-ready PBR sets:
## resized to 1024, made seamless with a half-offset cross-fade, and given a
## Sobel normal map and a luma-driven roughness map.
## Usage: Godot --headless --path . --script res://tools/build_surface_textures.gd
## Raw generations are read from the folder given as the first user argument
## (they are not kept in the repo); a second argument limits the run to one set.

const DIR := "res://assets/materials/generated/"
const SIZE := 1024

## name, normal strength, roughness at dark pixels, roughness at bright pixels, seam blend width
const SETS := [
	["frost_slate", 3.2, 0.92, 0.62, 0.12],
	["carrion_sandstone", 3.8, 0.97, 0.78, 0.12],
	["iron_plate", 3.0, 0.78, 0.42, 0.12],
	["abbey_masonry", 4.2, 0.98, 0.8, 0.12],
	["banner_cloth", 2.4, 0.95, 0.85, 0.12],
	["cracked_ice", 2.0, 0.18, 0.5, 0.12],
	["dirty_snow", 2.6, 0.9, 0.7, 0.12],
	["iron_bound_timber", 3.0, 0.95, 0.72, 0.12],
	["bell_bronze", 3.4, 0.7, 0.3, 0.12],
]


var _raw_dir := ""


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	_raw_dir = args[0]
	for spec in SETS:
		if args.size() > 1 and spec[0] != args[1]:
			continue
		_build(spec)
	quit()


func _luma(c: Color) -> float:
	return c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722


func _seamless(source: Image, blend: float) -> Image:
	var w := source.get_width()
	var h := source.get_height()
	var out := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		var v := float(y) / h
		var wy := smoothstep(0.0, blend, minf(v, 1.0 - v))
		for x in w:
			var u := float(x) / w
			var wx := smoothstep(0.0, blend, minf(u, 1.0 - u))
			var weight := wx * wy
			var a := source.get_pixel(x, y)
			var b := source.get_pixel((x + w / 2) % w, (y + h / 2) % h)
			out.set_pixel(x, y, b.lerp(a, weight))
	return out


func _build(spec: Array) -> void:
	var name: String = spec[0]
	var raw := Image.load_from_file(_raw_dir + "/" + name + ".png")
	if raw == null:
		push_error("missing raw " + name)
		return
	raw.convert(Image.FORMAT_RGB8)
	raw.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
	var albedo := _seamless(raw, spec[4])
	var height := PackedFloat32Array()
	height.resize(SIZE * SIZE)
	for y in SIZE:
		for x in SIZE:
			height[y * SIZE + x] = _luma(albedo.get_pixel(x, y))
	# A light blur keeps the Sobel from amplifying JPEG grain into noise.
	var soft := height.duplicate()
	for y in SIZE:
		for x in SIZE:
			var sum := 0.0
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					sum += height[((y + oy + SIZE) % SIZE) * SIZE + (x + ox + SIZE) % SIZE]
			soft[y * SIZE + x] = sum / 9.0
	var normal := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var rough := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var strength: float = spec[1]
	for y in SIZE:
		for x in SIZE:
			var xm := (x - 1 + SIZE) % SIZE
			var xp := (x + 1) % SIZE
			var ym := (y - 1 + SIZE) % SIZE
			var yp := (y + 1) % SIZE
			var dx := (soft[ym * SIZE + xp] + 2.0 * soft[y * SIZE + xp] + soft[yp * SIZE + xp]) - (soft[ym * SIZE + xm] + 2.0 * soft[y * SIZE + xm] + soft[yp * SIZE + xm])
			var dy := (soft[yp * SIZE + xm] + 2.0 * soft[yp * SIZE + x] + soft[yp * SIZE + xp]) - (soft[ym * SIZE + xm] + 2.0 * soft[ym * SIZE + x] + soft[ym * SIZE + xp])
			# OpenGL convention: +Y up in tangent space, image y grows downward.
			var n := Vector3(-dx * strength, dy * strength, 1.0).normalized()
			normal.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5))
			var r := lerpf(spec[2], spec[3], clampf(height[y * SIZE + x] * 1.6 - 0.15, 0.0, 1.0))
			rough.set_pixel(x, y, Color(r, r, r))
	albedo.save_jpg(DIR + name + "_albedo.jpg", 0.93)
	normal.save_jpg(DIR + name + "_normal.jpg", 0.95)
	rough.save_jpg(DIR + name + "_rough.jpg", 0.9)
	print("built ", name)
