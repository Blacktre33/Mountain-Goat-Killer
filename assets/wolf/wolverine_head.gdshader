shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// The generated warpack head. Its baked pale-blue eyes are found by colour and
// lit with whatever the wolverine knows: cold blue, amber when suspicious, red
// when hunting. Hit flashes and rime work as on the fur.

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 eye_color : source_color = vec3(0.35, 0.65, 1.0);
uniform float eye_energy = 2.5;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec3 flash_color : source_color = vec3(1.0, 0.36, 0.15);
uniform float frost : hint_range(0.0, 1.0) = 0.1;

varying vec3 world_up_normal;

void vertex() {
	world_up_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 tex = texture(albedo_texture, UV).rgb;
	float blueness = tex.b - max(tex.r, tex.g * 0.92);
	float eye = smoothstep(0.07, 0.24, blueness) * smoothstep(0.42, 0.7, tex.b);
	float luminance = dot(tex, vec3(0.3, 0.59, 0.11));
	vec3 albedo = mix(tex, eye_color * 0.5, eye);
	float rime = smoothstep(0.6, 0.95, world_up_normal.y) * frost * luminance;
	albedo = mix(albedo, vec3(0.75, 0.8, 0.86), rime);
	ALBEDO = albedo;
	ROUGHNESS = mix(0.82, 0.3, eye);
	SPECULAR = 0.3;
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = eye_color * eye * eye_energy + albedo * fresnel * 0.12 + flash_color * flash * (0.2 + luminance * 1.4);
}
