shader_type canvas_item;
render_mode unshaded;

uniform float radius : hint_range(0.2, 0.5) = 0.46;
uniform float edge_softness : hint_range(0.0001, 0.03) = 0.004;
uniform float line_width : hint_range(0.0005, 0.02) = 0.0025;
uniform vec4 reticle_color : source_color = vec4(0.01, 0.02, 0.012, 0.92);
uniform vec4 lens_tint : source_color = vec4(0.04, 0.11, 0.07, 0.08);

void fragment() {
	vec2 point = SCREEN_UV * 2.0 - 1.0;
	point.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;

	float distance_from_center = length(point);
	float outside = smoothstep(
		radius - edge_softness,
		radius + edge_softness,
		distance_from_center
	);
	float inside = 1.0 - outside;

	float horizontal = 1.0 - smoothstep(
		line_width,
		line_width + edge_softness,
		abs(point.y)
	);
	float vertical = 1.0 - smoothstep(
		line_width,
		line_width + edge_softness,
		abs(point.x)
	);

	float center_gap = smoothstep(0.012, 0.025, distance_from_center);
	float crosshair = max(horizontal, vertical) * inside * center_gap;
	float ring = 1.0 - smoothstep(
		line_width,
		line_width + edge_softness,
		abs(distance_from_center - radius)
	);

	vec4 color = lens_tint * inside;
	color = mix(color, reticle_color, max(crosshair, ring));
	color = mix(color, vec4(0.0, 0.0, 0.0, 1.0), outside);
	COLOR = color;
}

