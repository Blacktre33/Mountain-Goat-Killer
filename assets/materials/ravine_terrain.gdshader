shader_type spatial;

uniform sampler2D grain : filter_linear_mipmap, repeat_enable;
uniform sampler2D snow_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_roughness : filter_linear_mipmap_anisotropic, repeat_enable;

varying vec3 world_pos;
varying float slope;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	slope = NORMAL.y;
}

void fragment() {
	float macro = texture(grain, world_pos.xz * 0.012).r;
	float breakup = texture(grain, world_pos.xz * 0.065).r;
	vec2 surface_uv = world_pos.xz * 0.27;
	vec2 detail_uv = world_pos.xz * 0.62;
	vec3 snow_scan = texture(snow_albedo, surface_uv).rgb;
	vec3 stone_scan = texture(rock_albedo, surface_uv * 0.73).rgb;
	float snow_luma = dot(snow_scan, vec3(0.2126, 0.7152, 0.0722));
	float stone_luma = dot(stone_scan, vec3(0.2126, 0.7152, 0.0722));

	// Drift boundaries cross the path irregularly, without a straight colour
	// stripe at the story trigger. Snow coverage changes as well as pigment.
	float boundary = world_pos.z + (macro - 0.5) * 10.0 + (breakup - 0.5) * 3.0;
	float carrion = 1.0 - smoothstep(-25.0, -12.0, boundary);
	float crown = 1.0 - smoothstep(-87.0, -73.0, boundary);
	float exposed_rock = 1.0 - smoothstep(0.66, 0.91, slope);
	float trail = 1.0 - smoothstep(0.9, 2.5, abs(world_pos.x - sin(world_pos.z * 0.12) * 1.2));
	float cover = mix(0.74, 0.43, carrion);
	cover = mix(cover, 0.29, crown);
	cover += (macro - 0.5) * 0.95 + (breakup - 0.5) * 0.3;
	cover -= trail * 0.11 * (1.0 - carrion);
	float snow_cover = smoothstep(0.32, 0.68, cover) * smoothstep(0.58, 0.95, slope);

	vec3 forest_soil = vec3(0.047, 0.043, 0.035);
	vec3 carrion_soil = vec3(0.16, 0.062, 0.034);
	vec3 crown_soil = vec3(0.039, 0.042, 0.048);
	vec3 soil = mix(forest_soil, carrion_soil, carrion);
	soil = mix(soil, crown_soil, crown);
	vec3 cliff = mix(vec3(0.042, 0.055, 0.064), vec3(0.085, 0.039, 0.028), carrion);
	cliff = mix(cliff, vec3(0.029, 0.033, 0.041), crown);
	soil = mix(soil, cliff, exposed_rock);
	soil *= 0.48 + stone_luma * 1.8 + breakup * 0.26;
	vec3 snow = mix(vec3(0.36, 0.43, 0.50), vec3(0.29, 0.29, 0.28), carrion);
	snow = mix(snow, vec3(0.22, 0.24, 0.27), crown);
	snow *= 0.54 + snow_luma * 0.8;
	ALBEDO = mix(soil, snow, snow_cover);

	vec3 snow_micro = texture(snow_normal, detail_uv).rgb;
	vec3 stone_micro = texture(rock_normal, detail_uv * 0.76).rgb;
	NORMAL_MAP = mix(stone_micro, snow_micro, snow_cover);
	NORMAL_MAP_DEPTH = mix(0.72, 0.48, snow_cover);
	float snow_rough = texture(snow_roughness, detail_uv).r;
	float stone_rough = texture(rock_roughness, detail_uv * 0.76).r;
	ROUGHNESS = mix(mix(0.83, 0.98, stone_rough), mix(0.73, 0.94, snow_rough), snow_cover);
	SPECULAR = mix(0.13, 0.28, snow_cover);
}
