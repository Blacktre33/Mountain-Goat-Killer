shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Fur for the warpack. The wolverine mesh keeps the source rig's small palette
// UV islands, so the coat is projected in object space instead: two scales of
// the generated guard-hair swatch, a pale flank band, dry-brush war paint, and
// scars all follow the skinned body through every clip.

uniform sampler2D fur_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D fur_b : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D paint_mask : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform vec3 base_tint : source_color = vec3(0.55, 0.5, 0.46);
uniform vec3 pale_tint : source_color = vec3(1.1, 0.95, 0.75);
uniform vec3 paint_color : source_color = vec3(0.62, 0.05, 0.03);
uniform float light_amount : hint_range(0.0, 1.0) = 0.0;
uniform float fur_scale = 0.55;
// Skinned vertices arrive in the rig's 0.01 skeleton units; this restores the
// ~2.5-unit body the swatches were laid out against (1 unit is about 0.25 m).
uniform float position_scale = 100.0;
uniform float paint_amount : hint_range(0.0, 1.0) = 0.6;
uniform float paint_seed = 0.0;
uniform float flank_band : hint_range(0.0, 1.0) = 0.55;
uniform float frost : hint_range(0.0, 1.0) = 0.12;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec3 flash_color : source_color = vec3(1.0, 0.36, 0.15);
uniform float wet : hint_range(0.0, 1.0) = 0.0;

varying vec3 obj_position;
varying vec3 mesh_position;
varying vec3 obj_normal;

vec3 triplanar(sampler2D tex, vec3 position, vec3 weights, float scale) {
	vec3 x = texture(tex, position.yz * scale).rgb;
	vec3 y = texture(tex, position.xz * scale).rgb;
	vec3 z = texture(tex, position.xy * scale).rgb;
	return x * weights.x + y * weights.y + z * weights.z;
}

void vertex() {
	obj_position = VERTEX * position_scale;
	mesh_position = VERTEX * position_scale;
	obj_normal = NORMAL;
}

void fragment() {
	vec3 weights = pow(abs(normalize(obj_normal)), vec3(4.0));
	weights /= (weights.x + weights.y + weights.z);
	vec3 coarse = triplanar(fur_a, obj_position, weights, fur_scale * 0.62);
	vec3 fine = triplanar(fur_b, obj_position + vec3(0.37, 0.11, 0.52), weights, fur_scale * 1.7);
	vec3 coat = mix(coarse, fine, 0.5);
	float luminance = dot(coat, vec3(0.3, 0.59, 0.11));

	// Skeleton space: x is across the body, y runs along it, z is up.
	float lateral = abs(mesh_position.x);
	float band = smoothstep(0.35, 0.62, lateral) * (1.0 - smoothstep(0.85, 1.25, lateral));
	band *= flank_band;
	vec3 albedo = coat * mix(base_tint, pale_tint, clamp(max(light_amount, band * 0.55), 0.0, 1.0));

	// War paint and scars: a claw mask projected from the flank, offset per animal.
	vec2 paint_uv = vec2(mesh_position.y * 0.9 + mesh_position.z * 0.25, mesh_position.z * 0.85) * 0.55 + vec2(paint_seed, paint_seed * 1.7);
	float paint = texture(paint_mask, paint_uv).r * weights.x * paint_amount;
	float paint_top = texture(paint_mask, mesh_position.xy * 0.6 + vec2(paint_seed * 2.3)).r * weights.z * paint_amount * 0.5;
	paint = max(paint, paint_top);
	albedo = mix(albedo, paint_color * (0.6 + luminance), clamp(paint, 0.0, 1.0));

	// Rime on the coat's upper surfaces.
	float snow = smoothstep(0.55, 0.95, normalize(obj_normal).z) * frost * luminance;
	albedo = mix(albedo, vec3(0.75, 0.8, 0.85), snow);

	ALBEDO = albedo * (0.8 + luminance * 0.5);
	ROUGHNESS = mix(0.9, 0.55, wet);
	SPECULAR = 0.25;
	// Soft fur fuzz at grazing angles keeps the silhouette from reading hard-edged.
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = albedo * fresnel * 0.18 + flash_color * flash * (0.2 + luminance * 1.4);
}
