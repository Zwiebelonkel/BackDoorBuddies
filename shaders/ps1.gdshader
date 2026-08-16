shader_type spatial;

render_mode vertex_lighting,
			skip_vertex_transform,
			specular_schlick_ggx,
			diffuse_lambert_wrap;


// =====================================================
// ALBEDO
// =====================================================

// Keine Textur gesetzt -> automatisch WEISS.
// Dadurch funktioniert die Albedo-Farbe auch alleine.
uniform sampler2D albedo : source_color, hint_default_white;

uniform vec4 albedo_color : source_color =
	vec4(1.0, 1.0, 1.0, 1.0);


// =====================================================
// SPECULAR
// =====================================================

// Keine Specular-Textur -> Schwarz = kein Specular
uniform sampler2D specular : hint_default_black;


// =====================================================
// EMISSION
// =====================================================

// GANZ WICHTIG:
// Keine Emission-Textur -> Schwarz = keine Emission
uniform sampler2D emission : source_color, hint_default_black;


// =====================================================
// PSX SETTINGS
// =====================================================

uniform float jitter : hint_range(0.0, 1.0) = 0.5;

uniform bool jitter_z_coordinate = true;
uniform bool jitter_depth_independent = true;

uniform bool affine_texture_mapping = true;

uniform float alpha_scissor : hint_range(0.0, 1.0) = 0.5;


// =====================================================
// VARYINGS
// =====================================================

varying float vertex_depth;


// =====================================================
// VERTEX
// =====================================================

void vertex() {
	// Manuelle Transformation,
	// da skip_vertex_transform aktiviert ist.
	VERTEX = (
		MODELVIEW_MATRIX *
		vec4(VERTEX, 1.0)
	).xyz;


	// Normalen transformieren
	NORMAL = normalize(
		(
			MODELVIEW_MATRIX *
			vec4(NORMAL, 0.0)
		).xyz
	);


	float z_orig = VERTEX.z;


	float resolution = min(
		VIEWPORT_SIZE.x,
		VIEWPORT_SIZE.y
	);


	float i = max(
		(1.0 - jitter) *
		resolution *
		0.5,
		1.0
	);


	// =================================================
	// PSX VERTEX JITTER
	// =================================================

	if (jitter_depth_independent) {

		float w = (
			PROJECTION_MATRIX *
			vec4(VERTEX, 1.0)
		).w;


		VERTEX.xy = round(
			(VERTEX.xy / w) * i
		) / i * w;


		if (jitter_z_coordinate) {

			VERTEX.z = round(
				(VERTEX.z / w) * i
			) / i * w;

		}

	} else {

		VERTEX = round(
			VERTEX * i
		) / i;


		if (!jitter_z_coordinate) {
			VERTEX.z = z_orig;
		}
	}


	// =================================================
	// AFFINE TEXTURE MAPPING
	// =================================================

	vertex_depth = VERTEX.z;


	if (affine_texture_mapping) {
		UV *= vertex_depth;
	}
}


// =====================================================
// FRAGMENT
// =====================================================

void fragment() {

	vec2 uv = UV;


	// =================================================
	// AFFINE TEXTURE MAPPING
	// =====================================================

	if (affine_texture_mapping) {

		float safe_depth = vertex_depth;


		if (abs(safe_depth) < 0.0001) {
			safe_depth = -0.0001;
		}


		uv /= safe_depth;
	}


	// =================================================
	// ALBEDO
	// =====================================================

	// Wenn KEINE Textur gesetzt wurde:
	//
	// albedo_tex = weiß
	//
	// Dadurch:
	//
	// weiß * albedo_color
	// =
	// albedo_color

	vec4 albedo_tex = texture(
		albedo,
		uv
	);


	vec4 final_albedo =
		albedo_tex *
		albedo_color;


	ALBEDO = final_albedo.rgb;

	ALPHA = final_albedo.a;


	// =================================================
	// ALPHA
	// =====================================================

	ALPHA_SCISSOR_THRESHOLD =
		alpha_scissor;


	// =================================================
	// EMISSION
	// =====================================================

	// Ohne Textur ist das automatisch SCHWARZ
	// und verändert die Albedo nicht.

	EMISSION = texture(
		emission,
		uv
	).rgb;


	// =================================================
	// SPECULAR
	// =====================================================

	// Ohne Textur automatisch 0.

	SPECULAR = texture(
		specular,
		uv
	).r;


	// =================================================
	// ROUGHNESS
	// =====================================================

	ROUGHNESS = 0.8;
}