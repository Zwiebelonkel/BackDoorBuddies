shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

uniform sampler2D dirt_texture : source_color;
uniform sampler2D scratches_texture : source_color;

uniform float dirt_strength : hint_range(0.0, 2.0) = 0.55;
uniform float scratch_strength : hint_range(0.0, 2.0) = 0.75;
uniform float vignette_strength : hint_range(0.0, 2.0) = 0.65;
uniform float distortion_strength : hint_range(0.0, 0.05) = 0.006;
uniform float blur_strength : hint_range(0.0, 5.0) = 0.6;

uniform float scratch_scroll_speed : hint_range(-1.0, 1.0) = 0.015;
uniform float flicker_strength : hint_range(0.0, 0.5) = 0.035;

uniform vec3 dirt_color : source_color = vec3(0.32, 0.27, 0.20);
uniform vec3 scratch_color : source_color = vec3(0.85, 0.82, 0.72);

float random(vec2 uv) {
	return fract(
		sin(dot(uv, vec2(12.9898, 78.233))) * 43758.5453
	);
}

void fragment() {
	vec2 uv = SCREEN_UV;

	// Leichte Linsenwölbung
	vec2 centered_uv = uv - vec2(0.5);
	float distance_from_center = length(centered_uv);

	vec2 distorted_uv = uv
		+ centered_uv
		* distance_from_center
		* distortion_strength;

	distorted_uv = clamp(distorted_uv, vec2(0.001), vec2(0.999));

	// Kamerabild
	vec3 screen_color = textureLod(
		screen_texture,
		distorted_uv,
		blur_strength
	).rgb;

	// Dirt-Textur bleibt fest auf der Linse
	vec4 dirt_sample = texture(dirt_texture, UV);

	// Kratzer bewegen sich ganz leicht
	vec2 scratch_uv = UV;
	scratch_uv.y += TIME * scratch_scroll_speed;

	vec4 scratch_sample = texture(
		scratches_texture,
		scratch_uv
	);

	float dirt_mask = dirt_sample.r * dirt_sample.a;
	float scratch_mask = scratch_sample.r * scratch_sample.a;

	// Kleine unregelmäßige Helligkeitsschwankung
	float noise = random(
		vec2(
			floor(TIME * 12.0),
			UV.y
		)
	);

	float flicker = 1.0
		- flicker_strength
		* noise;

	screen_color *= flicker;

	// Dunkler Schmutz
	screen_color = mix(
		screen_color,
		screen_color * dirt_color,
		dirt_mask * dirt_strength
	);

	// Helle Kratzerspuren
	screen_color += scratch_color
		* scratch_mask
		* scratch_strength;

	// Vignette
	float vignette = smoothstep(
		0.35,
		0.85,
		distance_from_center
	);

	screen_color *= 1.0
		- vignette
		* vignette_strength;

	COLOR = vec4(screen_color, 1.0);
}