class_name GraphicsQuality
extends RefCounted
## Graphics presets. ULTRA is the authored desktop look the art was reviewed
## at (SSAO, SSIL, volumetric fog, 4x MSAA, full resolution); the lower
## presets drop the most expensive effects first for weaker GPUs.

const ORDER := ["low", "medium", "high", "ultra"]
const PRESETS := {
	"low": {
		"title": "LOW",
		"ssao": false, "ssil": false, "volumetric_fog": false, "glow": true,
		"msaa": Viewport.MSAA_DISABLED, "render_scale": 0.75, "shadow_distance": 45.0,
	},
	"medium": {
		"title": "MEDIUM",
		"ssao": true, "ssil": false, "volumetric_fog": false, "glow": true,
		"msaa": Viewport.MSAA_2X, "render_scale": 1.0, "shadow_distance": 65.0,
	},
	"high": {
		"title": "HIGH",
		"ssao": true, "ssil": false, "volumetric_fog": true, "glow": true,
		"msaa": Viewport.MSAA_4X, "render_scale": 1.0, "shadow_distance": 90.0,
	},
	"ultra": {
		"title": "ULTRA",
		"ssao": true, "ssil": true, "volumetric_fog": true, "glow": true,
		"msaa": Viewport.MSAA_4X, "render_scale": 1.0, "shadow_distance": 90.0,
	},
}
## Without volumetric fog, a little denser distance fog keeps the ravine's depth.
const FOG_DENSITY_WITHOUT_VOLUMETRICS := 0.017


static func key() -> String:
	var value: String = GameSettings.get_value("graphics_quality")
	return value if PRESETS.has(value) else "ultra"


static func preset(name := "") -> Dictionary:
	return PRESETS.get(name if not name.is_empty() else key(), PRESETS.ultra)


static func title(name := "") -> String:
	return preset(name).title


## Apply the current preset to the world's environment, moonlight and viewport.
## Re-apply after a biome change, which restores the authored fog density.
static func apply(environment: Environment, moon: DirectionalLight3D, viewport: Viewport) -> void:
	var settings := preset()
	var base_fog_density: float = environment.get_meta("authored_fog_density", environment.fog_density)
	environment.ssao_enabled = settings.ssao
	environment.ssil_enabled = settings.ssil
	environment.volumetric_fog_enabled = settings.volumetric_fog
	environment.glow_enabled = settings.glow
	environment.fog_density = base_fog_density if settings.volumetric_fog else maxf(base_fog_density, FOG_DENSITY_WITHOUT_VOLUMETRICS)
	if moon:
		moon.directional_shadow_max_distance = settings.shadow_distance
	if viewport:
		viewport.msaa_3d = settings.msaa
		viewport.scaling_3d_scale = settings.render_scale
		viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if settings.render_scale < 1.0 else Viewport.SCALING_3D_MODE_BILINEAR


## Window mode and V-sync. Only a real play session changes the window.
static func apply_display() -> void:
	if not GameSettings.persistent() or DisplayServer.get_name() == "headless":
		return
	var fullscreen: bool = GameSettings.get_value("fullscreen")
	var wanted := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	var current := DisplayServer.window_get_mode()
	var is_fullscreen := current == DisplayServer.WINDOW_MODE_FULLSCREEN or current == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if fullscreen != is_fullscreen:
		DisplayServer.window_set_mode(wanted)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if GameSettings.get_value("vsync") else DisplayServer.VSYNC_DISABLED)
