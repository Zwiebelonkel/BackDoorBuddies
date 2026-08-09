shader_type spatial;

render_mode cull_disabled;

uniform vec3 grass_color : source_color = vec3(0.25, 0.55, 0.15);

uniform float wind_strength : hint_range(0.0, 1.0) = 0.2;
uniform float wind_speed : hint_range(0.0, 10.0) = 2.0;
uniform float wind_scale : hint_range(0.1, 10.0) = 1.5;

void vertex() {
	// 0 unten, 1 oben am Grashalm
	float height = UV.y;

	// Unterschiedliche Bewegung je nach Weltposition
	float wave =
		sin(
			TIME * wind_speed +
			INSTANCE_CUSTOM.x * 10.0 +
			VERTEX.x * wind_scale
		);

	// Nur die Spitze bewegen
	VERTEX.x += wave * wind_strength * height;
}

void fragment() {
	ALBEDO = grass_color;
	ROUGHNESS = 1.0;
}