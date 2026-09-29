extends SceneTree
## Draws the small combat textures the weapon and impact effects use: the muzzle
## flash star, the smoke puff, the spark dot, and three bullet-hole decals with a
## shared dent normal map. Run once; the PNGs are committed.
##   Godot --headless --path . --script res://tools/generate_fx_textures.gd

const OUT := "res://assets/weapon/fx/"


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_flash()
	_smoke()
	_spark()
	_hole("hole_snow", Color(0.05, 0.08, 0.13), Color(0.95, 0.98, 1.0), 0.26, 11)
	_hole("hole_rock", Color(0.04, 0.04, 0.045), Color(0.92, 0.9, 0.86), 0.34, 23)
	_hole("hole_wood", Color(0.05, 0.03, 0.02), Color(0.9, 0.66, 0.38), 0.36, 37)
	_hole_normal()
	quit()


func _save(image: Image, name: String) -> void:
	var path := ProjectSettings.globalize_path(OUT + name + ".png")
	var error := image.save_png(path)
	print("saved ", path, " ", error)


func _flash() -> void:
	var size := 160
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4417
	var spikes: Array = []
	for i in 9:
		spikes.append({"angle": rng.randf() * TAU, "length": rng.randf_range(0.42, 1.0), "width": rng.randf_range(0.05, 0.12)})
	var centre := Vector2(size, size) * 0.5
	for y in size:
		for x in size:
			var p := (Vector2(x, y) - centre) / (size * 0.5)
			var r := p.length()
			var angle := atan2(p.y, p.x)
			var v := exp(-r * r * 26.0) * 1.3
			for spike in spikes:
				var d := absf(fposmod(angle - spike.angle + PI, TAU) - PI)
				var reach := clampf(1.0 - r / spike.length, 0.0, 1.0)
				v += exp(-d * d / (spike.width * spike.width) * (0.6 + r * 2.0)) * reach * reach * 0.95
			v = clampf(v, 0.0, 1.0)
			var heat := Color(1.0, 0.62 + v * 0.38, 0.28 + v * 0.62)
			image.set_pixel(x, y, Color(heat.r * v, heat.g * v, heat.b * v, v))
	_save(image, "muzzle_flash")


func _smoke() -> void:
	var size := 128
	var noise := FastNoiseLite.new()
	noise.seed = 91
	noise.frequency = 0.045
	noise.fractal_octaves = 4
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var p := (Vector2(x, y) - Vector2(size, size) * 0.5) / (size * 0.5)
			var edge := clampf(1.0 - p.length(), 0.0, 1.0)
			var n := noise.get_noise_2d(x, y) * 0.5 + 0.5
			var a := clampf(edge * (0.5 + n * 0.9), 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)
			image.set_pixel(x, y, Color(0.86, 0.88, 0.92, a))
	_save(image, "smoke_puff")


func _spark() -> void:
	var size := 32
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var r := (Vector2(x, y) - Vector2(size, size) * 0.5).length() / (size * 0.5)
			var a := clampf(1.0 - r, 0.0, 1.0)
			a *= a
			image.set_pixel(x, y, Color(1.0, 0.9, 0.7, a))
	_save(image, "spark_dot")


## A dark crater with a lighter broken rim and a few radial cracks.
func _hole(name: String, core: Color, rim: Color, hole_radius: float, seed_value: int) -> void:
	var size := 96
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.09
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var cracks: Array = []
	for i in 6:
		cracks.append({"angle": rng.randf() * TAU, "length": rng.randf_range(0.6, 0.95)})
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var p := (Vector2(x, y) - Vector2(size, size) * 0.5) / (size * 0.5)
			var r := p.length()
			var angle := atan2(p.y, p.x)
			var ragged := hole_radius * (0.75 + noise.get_noise_2d(x, y) * 0.5 + 0.25 * sin(angle * 5.0 + seed_value))
			var color := core
			var alpha := 0.0
			if r < ragged:
				alpha = 0.96
				color = core.darkened(clampf(1.0 - r / ragged, 0.0, 1.0) * 0.6)
			elif r < ragged + 0.22:
				var t := (r - ragged) / 0.22
				alpha = (1.0 - t * t) * 0.92
				color = core.lerp(rim, 0.9 - t * 0.3)
			var soot := clampf(1.0 - r, 0.0, 1.0)
			alpha = maxf(alpha, soot * soot * 0.32)
			for crack in cracks:
				var d := absf(fposmod(angle - crack.angle + PI, TAU) - PI)
				if d < 0.05 and r > ragged and r < crack.length * 0.9:
					alpha = maxf(alpha, 0.6 * (1.0 - r))
					color = core.lerp(rim, 0.2)
			image.set_pixel(x, y, Color(color.r, color.g, color.b, clampf(alpha, 0.0, 1.0) * clampf((1.0 - r) * 4.0, 0.0, 1.0)))
	_save(image, name)


## Shallow dent: the rim rises slightly and the centre drops.
func _hole_normal() -> void:
	var size := 96
	var heights := PackedFloat32Array()
	heights.resize(size * size)
	for y in size:
		for x in size:
			var r := (Vector2(x, y) - Vector2(size, size) * 0.5).length() / (size * 0.5)
			var dent := -exp(-pow(r / 0.36, 2.0) * 2.0)
			var lip := exp(-pow((r - 0.5) / 0.14, 2.0)) * 0.35
			heights[y * size + x] = (dent + lip) * clampf(1.0 - r, 0.0, 1.0) * 2.4
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var left := heights[y * size + maxi(x - 1, 0)]
			var right := heights[y * size + mini(x + 1, size - 1)]
			var up := heights[maxi(y - 1, 0) * size + x]
			var down := heights[mini(y + 1, size - 1) * size + x]
			var normal := Vector3((left - right) * 6.0, (up - down) * 6.0, 1.0).normalized()
			image.set_pixel(x, y, Color(normal.x * 0.5 + 0.5, normal.y * 0.5 + 0.5, normal.z * 0.5 + 0.5, 1.0))
	_save(image, "hole_normal")
