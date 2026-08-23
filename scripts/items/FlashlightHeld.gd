class_name FlashlightHeld
extends Node3D

signal light_toggled(enabled: bool)

@export var starts_enabled := false

@onready var beam: SpotLight3D = $Beam

var _light_enabled := false


func _ready() -> void:
	set_light_enabled(starts_enabled)


func use_primary() -> void:
	set_light_enabled(not _light_enabled)


func set_light_enabled(enabled: bool) -> void:
	_light_enabled = enabled

	if is_instance_valid(beam):
		beam.visible = enabled

	light_toggled.emit(enabled)


func is_light_enabled() -> bool:
	return _light_enabled
