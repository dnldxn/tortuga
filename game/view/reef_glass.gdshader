shader_type canvas_item;
render_mode unshaded;

// Refined Reef Glass study: gentle swells, 4–8 second whitecaps, subtle sunlight.
// Geometry/bottom are world-anchored. SCREEN_UV is used only for the sun reflection.
uniform vec2 arena_size;
uniform float world_scale;
uniform float shallow_fade;
uniform vec3 swell_weights;
uniform float texture_weight;
uniform vec2 whitecap_lifetime;
uniform vec2 wind_direction = vec2(1.0, 0.0);
uniform vec2 surface_drift = vec2(0.0);
uniform float animation_time = 0.0;
varying vec2 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec2 hash2(vec2 p) {
	return vec2(hash(p), hash(p + 71.37));
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	return noise(p) * 0.57 + noise(p * 2.03 + 13.0) * 0.28 + noise(p * 4.01 - 9.0) * 0.15;
}

float height_at(vec2 p, vec2 wind) {
	vec2 side = vec2(-wind.y, wind.x);
	float a = dot(p, wind);
	float b = dot(p, side);
	float warp = (fbm(p * 1.35) - 0.5) * 5.0;
	float broad = sin(a * 5.8 + sin(b * 2.2) * 0.85 + warp) * (0.6 + 0.4 * noise(p * 1.8));
	float middle = sin(a * 13.2 + b * 1.6 + sin(b * 4.4) * 0.85 + warp * 0.7);
	float fine = sin(a * 32.0 - b * 4.5 + sin(b * 11.0) * 0.8);
	return dot(vec3(broad, middle, fine), swell_weights) + (fbm(p * 9.0) - 0.5) * texture_weight;
}

float caustic(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 o = vec2(float(x), float(y));
			vec2 r = o + hash2(cell + o) * 0.7 + 0.15 - f;
			float d = dot(r, r);
			if (d < d1) {
				d2 = d1;
				d1 = d;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return 1.0 - smoothstep(0.012, 0.09, d2 - d1);
}

float whitecaps(vec2 p, vec2 wind) {
	vec2 side = vec2(-wind.y, wind.x);
	vec2 q = vec2(dot(p, wind), dot(p, side)) * vec2(3.1, 1.55);
	vec2 id = floor(q);
	vec2 f = fract(q);
	float result = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 o = vec2(float(x), float(y));
			vec2 key = id + o;
			float seed = hash(key + 12.0);
			float age = animation_time / mix(whitecap_lifetime.x, whitecap_lifetime.y, seed) + seed * 17.0;
			float cycle = floor(age);
			float life = fract(age);
			// Re-seed while invisible so crests fade instead of popping to new positions.
			vec2 r = o + 0.18 + hash2(key + cycle * 23.4) * 0.64 - f;
			float envelope = smoothstep(0.08, 0.3, life) * (1.0 - smoothstep(0.48, 0.88, life));
			float crest_length = 0.18 + hash(key + cycle + 91.0) * 0.22;
			float taper = 1.0 - smoothstep(crest_length * 0.5, crest_length, abs(r.y));
			float bend = r.x + 0.25 * r.y * r.y + 0.012 * sin(r.y * 39.0 + seed * 20.0);
			float line = 1.0 - smoothstep(0.010, 0.023, abs(bend));
			float broken = smoothstep(0.24, 0.56, noise(vec2(r.y * 35.0 + cycle * 7.0, seed * 50.0)));
			float allowed = step(0.35, hash(key + cycle * 3.7));
			result = max(result, line * taper * envelope * broken * allowed);
		}
	}
	return result;
}

void fragment() {
	// The browser study uses Y-up; Godot world headings use clockwise Y-down.
	vec2 centered = (world_position - arena_size * 0.5) / world_scale;
	vec2 world = vec2(centered.x, -centered.y);
	vec2 wind = vec2(wind_direction.x, -wind_direction.y);
	vec2 p = world - vec2(surface_drift.x, -surface_drift.y);
	float h = height_at(p, wind);
	float e = 0.018;
	vec2 slope = vec2(
		height_at(p + vec2(e, 0.0), wind) - height_at(p - vec2(e, 0.0), wind),
		height_at(p + vec2(0.0, e), wind) - height_at(p - vec2(0.0, e), wind)) / (2.0 * e);
	vec3 normal = normalize(vec3(-slope * 0.10, 1.0));
	float diffuse = dot(normal, normalize(vec3(-0.5, 0.7, 1.3)));

	// Broad depth patches cover the whole arena; reef detail never follows the camera.
	float depth = clamp(0.45 + (fbm(world * 0.12) - 0.5) * 0.65
		+ (fbm(world * 0.75) - 0.5) * 0.45, 0.05, 0.9);
	vec2 edge = min(world_position, arena_size - world_position);
	depth = mix(0.1, depth, smoothstep(0.0, shallow_fade, min(edge.x, edge.y)));
	vec3 col = mix(vec3(0.13, 0.77, 0.69), vec3(0.018, 0.48, 0.61), depth);
	vec2 bottom = world + slope * 0.012;
	float reef = fbm(bottom * 2.2);
	float patch = smoothstep(0.57, 0.70, reef) * (1.0 - smoothstep(0.45, 0.90, depth));
	float facet = floor(noise(bottom * 19.0) * 5.0) / 5.0;
	vec3 rock = mix(vec3(0.08, 0.39, 0.37), vec3(0.33, 0.53, 0.31), facet);
	col = mix(col, rock, patch * 0.66);
	float c = caustic(bottom * 6.0
		+ vec2(sin(animation_time * 0.35), cos(animation_time * 0.35)) * 0.10);
	col += vec3(0.52, 0.75, 0.39) * c * (1.0 - depth) * 0.16;
	float shoulder = smoothstep(-0.65, 0.75, h);
	col += vec3(0.10, 0.19, 0.16) * (shoulder - 0.5);
	col += vec3(0.11, 0.22, 0.20) * (diffuse - 0.85) * 0.72;
	col += (fbm(p * 18.0) - 0.5) * 0.022;

	vec3 light = normalize(vec3(0.28, 0.48, 1.8));
	float spec = pow(max(dot(normal, light), 0.0), 160.0);
	vec2 sun_offset = (vec2(SCREEN_UV.x, 1.0 - SCREEN_UV.y) - vec2(0.78, 0.8)) * vec2(1.7, 1.1);
	float sun_patch = exp(-dot(sun_offset, sun_offset) * 2.4);
	float twinkle = 0.35 + 0.65 * pow(0.5 + 0.5 * sin(animation_time * 2.0
		+ hash(floor(p * 36.0)) * 6.28318530718), 3.0);
	float sparkle = spec * smoothstep(0.58, 0.86, noise(p * 53.0)) * sun_patch * twinkle;
	col += vec3(1.0, 0.97, 0.76) * sparkle * 0.58;
	col = mix(col, vec3(0.94, 0.99, 0.88), whitecaps(p, wind) * 0.72);
	COLOR = vec4(col, 1.0);
}
