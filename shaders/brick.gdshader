shader_type spatial;

const vec3 MONOCHROME_SCALE = vec3(
	0.298912,
	0.586611,
	0.114478
);

uniform float noise_scale = 700.0;

uniform vec2 brick_scale = vec2(20.0, 10.0);

uniform float mortar_width_x : hint_range(0.0, 0.4) = 0.06;
uniform float mortar_width_y : hint_range(0.0, 0.4) = 0.08;

uniform vec4 brick_color : source_color =
	vec4(0.745, 0.341, 0.219, 1.0);

uniform vec4 brick_color2 : source_color =
	vec4(0.37, 0.12, 0.04, 1.0);

uniform vec4 mortar_joint_color : source_color =
	vec4(1.0, 0.987, 0.987, 1.0);


vec2 random(vec2 pos)
{
	return fract(
		sin(
			vec2(
				dot(pos, vec2(12.9898, 78.233)),
				dot(pos, vec2(-148.998, -65.233))
			)
		) * 43758.5453
	);
}


vec2 value_noise(vec2 pos)
{
	vec2 p = floor(pos);
	vec2 f = fract(pos);

	vec2 v00 = random(p + vec2(0.0, 0.0));
	vec2 v10 = random(p + vec2(1.0, 0.0));
	vec2 v01 = random(p + vec2(0.0, 1.0));
	vec2 v11 = random(p + vec2(1.0, 1.0));

	vec2 u = f * f * (3.0 - 2.0 * f);

	return mix(
		mix(v00, v10, u.x),
		mix(v01, v11, u.x),
		u.y
	);
}


vec3 gen_brick_color(vec2 uv, float noise_amount)
{
	// -------------------------------------------------
	// ZIEGELRASTER
	// -------------------------------------------------

	vec2 brick_uv = uv;

	float row = floor(brick_uv.y);

	// Jede zweite Reihe um einen halben Stein verschieben
	if (mod(row, 2.0) >= 1.0) {
		brick_uv.x += 0.5;
	}

	vec2 brick_id = floor(brick_uv);
	vec2 local_uv = fract(brick_uv);


	// -------------------------------------------------
	// HARTE RECHTECKIGE KANTEN
	// Corner Radius = 0
	// -------------------------------------------------

	float inside_left =
		step(mortar_width_x, local_uv.x);

	float inside_right =
		step(local_uv.x, 1.0 - mortar_width_x);

	float inside_top =
		step(mortar_width_y, local_uv.y);

	float inside_bottom =
		step(local_uv.y, 1.0 - mortar_width_y);

	float brick_mask =
		inside_left *
		inside_right *
		inside_top *
		inside_bottom;


	// -------------------------------------------------
	// FARBE PRO ZIEGEL
	// -------------------------------------------------

	float color_select =
		random(brick_id).x;

	vec3 current_brick_color = mix(
		brick_color.rgb,
		brick_color2.rgb,
		color_select
	);


	// ganz leichte Farbvariation
	float variation =
		(random(uv * 5.0).x - 0.5)
		* noise_amount;

	current_brick_color += variation * 0.1;


	return mix(
		mortar_joint_color.rgb,
		current_brick_color,
		brick_mask
	);
}


vec2 noise_tex(vec2 uv)
{
	return (
		value_noise(uv * 0.984864) * 0.5
		+ value_noise(uv * 2.543) * 0.25
		+ value_noise(uv * 9.543543) * 0.125
		+ value_noise(uv * 21.65436) * 0.0625
		+ value_noise(uv * 42.0) * 0.03125
		+ value_noise(uv * 87.135148) * 0.015625
		+ value_noise(uv * 340.66534654) * 0.0078125
	);
}


void fragment()
{
	vec2 uv = UV * brick_scale;

	float c[9];

	vec2 pixel_size = vec2(0.02, 0.02);

	for (int y = 0; y < 3; y++)
	{
		for (int x = 0; x < 3; x++)
		{
			vec2 offset = vec2(
				float(x - 1),
				float(y - 1)
			) * pixel_size;

			vec2 v = uv + offset;

			vec2 nv =
				UV * noise_scale + offset;

			c[y * 3 + x] =
				length(noise_tex(nv))
				+ dot(
					gen_brick_color(v, 0.15),
					MONOCHROME_SCALE
				);
		}
	}


	vec2 sobel_filter = clamp(
		vec2(
			(
				c[0] * -1.0
				+ c[3] * -2.0
				+ c[6] * -1.0
				+ c[2]
				+ c[5] * 2.0
				+ c[8]
			),
			(
				c[0] * -1.0
				+ c[1] * -2.0
				+ c[2] * -1.0
				+ c[6]
				+ c[7] * 2.0
				+ c[8]
			)
		),
		vec2(-1.0),
		vec2(1.0)
	) * 0.5;


	NORMAL_MAP = normalize(
		vec3(
			sobel_filter.x + 0.5,
			-sobel_filter.y + 0.5,
			1.0
		)
	);

	ALBEDO = gen_brick_color(
		uv,
		0.3
	);

	ROUGHNESS = 0.95;
	METALLIC = 0.0;
}