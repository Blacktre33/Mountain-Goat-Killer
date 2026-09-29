shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// Wind-cut snow drift ribbon. UV.y runs 0..2 across the two strips of the
// ridge (1 at the crest), so alpha falls to zero along both flanks and the
// drift dissolves into the terrain instead of ending in a hard polygon edge.

uniform sampler2D snow_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D snow_normal : hint_normal, filter_linear_mipmap, repeat_enable;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float across = 1.0 - abs(UV.y - 1.0);
	float alpha = pow(clamp(across, 0.0, 1.0), 1.7);
	vec3 snow = texture(snow_albedo, world_pos.xz * 0.6).rgb;
	ALBEDO = snow * vec3(0.52, 0.6, 0.72);
	ALPHA = alpha * 0.7;
	NORMAL_MAP = texture(snow_normal, world_pos.xz * 0.6).rgb;
	NORMAL_MAP_DEPTH = 0.6;
	ROUGHNESS = 0.78;
}
