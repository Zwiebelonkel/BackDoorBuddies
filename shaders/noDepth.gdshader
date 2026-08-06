shader_type spatial;

render_mode depth_test_disabled,
			depth_draw_never,
			cull_back,
			shadows_disabled;

uniform sampler2D albedo_texture : source_color, filter_nearest_mipmap;
uniform vec4 albedo_color : source_color = vec4(1.0);

uniform float roughness : hint_range(0.0, 1.0) = 0.65;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float specular : hint_range(0.0, 1.0) = 0.5;

void fragment() {
	vec4 texture_color = texture(albedo_texture, UV);

	ALBEDO = texture_color.rgb * albedo_color.rgb;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	SPECULAR = specular;
}