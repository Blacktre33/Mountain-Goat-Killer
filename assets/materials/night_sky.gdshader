shader_type sky;
// Night sky for the ravine: CC0 HDRI structure, a luminous horizon, drifting
// cloud bands, a hashed star field, a faint aurora, and a moon that lives at
// infinity. The moon direction is the Moonlight node's direction, set from
// script, so the disc, its halo, the shadows and the rim light always agree.
// Because this is sky, the disc can never draw over a tree, rock or building.

uniform sampler2D panorama : source_color, filter_linear, repeat_enable;
uniform sampler2D moon_surface : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 moon_dir = vec3(0.37, 0.62, -0.70);

uniform vec3 zenith_color : source_color = vec3(0.02, 0.04, 0.10);
uniform vec3 mid_color : source_color = vec3(0.05, 0.10, 0.22);
uniform vec3 horizon_color : source_color = vec3(0.16, 0.32, 0.48);
uniform vec3 glow_color : source_color = vec3(0.30, 0.52, 0.72);
uniform vec3 ground_color : source_color = vec3(0.03, 0.05, 0.08);
uniform vec3 cloud_tint : source_color = vec3(0.35, 0.48, 0.65);
uniform vec3 moon_tint : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 halo_tint : source_color = vec3(0.45, 0.65, 1.0);

uniform float panorama_energy = 0.25;
uniform float star_strength = 1.0;
uniform float cloud_cover = 0.5;
uniform float aurora_strength = 0.0;
uniform float moon_disc = 4.0;
uniform float halo_ring = 0.0;
uniform float moon_rays = 0.0;
uniform float moon_radius = 0.055;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

vec3 hash33(vec3 p3) {
	p3 = fract(p3 * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yxz + 33.33);
	return fract((p3.xxy + p3.yxx) * p3.zyx);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x),
			mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float amplitude = 0.5;
	float sum = 0.0;
	for (int i = 0; i < 5; i++) {
		sum += amplitude * value_noise(p);
		p = p * 2.03 + vec2(17.3, 9.1);
		amplitude *= 0.5;
	}
	return sum;
}

// Hashed points on the unit sphere, one jittered star per cell.
float star_layer(vec3 dir, float scale, float density, float radius) {
	vec3 sp = dir * scale;
	vec3 id = floor(sp);
	vec3 local = fract(sp) - 0.5;
	float pick = hash13(id);
	vec3 jitter = (hash33(id) - 0.5) * 0.6;
	float d = length(local - jitter);
	float magnitude = pow(hash13(id + 4.7), 3.0);
	return smoothstep(radius, radius * 0.1, d) * step(1.0 - density, pick) * (0.35 + 1.4 * magnitude);
}

float cloud_density(vec2 p) {
	float base = fbm(p);
	// Stretch the coverage into long bands so the layer reads as stratus, not smoke.
	float band = fbm(p * vec2(0.35, 1.1) + 3.7);
	return base * 0.65 + band * 0.55;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float h = dir.y;
	float moon_cos = dot(dir, normalize(moon_dir));
	float moon_angle = acos(clamp(moon_cos, -1.0, 1.0));

	// Base gradient: deep zenith down to a luminous horizon band.
	vec3 col = mix(horizon_color, mid_color, smoothstep(0.0, 0.22, h));
	col = mix(col, zenith_color, smoothstep(0.12, 0.85, h));
	// Horizon glow, strongest toward the moon (forward scattering through haze).
	float glow_falloff = exp(-abs(h) * 7.0);
	col += glow_color * glow_falloff * (0.7 + 1.3 * pow(max(moon_cos, 0.0), 3.0));
	// Below the horizon the sky fades to the dark ground tone.
	col = mix(col, ground_color, smoothstep(0.0, -0.35, h));

	// The HDRI supplies a natural tonal structure; it is a texture, not a light.
	vec2 pano_uv = vec2(atan(dir.x, -dir.z) / TAU + 0.5, acos(clamp(h, -1.0, 1.0)) / PI);
	vec3 pano = texture(panorama, pano_uv).rgb;
	col += pano * panorama_energy * smoothstep(-0.1, 0.25, h);

	// Stars, hidden by horizon haze, clouds and the moon's own glare.
	float star_mask = smoothstep(0.03, 0.45, h) * star_strength;
	float stars = star_layer(dir, 95.0, 0.03, 0.30) + star_layer(dir, 42.0, 0.045, 0.24) * 1.4;

	// Aurora: two slow curtains over the north wall of the ravine.
	float azimuth = atan(dir.x, -dir.z);
	vec3 aurora = vec3(0.0);
	if (aurora_strength > 0.001) {
		float base = 0.34 + 0.10 * sin(azimuth * 2.3 + 1.1) + 0.05 * sin(azimuth * 5.7);
		float height = h - base;
		float rays = 0.55 + 0.45 * value_noise(vec2(azimuth * 34.0, height * 3.0));
		float curtain = smoothstep(0.26, 0.0, abs(height - 0.10)) * smoothstep(-0.04, 0.05, height);
		float fade = smoothstep(-2.3, -1.4, azimuth) * smoothstep(0.6, -0.4, azimuth);
		vec3 green = vec3(0.16, 0.85, 0.52);
		vec3 violet = vec3(0.42, 0.24, 0.85);
		aurora = mix(green, violet, smoothstep(0.02, 0.32, height)) * curtain * rays * fade * aurora_strength;
	}

	// Clouds: a projected band layer, lit on the moon-facing edge for a silver lining.
	vec2 cp = dir.xz / (max(h, 0.0) + 0.16) * 0.55;
	float dens = cloud_density(cp + vec2(3.1, 1.7));
	float coverage = smoothstep(1.0 - cloud_cover - 0.05, 1.0 - cloud_cover + 0.28, dens);
	coverage *= smoothstep(-0.02, 0.16, h);
	vec2 to_moon = normalize(moon_dir.xz + vec2(0.0001)) * 0.09;
	float dens_lit = cloud_density(cp + vec2(3.1, 1.7) + to_moon);
	float lit = clamp((dens - dens_lit) * 5.0 + 0.5, 0.0, 1.0);
	float moon_near = exp(-moon_angle * 3.2);
	vec3 shadow_tone = mix(col, cloud_tint, 0.35) * 0.55;
	vec3 lit_tone = cloud_tint * (0.7 + 2.6 * moon_near) * (0.5 + 0.9 * lit);
	vec3 cloud_col = mix(shadow_tone, lit_tone, lit);
	col = mix(col, cloud_col, coverage * 0.88);

	col += aurora * (1.0 - coverage * 0.75);
	col += vec3(0.8, 0.88, 1.0) * stars * star_mask * (1.0 - coverage) * (1.0 - clamp(moon_near * 1.8, 0.0, 1.0));

	// Moon halo: tight glare, wide bloom, and (in clear ice-air) the 22 degree ring.
	float glare = 0.55 * exp(-moon_angle * 26.0) + 0.16 * exp(-moon_angle * 6.0) + 0.05 * exp(-moon_angle * 1.6);
	float ring = exp(-pow((moon_angle - 0.384) / 0.05, 2.0)) * halo_ring;
	col += halo_tint * (glare * (0.55 + 0.9 * coverage) * moon_disc * 0.05 + ring);

	// Crepuscular rays fan out of the moon; trees and crags draw over them, so
	// they read as light breaking through the ravine rim.
	{
		vec3 forward = normalize(moon_dir);
		vec3 up_ref = abs(forward.y) < 0.98 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
		vec3 right = normalize(cross(up_ref, forward));
		vec3 up = cross(forward, right);
		float spin = atan(dot(dir, up), dot(dir, right));
		float fan = value_noise(vec2(spin * 5.0, 3.7)) * 0.6 + value_noise(vec2(spin * 13.0, 1.3)) * 0.4;
		float ray = smoothstep(0.38, 0.85, fan) * exp(-moon_angle * 2.4) * step(0.0, moon_cos);
		col += halo_tint * ray * moon_rays * (1.0 - coverage * 0.5) * 0.35;
	}

	// The disc: an orthographic patch of the lunar face, lit as a waxing gibbous.
	if (moon_cos > 0.0 && moon_angle < moon_radius * 1.6) {
		vec3 forward = normalize(moon_dir);
		vec3 up_ref = abs(forward.y) < 0.98 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
		vec3 right = normalize(cross(up_ref, forward));
		vec3 up = cross(forward, right);
		vec2 q = vec2(dot(dir, right), dot(dir, up)) / moon_radius;
		float r = length(q);
		float edge = smoothstep(1.02, 0.96, r);
		if (edge > 0.0) {
			vec3 normal = vec3(q, sqrt(max(1.0 - r * r, 0.0)));
			vec3 albedo = texture(moon_surface, q * 0.5 + 0.5).rgb;
			float lambert = smoothstep(-0.05, 0.32, dot(normal, normalize(vec3(0.62, 0.22, 0.75))));
			float limb = pow(max(normal.z, 0.0), 0.32);
			vec3 surface = albedo * (0.06 + lambert * 1.0) * limb * moon_tint;
			// Thin cloud passes across the face instead of a hard cut-out.
			float veil = 1.0 - coverage * 0.55;
			col = mix(col, surface * moon_disc * veil, edge);
		}
	}

	COLOR = col;
}
