extends SceneTree
## Generates the projected-decal textures (RGBA albedo with a real soft alpha,
## plus normals) used for footprints, blood, scorch and dirty snow. All shapes
## are procedural, so they can be regenerated deterministically.
## Usage: Godot --headless --path . --script res://tools/build_decals.gd

const OUT := "res://assets/materials/decals/"

var _noise := FastNoiseLite.new()
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_noise.seed = 31
	_noise.frequency = 6.0
	_noise.fractal_octaves = 4
	_rng.seed = 77
	_footprint()
	_paw()
	_blood_splat()
	_blood_drag()
	_scorch()
	_dirty_patch()
	_ice_sheen()
	quit()


func _n(x: float, y: float, scale := 1.0) -> float:
	return _noise.get_noise_2d(x * scale, y * scale) * 0.5 + 0.5


func _save(image: Image, name: String, normal_strength := 0.0, normal_blur := 2) -> void:
	image.save_png(OUT + name + "_albedo.png")
	if normal_strength > 0.0:
		_save_normal(image, name, normal_strength, normal_blur)
	print("built ", name)


## Height = alpha, so prints and splatter press into (or stand proud of) the snow.
func _save_normal(image: Image, name: String, strength: float, blur: int) -> void:
	var w := image.get_width()
	var h := image.get_height()
	var height := PackedFloat32Array()
	height.resize(w * h)
	for y in h:
		for x in w:
			height[y * w + x] = image.get_pixel(x, y).a
	var soft := height.duplicate()
	for y in h:
		for x in w:
			var sum := 0.0
			var count := 0
			for oy in range(-blur, blur + 1):
				for ox in range(-blur, blur + 1):
					sum += height[clampi(y + oy, 0, h - 1) * w + clampi(x + ox, 0, w - 1)]
					count += 1
			soft[y * w + x] = sum / count
	var normal := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var dx := soft[y * w + mini(x + 1, w - 1)] - soft[y * w + maxi(x - 1, 0)]
			var dy := soft[mini(y + 1, h - 1) * w + x] - soft[maxi(y - 1, 0) * w + x]
			var n := Vector3(-dx * strength, dy * strength, 1.0).normalized()
			normal.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5, 1.0))
	normal.save_png(OUT + name + "_normal.png")


func _rounded_box(p: Vector2, center: Vector2, half: Vector2, radius: float) -> float:
	var q := (p - center).abs() - half + Vector2(radius, radius)
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - radius


## A single boot sole: toe box, instep gap, heel, and cross-cut lugs.
func _footprint() -> void:
	var w := 128
	var h := 256
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var p := Vector2(float(x) / w, float(y) / h)
			var sq := Vector2(p.x, p.y * 2.0)
			var sole := _rounded_box(sq, Vector2(0.5, 0.62), Vector2(0.27, 0.5), 0.2)
			var heel := _rounded_box(sq, Vector2(0.5, 1.62), Vector2(0.23, 0.22), 0.14)
			var d := minf(sole, heel)
			d += (_n(p.x, p.y, 9.0) - 0.5) * 0.05
			var lug := 0.5 + 0.5 * sin(p.y * 96.0)
			var alpha := smoothstep(0.03, -0.02, d)
			alpha *= 1.0 - smoothstep(0.55, 0.85, lug) * 0.4 * smoothstep(0.0, -0.1, d)
			image.set_pixel(x, y, Color(0.16, 0.13, 0.12, alpha * 0.85))
	_save(image, "footprint", 6.0, 2)


## A wolverine paw: pad with four toes.
func _paw() -> void:
	var size := 128
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var toes := [Vector2(0.3, 0.3), Vector2(0.43, 0.2), Vector2(0.57, 0.2), Vector2(0.7, 0.3)]
	for y in size:
		for x in size:
			var p := Vector2(float(x) / size, float(y) / size)
			var d := (p - Vector2(0.5, 0.62)).length() - 0.2
			for toe in toes:
				d = minf(d, (p - toe).length() - 0.075)
			d += (_n(p.x, p.y, 8.0) - 0.5) * 0.04
			image.set_pixel(x, y, Color(0.16, 0.14, 0.14, smoothstep(0.02, -0.015, d) * 0.8))
	_save(image, "paw", 5.0, 2)


func _blood_splat() -> void:
	var size := 256
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var drops: Array = []
	for i in 26:
		var angle := _rng.randf() * TAU
		var dist := _rng.randf_range(0.28, 0.46)
		drops.append([Vector2(0.5, 0.5) + Vector2(cos(angle), sin(angle)) * dist, _rng.randf_range(0.008, 0.032), angle])
	for y in size:
		for x in size:
			var p := Vector2(float(x) / size, float(y) / size)
			var r := (p - Vector2(0.5, 0.5)).length() * 2.0
			var n := _n(p.x, p.y, 1.6)
			var core := smoothstep(0.62, 0.3, r + (n - 0.5) * 0.65)
			var a := core
			for drop in drops:
				var to: Vector2 = p - drop[0]
				var dir := Vector2(cos(drop[2]), sin(drop[2]))
				var along := to.dot(dir) * 0.55
				var across := to.dot(Vector2(-dir.y, dir.x))
				a = maxf(a, smoothstep(drop[1], drop[1] * 0.4, Vector2(along, across).length()))
			var shade := 0.6 + 0.6 * _n(p.x + 3.0, p.y, 4.0)
			image.set_pixel(x, y, Color(0.26 * shade, 0.012, 0.01, clampf(a, 0.0, 1.0) * 0.88))
	_save(image, "blood_splat", 2.5, 3)


func _blood_drag() -> void:
	var w := 512
	var h := 128
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var u := float(x) / w
			var v := float(y) / h
			var centre := 0.5 + sin(u * 7.0) * 0.06
			var width := (0.1 + 0.07 * _n(u, 0.3, 3.0)) * sin(u * PI)
			var d := absf(v - centre) - width
			d += (_n(u, v, 7.0) - 0.5) * 0.09
			var breakup := smoothstep(0.25, 0.6, _n(u, v, 4.0))
			var a := smoothstep(0.03, -0.03, d) * lerpf(0.35, 1.0, breakup)
			image.set_pixel(x, y, Color(0.24, 0.012, 0.01, a * 0.85))
	_save(image, "blood_drag", 2.5, 3)


func _scorch() -> void:
	var size := 256
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var p := Vector2(float(x) / size, float(y) / size)
			var to := p - Vector2(0.5, 0.5)
			var r := to.length() * 2.0
			var angle := atan2(to.y, to.x)
			var streak := _n(cos(angle) * 0.8 + 3.0, sin(angle) * 0.8, 3.0)
			var a := smoothstep(0.98, 0.1, r + (streak - 0.5) * 0.22 + (_n(p.x, p.y, 3.0) - 0.5) * 0.5)
			var soot := 0.5 + 0.5 * _n(p.x, p.y, 10.0)
			image.set_pixel(x, y, Color(0.028 * soot + 0.01, 0.026 * soot + 0.01, 0.03 * soot + 0.012, clampf(a, 0.0, 1.0) * 0.9))
	_save(image, "scorch", 1.8, 4)


func _dirty_patch() -> void:
	var size := 256
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var p := Vector2(float(x) / size, float(y) / size)
			var r := (p - Vector2(0.5, 0.5)).length() * 2.0
			var n := _n(p.x, p.y, 2.0)
			var a := smoothstep(1.0, 0.2, r + (n - 0.5) * 0.9)
			var speck := smoothstep(0.55, 0.75, _n(p.x + 9.0, p.y, 14.0))
			a *= 0.35 + speck * 0.65
			var tone := 0.5 + 0.5 * _n(p.x, p.y + 4.0, 6.0)
			image.set_pixel(x, y, Color(0.2 * tone + 0.05, 0.17 * tone + 0.05, 0.15 * tone + 0.05, clampf(a, 0.0, 1.0) * 0.7))
	_save(image, "dirty_patch", 1.2, 3)


## Glossy black ice: dark blue body with pale crack lines. Roughness comes from
## the material's ORM constant, so only albedo and normal are stored here.
func _ice_sheen() -> void:
	var size := 256
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var cracks := FastNoiseLite.new()
	cracks.seed = 5
	cracks.frequency = 5.0
	cracks.fractal_octaves = 2
	for y in size:
		for x in size:
			var p := Vector2(float(x) / size, float(y) / size)
			var r := (p - Vector2(0.5, 0.5)).length() * 2.0
			var n := _n(p.x, p.y, 2.2)
			var body := smoothstep(0.98, 0.35, r + (n - 0.5) * 0.7)
			var line := 1.0 - smoothstep(0.0, 0.028, absf(cracks.get_noise_2d(p.x * 40.0, p.y * 40.0)))
			var colour := Color(0.03, 0.06, 0.1).lerp(Color(0.5, 0.65, 0.8), line * 0.7)
			image.set_pixel(x, y, Color(colour.r, colour.g, colour.b, clampf(body * (0.55 + line * 0.3), 0.0, 1.0)))
	_save(image, "ice_sheen", 1.5, 2)
