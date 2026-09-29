shader_type spatial;
// Distant ravine peaks as dark silhouettes against the luminous sky. Their base
// dissolves into the same haze the fog produces, so they never read as lit blue
// blobs, and only a thin moon rim and a cold snow line survive on the far side.
render_mode unshaded, fog_disabled, shadows_disabled;

uniform vec3 rock_color : source_color = vec3(0.02, 0.03, 0.05);
uniform vec3 rim_color : source_color = vec3(0.14, 0.21, 0.32);
uniform vec3 snow_tone : source_color = vec3(0.10, 0.15, 0.22);
uniform vec3 haze_color : source_color = vec3(0.16, 0.32, 0.48);
uniform vec3 moon_dir = vec3(0.37, 0.62, -0.70);
uniform float haze_height = 30.0;
uniform float haze_strength = 0.9;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(world_normal);
	float moon_face = max(dot(n, normalize(moon_dir)), 0.0);
	vec3 col = rock_color + rim_color * pow(moon_face, 1.6);
	float snow_line = smoothstep(26.0, 48.0, world_pos.y) * smoothstep(0.15, 0.75, n.y);
	col = mix(col, snow_tone * (0.35 + moon_face), snow_line * 0.7);
	// Height haze pools at the foot of each peak; distance haze softens far ones.
	float pool = exp(-max(world_pos.y - 4.0, 0.0) / haze_height);
	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	// Far ridges lose almost all contrast: they must read as mist-shrouded
	// mountains behind the sky glow, never as black masses hanging in it.
	float distance_haze = 1.0 - exp(-dist * 0.011);
	float haze = clamp(max(pool * haze_strength, distance_haze * 0.92), 0.0, 1.0);
	ALBEDO = mix(col, haze_color, haze);
}
