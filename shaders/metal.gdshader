shader_type spatial;

render_mode diffuse_lambert_wrap, specular_schlick_ggx;

uniform vec4 metal_color : source_color = vec4(0.28, 0.30, 0.32, 1.0);
uniform vec4 dark_color : source_color = vec4(0.08, 0.09, 0.10, 1.0);

uniform float metallic_strength : hint_range(0.0, 1.0) = 0.75;
uniform float roughness : hint_range(0.0, 1.0) = 0.72;

uniform float sheet_scale : hint_range(1.0, 100.0) = 22.0;

uniform float scratch_scale : hint_range(1.0, 500.0) = 120.0;
uniform float scratch_strength : hint_range(0.0, 1.0) = 0.18;

uniform float dirt_scale : hint_range(1.0, 100.0) = 14.0;
uniform float dirt_strength : hint_range(0.0, 1.0) = 0.22;

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


float fbm(vec2 uv)
{
	float value = 0.0;
	float amplitude = 0.5;

	for (int i = 0; i < 5; i++)
	{
		value += noise(uv) * amplitude;
		uv *= 2.0;
		amplitude *= 0.5;
	}

	return value;
}


void fragment()
{
	vec2 uv = UV;


	// --------------------------------------------------
	// GROBE METALLOBERFLÄCHE
	// --------------------------------------------------

	float surface_noise =
		fbm(uv * sheet_scale);


	// --------------------------------------------------
	// DRECK / FLECKEN
	// --------------------------------------------------

	float dirt =
		fbm(
			uv * dirt_scale
			+ vec2(14.7, 4.2)
		);

	dirt = smoothstep(
		0.45,
		0.75,
		dirt
	);


	// --------------------------------------------------
	// FEINE KRATZER
	// --------------------------------------------------

	vec2 scratch_uv = uv;

	scratch_uv.y *= scratch_scale;
	scratch_uv.x *= 3.0;

	float scratch_noise =
		random(
			vec2(
				floor(scratch_uv.x),
				floor(scratch_uv.y)
			)
		);

	float scratches =
		step(
			1.0 - scratch_strength,
			scratch_noise
		);


	// --------------------------------------------------
	// FARBE
	// --------------------------------------------------

	vec3 color = metal_color.rgb;

	color *= mix(
		0.8,
		1.15,
		surface_noise
	);

	color = mix(
		color,
		dark_color.rgb,
		dirt * dirt_strength
	);

	color *= mix(
		1.0,
		0.65,
		scratches
	);


	// --------------------------------------------------
	// NORMAL / BUMP
	// --------------------------------------------------

	float px = fbm(
		(uv + vec2(0.002, 0.0))
		* sheet_scale
	);

	float py = fbm(
		(uv + vec2(0.0, 0.002))
		* sheet_scale
	);

	vec2 normal_offset =
		vec2(
			px - surface_noise,
			py - surface_noise
		);

	NORMAL_MAP = normalize(
		vec3(
			normal_offset.x * bump_strength + 0.5,
			normal_offset.y * bump_strength + 0.5,
			1.0
		)
	);


	// --------------------------------------------------
	// MATERIAL
	// --------------------------------------------------

	ALBEDO = color;

	METALLIC = metallic_strength;

	ROUGHNESS =
		clamp(
			roughness
			+ dirt * 0.15
			+ scratches * 0.12,
			0.0,
			1.0
		);
}