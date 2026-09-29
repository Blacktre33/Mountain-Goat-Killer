shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// Soft, broken-edged stain for thin patch meshes whose UVs run 0..1 across the
// patch (centre at 0.5). The alpha dissolves through fbm noise so a stain never
// ends in a hard polygon outline that could read as a hole in the snow.

uniform vec3 stain_color : source_color = vec3(0.2, 0.01, 0.01);
uniform float opacity = 0.75;
uniform float wet = 0.5;
uniform sampler2D detail_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float detail_mix = 0.0;
uniform float detail_scale = 0.7;

varying vec3 world_pos;

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
	return value_noise(p) * 0.55 + value_noise(p * 2.3 + 5.1) * 0.3 + value_noise(p * 5.1 - 2.7) * 0.15;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float n = fbm(world_pos.xz * 3.2);
	float edge = smoothstep(1.0, 0.25, d + (n - 0.5) * 0.9);
	float core = fbm(world_pos.xz * 9.0 + 11.0);
	float alpha = edge * mix(0.55, 1.0, core) * opacity;
	vec3 colour = stain_color * mix(0.7, 1.25, core);
	if (detail_mix > 0.0) {
		colour = mix(colour, texture(detail_tex, world_pos.xz * detail_scale).rgb * stain_color * 1.6, detail_mix);
	}
	ALBEDO = colour;
	ALPHA = clamp(alpha, 0.0, 1.0);
	ROUGHNESS = mix(0.95, 0.25, wet * edge);
	SPECULAR = mix(0.2, 0.6, wet);
}
