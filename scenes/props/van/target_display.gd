extends Node3D

const ATTRIBUTE_LABELS := {
	&"age": "ALTER",
	&"hair": "HAARE",
	&"height": "GRÖSSE",
	&"skin_tone": "TEINT",
}

@onready var viewport: SubViewport = $SubViewport
@onready var screen: MeshInstance3D = $MeshInstance3D
@onready var case_label: Label = (
	$SubViewport/Interface/Margin/Content/CaseLabel
)
@onready var progress_label: Label = (
	$SubViewport/Interface/Margin/Content/ProgressLabel
)
@onready var status_label: Label = (
	$SubViewport/Interface/Margin/Content/StatusLabel
)
@onready var value_labels := {
	&"age": $SubViewport/Interface/Margin/Content/Attributes/AgeValue,
	&"hair": $SubViewport/Interface/Margin/Content/Attributes/HairValue,
	&"height": $SubViewport/Interface/Margin/Content/Attributes/HeightValue,
	&"skin_tone": $SubViewport/Interface/Margin/Content/Attributes/SkinToneValue,
}


func _ready() -> void:
	_configure_screen_material()

	if not SessionManager.session_state_changed.is_connected(
		_on_session_state_changed
	):
		SessionManager.session_state_changed.connect(
			_on_session_state_changed
		)

	_refresh_display()


func _on_session_state_changed(_snapshot: Dictionary) -> void:
	_refresh_display()


func _refresh_display() -> void:
	case_label.text = "AKTE // %s" % SessionManager.target_code

	var required := SessionManager.get_required_target_clues()
	var revealed := SessionManager.get_revealed_target_clues()
	progress_label.text = "IDENTIFIZIERUNG  %d / %d" % [
		revealed.size(),
		required.size(),
	]

	for clue_type: StringName in ATTRIBUTE_LABELS:
		var value_label := value_labels[clue_type] as Label

		if clue_type not in required:
			value_label.text = "---"
			value_label.modulate = Color(0.28, 0.4, 0.31, 1)
		elif clue_type in revealed:
			value_label.text = SessionManager.get_target_attribute_value(
				clue_type
			)
			value_label.modulate = Color(0.35, 1, 0.52, 1)
		else:
			value_label.text = "???"
			value_label.modulate = Color(1, 0.68, 0.18, 1)

	if SessionManager.is_target_identified():
		status_label.text = "ZIEL IDENTIFIZIERT"
		status_label.modulate = Color(0.25, 1, 0.42, 1)
	else:
		status_label.text = "HINWEISE IN DEN VAN BRINGEN"
		status_label.modulate = Color(0.76, 0.84, 0.76, 1)


func _configure_screen_material() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_texture = viewport.get_texture()
	material.emission_enabled = true
	material.emission_texture = viewport.get_texture()
	material.emission_energy_multiplier = 1.4
	material.flags_unshaded = true
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	screen.material_override = material
