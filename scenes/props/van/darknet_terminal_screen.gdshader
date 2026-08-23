shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform sampler2D terminal_texture : source_color, filter_nearest, repeat_disable;
uniform float curvature : hint_range(0.0, 0.12, 0.001) = 0.025;
uniform float scanline_strength : hint_range(0.0, 0.5, 0.01) = 0.16;
uniform float grille_strength : hint_range(0.0, 0.25, 0.01) = 0.045;
uniform float noise_strength : hint_range(0.0, 0.15, 0.005) = 0.018;
uniform float emission_strength : hint_range(0.0, 4.0, 0.05) = 1.35;
uniform vec3 phosphor_tint : source_color = vec3(0.86, 1.0, 0.9);

float random_value(vec2 coordinates) {
	return fract(sin(dot(coordinates, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 centered = UV * 2.0 - 1.0;
	float radius_squared = dot(centered, centered);
	vec2 warped = centered * (1.0 + curvature * radius_squared);
	vec2 screen_uv = warped * 0.5 + 0.5;
	float inside = (
		step(0.0, screen_uv.x)
		* step(screen_uv.x, 1.0)
		* step(0.0, screen_uv.y)
		* step(screen_uv.y, 1.0)
	);

	vec2 safe_uv = clamp(screen_uv, vec2(0.0), vec2(1.0));
	vec2 chroma_offset = vec2(0.0012, 0.0);
	vec3 color;
	color.r = texture(terminal_texture, safe_uv + chroma_offset).r;
	color.g = texture(terminal_texture, safe_uv).g;
	color.b = texture(terminal_texture, safe_uv - chroma_offset).b;

	float scanline = 1.0 - scanline_strength * (
		0.5 + 0.5 * sin(safe_uv.y * 640.0 * 6.2831853)
	);
	float grille = 1.0 - grille_strength * (
		0.5 + 0.5 * sin(safe_uv.x * 1024.0 * 2.0943951)
	);
	float noise = (
		random_value(floor(safe_uv * vec2(1024.0, 640.0)) + TIME * 47.0)
		- 0.5
	) * noise_strength;
	float vignette = 1.0 - smoothstep(0.25, 1.45, radius_squared) * 0.42;

	color = max(color * scanline * grille * vignette + noise, vec3(0.0));
	color *= phosphor_tint * inside;
	ALBEDO = color;
	EMISSION = color * emission_strength;
}
