shader_type canvas_item;
render_mode unshaded;

uniform vec4 color_top : source_color = vec4(0.006, 0.018, 0.012, 1.0);
uniform vec4 color_bottom : source_color = vec4(0.002, 0.005, 0.004, 1.0);
uniform vec4 accent : source_color = vec4(0.08, 1.0, 0.32, 1.0);


void fragment() {
	vec2 uv = UV;
	vec3 color = mix(color_bottom.rgb, color_top.rgb, 1.0 - uv.y);

	vec2 grid_uv = vec2(uv.x * 24.0, uv.y * 14.0 + TIME * 0.035);
	vec2 grid_distance = abs(fract(grid_uv) - 0.5) / fwidth(grid_uv);
	float grid = 1.0 - min(min(grid_distance.x, grid_distance.y), 1.0);
	color += accent.rgb * grid * 0.025;

	float horizon = exp(-abs(uv.y - 0.66) * 13.0);
	float sweep = 0.5 + 0.5 * sin(uv.x * 8.0 - TIME * 0.7);
	color += accent.rgb * horizon * (0.025 + sweep * 0.018);

	float glow = exp(-distance(uv, vec2(0.17, 0.5)) * 5.5);
	color += accent.rgb * glow * 0.085;

	float scanline = 0.985 + 0.015 * sin(FRAGCOORD.y * 1.8 + TIME * 2.0);
	float vignette = 1.0 - smoothstep(0.2, 0.82, distance(uv, vec2(0.5)));
	color *= scanline * mix(0.52, 1.0, vignette);

	COLOR = vec4(color, 1.0);
}
