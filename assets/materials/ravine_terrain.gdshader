shader_type spatial;
// Ravine ground: scanned snow over three biome soils and a triplanar cliff
// layer. Every map is sampled twice at unrelated scales/rotations and cross-
// faded by noise (no visible repeat), snow cover is height-blended against the
// soil so drift edges follow stones and needles, and the compacted trail gets
// slush wetness while open snow carries a faint ice sparkle.

uniform sampler2D grain : filter_linear_mipmap, repeat_enable;
uniform sampler2D snow_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_roughness : hint_roughness_gray, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grime_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grime_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D forest_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D forest_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D carrion_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D carrion_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D crown_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D crown_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cliff_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cliff_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

varying vec3 world_pos;
varying vec3 world_normal;

const mat2 ROT = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));

vec4 tex2(sampler2D t, vec2 uv, float m) {
	return mix(texture(t, uv), texture(t, ROT * uv * 0.57 + vec2(0.31, 0.77)), m);
}

// Tangent-space normal sample -> world-space offset for a projection along Y.
vec3 nrm_y(sampler2D t, vec2 uv, float m) {
	vec3 n = tex2(t, uv, m).rgb * 2.0 - 1.0;
	return vec3(n.x, 0.0, n.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec3 wn = normalize(world_normal);
	float up = wn.y;
	vec2 p = world_pos.xz;
	float macro = texture(grain, p * 0.012).r;
	float breakup = texture(grain, p * 0.065).r;
	float fine = texture(grain, p * 0.31).r;
	float anti = smoothstep(0.3, 0.7, texture(grain, p * 0.021 + 0.4).r);

	// Biome weights, wobbling with the same noise as the snow line.
	float boundary = world_pos.z + (macro - 0.5) * 10.0 + (breakup - 0.5) * 3.0;
	float carrion = 1.0 - smoothstep(-25.0, -12.0, boundary);
	float crown = 1.0 - smoothstep(-87.0, -73.0, boundary);
	float forest = clamp(1.0 - carrion - crown, 0.0, 1.0);
	carrion = clamp(carrion - crown, 0.0, 1.0);

	// --- Bare ground: three soils and the cliff layer ------------------------
	vec3 soil = vec3(0.0);
	vec3 soil_n = vec3(0.0);
	if (forest > 0.01) {
		soil += tex2(forest_albedo, p * 0.36, anti).rgb * vec3(0.55, 0.5, 0.46) * forest;
		soil_n += nrm_y(forest_normal, p * 0.36, anti) * forest;
	}
	if (carrion > 0.01) {
		soil += tex2(carrion_albedo, p * 0.3, anti).rgb * vec3(0.5, 0.3, 0.27) * carrion;
		soil_n += nrm_y(carrion_normal, p * 0.3, anti) * carrion;
	}
	if (crown > 0.01) {
		vec3 ash = tex2(crown_albedo, p * 0.34, anti).rgb;
		ash = mix(vec3(dot(ash, vec3(0.3, 0.55, 0.15))), ash, 0.35);
		soil += ash * vec3(0.36, 0.36, 0.42) * crown;
		soil_n += nrm_y(crown_normal, p * 0.34, anti) * crown;
	}
	soil *= 0.85 + fine * 0.3;

	float rock_amt = 1.0 - smoothstep(0.6, 0.9, up);
	vec3 ground = soil;
	vec3 ground_n = soil_n;
	if (rock_amt > 0.01) {
		vec3 w = pow(abs(wn), vec3(5.0));
		w /= (w.x + w.y + w.z);
		vec3 rock = vec3(0.0);
		vec3 rock_n = vec3(0.0);
		vec2 ux = world_pos.zy * 0.2;
		vec2 uy = world_pos.xz * 0.2;
		vec2 uz = world_pos.xy * 0.2;
		rock += tex2(cliff_albedo, ux, anti).rgb * w.x + tex2(cliff_albedo, uy, anti).rgb * w.y + tex2(cliff_albedo, uz, anti).rgb * w.z;
		vec3 nx = tex2(cliff_normal, ux, anti).rgb * 2.0 - 1.0;
		vec3 ny = tex2(cliff_normal, uy, anti).rgb * 2.0 - 1.0;
		vec3 nz = tex2(cliff_normal, uz, anti).rgb * 2.0 - 1.0;
		rock_n = vec3(0.0, nx.y, nx.x) * w.x + vec3(ny.x, 0.0, ny.y) * w.y + vec3(nz.x, nz.y, 0.0) * w.z;
		vec3 cliff_tint = mix(vec3(0.5, 0.55, 0.64), vec3(0.62, 0.36, 0.3), carrion);
		cliff_tint = mix(cliff_tint, vec3(0.36, 0.37, 0.42), crown);
		rock *= cliff_tint;
		ground = mix(soil, rock, rock_amt);
		ground_n = mix(soil_n, rock_n, rock_amt);
	}
	float ground_h = dot(ground, vec3(0.3, 0.55, 0.15));

	// --- Snow ------------------------------------------------------------------
	float trail = 1.0 - smoothstep(0.9, 2.6, abs(world_pos.x - sin(world_pos.z * 0.12) * 1.2));
	float cover = mix(0.76, 0.46, carrion);
	cover = mix(cover, 0.3, crown);
	cover += (macro - 0.5) * 0.9 + (breakup - 0.5) * 0.3 + (texture(grain, p * 0.19).r - 0.5) * 0.4;
	cover -= trail * 0.08 * (1.0 - carrion);
	vec3 snow = tex2(snow_albedo, p * 0.24, anti).rgb;
	float snow_h = dot(snow, vec3(0.3, 0.55, 0.15)) + (fine - 0.5) * 0.25;
	// Height blend: snow fills hollows first and thins over stones and needles,
	// so the edge follows the ground's own relief instead of a noise contour.
	float field = (cover - 0.5) * 1.5 + 0.5 + (snow_h - ground_h) * 0.55;
	float snow_cover = smoothstep(0.36, 0.7, field) * smoothstep(0.52, 0.86, up);
	// Trodden and dirty snow: the compacted lane greys and the low-cover fringe browns.
	float dirty = clamp(trail * 0.65 + (1.0 - smoothstep(0.3, 0.7, cover)) * 0.55 + (breakup - 0.5) * 0.4, 0.0, 1.0);
	vec3 grime = tex2(grime_albedo, p * 0.42, anti).rgb;
	vec3 snow_tint = mix(vec3(0.66, 0.76, 0.9), vec3(0.6, 0.56, 0.5), carrion);
	snow_tint = mix(snow_tint, vec3(0.42, 0.44, 0.5), crown);
	vec3 snow_col = mix(snow * snow_tint * 0.95, grime * snow_tint * 0.75, dirty * 0.6);

	vec3 albedo = mix(ground, snow_col, snow_cover);

	vec3 snow_n = nrm_y(snow_normal, p * 0.55, anti);
	snow_n = mix(snow_n, nrm_y(grime_normal, p * 0.42, anti), dirty * 0.5);
	vec3 offset = mix(ground_n * 0.85, snow_n * 0.6, snow_cover);
	vec3 n = normalize(wn + offset);
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	// --- Wetness, slush, ice sparkle -----------------------------------------
	float slush = trail * snow_cover * (1.0 - carrion * 0.6) * smoothstep(0.35, 0.75, breakup);
	albedo *= 1.0 - slush * 0.22;
	float rough = mix(0.86, 0.72, snow_cover);
	rough = mix(rough, 0.22, slush * 0.75);
	rough = mix(rough, 0.35, carrion * (1.0 - snow_cover) * smoothstep(0.55, 0.8, breakup) * 0.4);
	ROUGHNESS = rough;
	SPECULAR = mix(0.14, 0.3, snow_cover);

	vec2 gp = world_pos.xz * 150.0;
	vec2 gid = floor(gp);
	float cell = fract(sin(dot(gid, vec2(127.1, 311.7))) * 43758.5453);
	vec2 jitter = (vec2(fract(cell * 17.0), fract(cell * 53.0)) - 0.5) * 0.5;
	float spot = smoothstep(0.26, 0.0, length(fract(gp) - 0.5 - jitter));
	float twinkle = smoothstep(0.5, 1.0, fract(cell * 13.0 + dot(VIEW.xz, vec2(3.1, 1.9))));
	EMISSION = vec3(0.5, 0.65, 0.9) * step(0.9, cell) * spot * twinkle * snow_cover * (1.0 - slush) * 0.9;
	ALBEDO = albedo;
}
