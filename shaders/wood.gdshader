shader_type spatial;

render_mode diffuse_lambert_wrap, specular_schlick_ggx;

uniform vec4 wood_color : source_color = vec4(0.32, 0.16, 0.07, 1.0);
uniform vec4 wood_color_dark : source_color = vec4(0.12, 0.055, 0.02, 1.0);

uniform float grain_scale : hint_range(1.0, 100.0) = 18.0;
uniform float grain_strength : hint_range(0.0, 2.0) = 0.7;

uniform float noise_scale : hint_range(1.0, 100.0) = 8.0;
uniform float noise_strength : hint_range(0.0, 1.0) = 0.25;

uniform float roughness : hint_range(0.0, 1.0) = 0.8;
uniform float bump_strength : hint_range(0.0, 2.0) = 0.25;


float random(vec2 p)
{
	return fract(
		sin(dot(p, vec2(12.9898, 78.233)))
		* 43758.5453
	);
}


float noise(vec2 p)
{
	vec2 i = floor(p);
	vec2 f = fract(p);

	f = f * f * (3.0 - 2.0 * f);

	float a = random(i);
	float b = random(i + vec2(1.0, 0.0));
	float c = random(i + vec2(0.0, 1.0));
	float d = random(i + vec2(1.0, 1.0));

	return mix(
		mix(a, b, f.x),
		mix(c, d, f.x),
		f.y
	);
}


float fbm(vec2 p)
{
	float value = 0.0;
	float amplitude = 0.5;

	for (int i = 0; i < 5; i++)
	{
		value += noise(p) * amplitude;
		p *= 2.0;
		amplitude *= 0.5;
	}

	return value;
}


float wood_pattern(vec2 uv)
{
	// Maserung läuft vertikal
	float distortion =
		fbm(uv * noise_scale)
		* noise_strength;

	float grain =
		sin(
			(uv.x + distortion)
			* grain_scale
		);

	grain = grain * 0.5 + 0.5;

	grain = pow(
		grain,
		1.5
	);

	return grain;
}


void fragment()
{
	vec2 uv = UV;

	float grain = wood_pattern(uv);

	float variation =
		fbm(
			uv * noise_scale
			+ vec2(17.4, 3.1)
		);


	// --------------------------------------------------
	// FARBE
	// --------------------------------------------------

	vec3 color = mix(
		wood_color_dark.rgb,
		wood_color.rgb,
		grain
	);

	color *= mix(
		0.85,
		1.15,
		variation
	);


	// --------------------------------------------------
	// BUMP / MASERUNG
	// --------------------------------------------------

	float offset = 0.002;

	float grain_x =
		wood_pattern(
			uv + vec2(offset, 0.0)
		);

	float grain_y =
		wood_pattern(
			uv + vec2(0.0, offset)
		);

	vec2 gradient = vec2(
		grain_x - grain,
		grain_y - grain
	);

	NORMAL_MAP = normalize(
		vec3(
			gradient.x * bump_strength + 0.5,
			gradient.y * bump_strength + 0.5,
			1.0
		)
	);


	ALBEDO = color;

	METALLIC = 0.0;

	ROUGHNESS =
		clamp(
			roughness
			+ (1.0 - grain) * 0.08,
			0.0,
			1.0
		);
}