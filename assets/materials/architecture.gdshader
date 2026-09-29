shader_type spatial;
// Triplanar PBR for hewn masonry, timber, iron and cloth. Every architectural
// surface in the three biomes shares this shader so the world reads as one
// material family: the same frost dusting on upward faces, the same anti-tiling
// and the same macro tint drift, with only the scanned/generated maps and the
// tint changing per biome.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_roughness_gray, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D frost_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D frost_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

uniform vec3 tint : source_color = vec3(1.0);
uniform float uv_scale = 0.5;
uniform float normal_strength = 1.0;
uniform float roughness_min = 0.0;
uniform float roughness_max = 1.0;
uniform float metallic = 0.0;
uniform float specular = 0.4;
/// 0 = bare, 1 = every upward-facing surface is dusted with dirty snow.
uniform float frost_amount = 0.0;
uniform vec3 frost_tint : source_color = vec3(0.62, 0.7, 0.8);
uniform float frost_scale = 0.35;
uniform float saturation = 1.0;
/// Multipliers that fade in with the Carrion Cut (z < -18) and the Iron Crown (z < -78).
uniform vec3 carrion_shift = vec3(1.0);
uniform vec3 crown_shift = vec3(1.0);
uniform float macro_scale = 0.045;
uniform float macro_strength = 0.35;
uniform vec3 emission_tint : source_color = vec3(0.0);
uniform float emission_energy = 0.0;

varying vec3 tri_pos;
varying vec3 tri_normal;
varying vec4 vertex_tint;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1, 0)), f.x), mix(hash21(i + vec2(0, 1)), hash21(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	return value_noise(p) * 0.6 + value_noise(p * 2.13 + 7.7) * 0.3 + value_noise(p * 4.7 - 3.1) * 0.1;
}

void vertex() {
	tri_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	tri_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	vertex_tint = COLOR;
}

// One plane of the projection sampled twice at unrelated scales and rotations
// and cross-faded by low-frequency noise, so the repeat never shows as a grid.
vec4 sample_plane(sampler2D tex, vec2 uv, float mix_mask) {
	vec4 a = texture(tex, uv);
	mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	vec4 b = texture(tex, rot * uv * 0.61 + vec2(0.37, 0.71));
	return mix(a, b, mix_mask);
}

void fragment() {
	vec3 n = normalize(tri_normal);
	vec3 w = pow(abs(n), vec3(6.0));
	w /= (w.x + w.y + w.z);
	vec2 uv_x = tri_pos.zy * uv_scale;
	vec2 uv_y = tri_pos.xz * uv_scale;
	vec2 uv_z = tri_pos.xy * uv_scale;
	float breakup = smoothstep(0.25, 0.75, fbm(tri_pos.xz * 0.11 + tri_pos.y * 0.07));

	vec3 albedo = vec3(0.0);
	vec3 nrm = vec3(0.0);
	float rough = 0.0;
	if (w.x > 0.02) {
		albedo += sample_plane(albedo_tex, uv_x, breakup).rgb * w.x;
		vec3 tn = texture(normal_tex, uv_x).rgb * 2.0 - 1.0;
		nrm += vec3(0.0, tn.y, tn.x) * w.x;
		rough += texture(rough_tex, uv_x).r * w.x;
	}
	if (w.y > 0.02) {
		albedo += sample_plane(albedo_tex, uv_y, breakup).rgb * w.y;
		vec3 tn = texture(normal_tex, uv_y).rgb * 2.0 - 1.0;
		nrm += vec3(tn.x, 0.0, tn.y) * w.y;
		rough += texture(rough_tex, uv_y).r * w.y;
	}
	if (w.z > 0.02) {
		albedo += sample_plane(albedo_tex, uv_z, breakup).rgb * w.z;
		vec3 tn = texture(normal_tex, uv_z).rgb * 2.0 - 1.0;
		nrm += vec3(tn.x, tn.y, 0.0) * w.z;
		rough += texture(rough_tex, uv_z).r * w.z;
	}
	albedo *= tint;
	float luma = dot(albedo, vec3(0.2126, 0.7152, 0.0722));
	albedo = mix(vec3(luma), albedo, saturation);
	float biome_noise = (fbm(tri_pos.xz * 0.05) - 0.5) * 10.0;
	float crown_w = 1.0 - smoothstep(-87.0, -73.0, tri_pos.z + biome_noise);
	float carrion_w = clamp(1.0 - smoothstep(-25.0, -12.0, tri_pos.z + biome_noise) - crown_w, 0.0, 1.0);
	vec3 shift = mix(vec3(1.0), carrion_shift, carrion_w);
	albedo *= mix(shift, crown_shift, crown_w);
	// Slow tint drift plus per-block variation baked into vertex colour.
	float macro = fbm(tri_pos.xz * macro_scale + tri_pos.y * 0.09);
	albedo *= 1.0 - macro_strength * 0.5 + macro * macro_strength;
	// Alpha 1 marks meshes painted with per-block tint; anything else is left as is.
	albedo *= mix(vec3(1.0), vertex_tint.rgb, 0.85 * step(0.5, vertex_tint.a));

	// Frost and dirty snow settle on faces that look up, unevenly.
	float up = clamp(n.y, 0.0, 1.0);
	float drift = fbm(tri_pos.xz * 0.9 + 3.0);
	float frost_mask = smoothstep(0.55, 0.85, up + (drift - 0.5) * 0.55) * frost_amount;
	if (frost_mask > 0.001) {
		vec2 fuv = tri_pos.xz * frost_scale;
		vec3 f_albedo = sample_plane(frost_albedo, fuv, breakup).rgb * frost_tint;
		vec3 f_nrm = texture(frost_normal, fuv).rgb * 2.0 - 1.0;
		albedo = mix(albedo, f_albedo, frost_mask);
		nrm = mix(nrm, vec3(f_nrm.x, 0.0, f_nrm.y) * 1.2, frost_mask);
		rough = mix(rough, 0.72, frost_mask);
	}

	ALBEDO = albedo;
	ROUGHNESS = clamp(mix(roughness_min, roughness_max, rough), 0.02, 1.0);
	METALLIC = metallic;
	SPECULAR = specular;
	// Perturb the geometric normal with the blended tangent-space samples.
	// Whiteout-style blend of the three planes' tangent normals in world space.
	vec3 perturbed = normalize(n + nrm * normal_strength);
	NORMAL = normalize((VIEW_MATRIX * vec4(perturbed, 0.0)).xyz);
	EMISSION = emission_tint * emission_energy;
}
