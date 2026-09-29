class_name SurfaceLibrary
extends RefCounted
## One shared family of triplanar PBR materials for every piece of architecture
## and prop in the world. The imported GLBs still carry their own (often flat)
## materials; `upgrade()` swaps them by name so a rebuilt mesh never needs its
## textures re-authored, and `prop_material()` does the same for Kenney kit meshes.

const ARCHITECTURE := preload("res://assets/materials/architecture.gdshader")
const STAIN := preload("res://assets/materials/stain.gdshader")

const GENERATED := "res://assets/materials/generated/%s_%s.jpg"
const POLYHAVEN := "res://assets/materials/polyhaven/%s/%s_%s_1k.jpg"

const SUFFIX := {"albedo": "diff", "normal": "nor_gl", "rough": "rough"}

static var _cache := {}

## Each preset: albedo/normal/rough maps, tint, tile scale (tiles per metre),
## roughness range, metallic and how much dirty snow settles on upward faces.
static func _presets() -> Dictionary:
	return {
		"slate": {"maps": "frost_slate", "tint": Color(0.95, 0.95, 0.98), "scale": 0.42, "frost": 0.55, "rough": Vector2(0.5, 1.0), "saturation": 0.55, "carrion": Color(1.7, 0.95, 0.85), "crown": Color(0.78, 0.78, 0.82)},
		"slate_dark": {"maps": "frost_slate", "tint": Color(0.62, 0.62, 0.66), "scale": 0.36, "frost": 0.4, "rough": Vector2(0.55, 1.0), "saturation": 0.35, "carrion": Color(1.25, 0.95, 0.9), "crown": Color(0.85, 0.85, 0.9)},
		"cut": {"maps": "frost_slate", "tint": Color(0.16, 0.16, 0.17), "scale": 0.5, "frost": 0.0, "rough": Vector2(0.8, 1.0), "saturation": 0.0},
		"recess": {"maps": "frost_slate", "tint": Color(0.3, 0.32, 0.4), "scale": 0.3, "frost": 0.0, "rough": Vector2(0.8, 1.0), "saturation": 0.4},
		"limestone": {"maps": "ph:sandstone_cracks", "tint": Color(0.5, 0.53, 0.62), "scale": 0.32, "frost": 0.5, "rough": Vector2(0.7, 1.0), "saturation": 0.3},
		"limestone_dark": {"maps": "ph:sandstone_cracks", "tint": Color(0.34, 0.37, 0.46), "scale": 0.3, "frost": 0.3, "rough": Vector2(0.75, 1.0), "saturation": 0.3},
		"rock": {"maps": "ph:rock_face_03", "tint": Color(0.5, 0.54, 0.64), "scale": 0.22, "frost": 0.55, "rough": Vector2(0.6, 1.0), "saturation": 0.55, "carrion": Color(1.5, 0.85, 0.75), "crown": Color(0.65, 0.65, 0.7)},
		"red_stone": {"maps": "ph:cracked_red_ground", "tint": Color(0.62, 0.34, 0.3), "scale": 0.45, "frost": 0.3, "rough": Vector2(0.8, 1.0)},
		"scorched_masonry": {"maps": "abbey_masonry", "tint": Color(0.68, 0.68, 0.74), "scale": 0.24, "frost": 0.3, "rough": Vector2(0.8, 1.0), "saturation": 0.6},
		"iron": {"maps": "iron_plate", "tint": Color(0.85, 0.85, 0.9), "scale": 0.62, "frost": 0.0, "rough": Vector2(0.3, 0.9), "metallic": 0.55},
		"timber": {"maps": "iron_bound_timber", "tint": Color(1.15, 1.08, 1.05), "scale": 0.55, "frost": 0.2, "rough": Vector2(0.6, 1.0)},
		"bark": {"maps": "bark", "tint": Color(0.92, 0.8, 0.72), "scale": 0.7, "frost": 0.15, "rough": Vector2(0.7, 1.0)},
		"hide": {"maps": "banner_cloth", "tint": Color(0.3, 0.24, 0.22), "scale": 0.9, "frost": 0.0, "rough": Vector2(0.75, 1.0)},
		"banner": {"maps": "banner_cloth", "tint": Color(1.0, 0.95, 0.95), "scale": 0.7, "frost": 0.0, "rough": Vector2(0.8, 1.0)},
		"bellthorn": {"maps": "banner_cloth", "tint": Color(0.55, 0.07, 0.09), "scale": 1.6, "frost": 0.0, "rough": Vector2(0.55, 0.9)},
		"bronze": {"maps": "bell_bronze", "tint": Color(1.0, 0.95, 0.9), "scale": 0.7, "frost": 0.0, "rough": Vector2(0.28, 0.75), "metallic": 0.82},
		"bone": {"maps": "ph:sandstone_cracks", "tint": Color(0.78, 0.74, 0.62), "scale": 2.4, "frost": 0.0, "rough": Vector2(0.55, 0.9), "saturation": 0.45},
		"ice": {"maps": "cracked_ice", "tint": Color(0.55, 0.7, 0.85), "scale": 0.5, "frost": 0.0, "rough": Vector2(0.06, 0.4)},
		"snow_patch": {"maps": "dirty_snow", "tint": Color(0.7, 0.78, 0.9), "scale": 0.7, "frost": 0.0, "rough": Vector2(0.65, 0.95)},
	}


static func _tex(spec: String, kind: String) -> Texture2D:
	if spec.begins_with("ph:"):
		var id := spec.substr(3)
		return load(POLYHAVEN % [id, id, SUFFIX[kind]])
	if spec == "bark":
		return load("res://assets/materials/polyhaven/pine_tree_01/bark_%s_1k.jpg" % SUFFIX[kind])
	return load(GENERATED % [spec, kind])


## A cached architecture material. `overrides` are shader parameters applied on
## top of the preset (used for biome frost or tint changes).
static func material(preset: String) -> ShaderMaterial:
	if _cache.has(preset):
		return _cache[preset]
	var data: Dictionary = _presets()[preset]
	var material := ShaderMaterial.new()
	material.resource_name = "Surface " + preset
	material.shader = ARCHITECTURE
	material.set_shader_parameter("albedo_tex", _tex(data.maps, "albedo"))
	material.set_shader_parameter("normal_tex", _tex(data.maps, "normal"))
	material.set_shader_parameter("rough_tex", _tex(data.maps, "rough"))
	material.set_shader_parameter("frost_albedo", load(GENERATED % ["dirty_snow", "albedo"]))
	material.set_shader_parameter("frost_normal", load(GENERATED % ["dirty_snow", "normal"]))
	material.set_shader_parameter("tint", data.tint)
	material.set_shader_parameter("uv_scale", data.scale)
	material.set_shader_parameter("frost_amount", data.get("frost", 0.0))
	var rough: Vector2 = data.get("rough", Vector2(0.0, 1.0))
	material.set_shader_parameter("roughness_min", rough.x)
	material.set_shader_parameter("roughness_max", rough.y)
	material.set_shader_parameter("metallic", data.get("metallic", 0.0))
	material.set_shader_parameter("normal_strength", data.get("normal", 0.9))
	material.set_shader_parameter("saturation", data.get("saturation", 1.0))
	material.set_shader_parameter("carrion_shift", data.get("carrion", Color.WHITE))
	material.set_shader_parameter("crown_shift", data.get("crown", Color.WHITE))
	_cache[preset] = material
	return material


## Soft-edged alpha stain for the flat patch meshes baked into the biome GLBs.
static func stain(preset: String) -> ShaderMaterial:
	var key := "stain:" + preset
	if _cache.has(key):
		return _cache[key]
	var material := ShaderMaterial.new()
	material.resource_name = "Stain " + preset
	material.shader = STAIN
	match preset:
		"blood":
			material.set_shader_parameter("stain_color", Color(0.19, 0.012, 0.01))
			material.set_shader_parameter("opacity", 0.78)
			material.set_shader_parameter("wet", 0.55)
		"snow":
			material.set_shader_parameter("stain_color", Color(0.66, 0.74, 0.86))
			material.set_shader_parameter("opacity", 0.97)
			material.set_shader_parameter("wet", 0.1)
			material.set_shader_parameter("detail_tex", load(GENERATED % ["dirty_snow", "albedo"]))
			material.set_shader_parameter("detail_mix", 0.85)
		"ash":
			material.set_shader_parameter("stain_color", Color(0.045, 0.045, 0.05))
			material.set_shader_parameter("opacity", 0.55)
			material.set_shader_parameter("wet", 0.0)
	_cache[key] = material
	return material


## GLB material names that get a shared preset, per kind of surface.
const GLB_TABLE := {
	"Widowpine dark fieldstone": "slate",
	"Wet exposed pine roots": "bark",
	"Old black iron": "iron",
	"Varkas black iron": "iron",
	"Warpack smoke-black hide": "hide",
	"Trough black ice": "ice",
	"Dried bellthorn red": "bellthorn",
	"Dried bellthorn and banners": "banner",
	"Black weathered timber": "timber",
	"Sooted timber": "timber",
	"Carrion ironstone": "red_stone",
	"Mother shrine pale limestone": "limestone",
	"Mother shrine rain-dark limestone": "limestone_dark",
	"Rain-black shrine cuts": "cut",
	"Deep recess": "recess",
	"Black granite": "slate_dark",
	"Ancient pale limestone": "scorched_masonry",
	"Ravine dark rock": "rock",
	"Mother Bell bronze": "bronze",
	"Ninefold weathered bronze": "bronze",
}

## Flat patches that must fade out instead of ending in a hard polygon edge.
const GLB_STAINS := {
	"Old iron-dark blood": "blood",
	"Blue crusted snow": "snow",
	"Dirty moonlit snow": "snow",
	"Deep ravine shadow": "ash",
}


## Replaces the materials of every mesh under `root` (an instanced GLB) using
## surface overrides, leaving the shared imported meshes untouched.
static func upgrade(root: Node) -> void:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		var instance := node as MeshInstance3D
		if instance == null or instance.mesh == null:
			continue
		for surface in instance.mesh.get_surface_count():
			var source := instance.mesh.surface_get_material(surface)
			if source == null:
				continue
			var key := source.resource_name
			if GLB_TABLE.has(key):
				instance.set_surface_override_material(surface, material(GLB_TABLE[key]))
			elif GLB_STAINS.has(key):
				instance.set_surface_override_material(surface, stain(GLB_STAINS[key]))
				instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Kenney kit materials are flat pastel swatches; these are the scanned/generated
## equivalents keyed by the swatch material name.
const PROP_TABLE := {
	"wood": "timber",
	"woodDark": "timber",
	"woodBark": "bark",
	"woodBarkDark": "bark",
	"woodInner": "timber",
	"_defaultMat": "timber",
	"stone": "slate",
	"stoneDark": "slate_dark",
	"metal": "iron",
	"colormap": "timber",
}


static func prop_material(source_name: String) -> Material:
	if PROP_TABLE.has(source_name):
		return material(PROP_TABLE[source_name])
	return null
