class_name KnifeHeld
extends Node3D

@export_group("Attack")
@export var attack_cooldown: float = 0.45
@export var stab_distance: float = 0.35
@export var stab_duration: float = 0.08
@export var return_duration: float = 0.16
@export var attack_rotation_degrees := Vector3(-25.0, 0.0, -10.0)

var _can_attack := true
var _rest_position: Vector3
var _rest_rotation_degrees: Vector3


func _ready() -> void:
	_rest_position = position
	_rest_rotation_degrees = rotation_degrees


func use_primary() -> void:
	if not _can_attack:
		return

	_can_attack = false

	await _play_stab_animation()
	await get_tree().create_timer(
		maxf(attack_cooldown - stab_duration - return_duration, 0.0)
	).timeout

	_can_attack = true


func _play_stab_animation() -> void:
	var attack_position := _rest_position + Vector3(0.0, 0.0, -stab_distance)
	var attack_rotation := _rest_rotation_degrees + attack_rotation_degrees

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)

	tween.tween_property(
		self,
		"position",
		attack_position,
		stab_duration
	)

	tween.parallel().tween_property(
		self,
		"rotation_degrees",
		attack_rotation,
		stab_duration
	)

	tween.set_ease(Tween.EASE_IN_OUT)

	tween.tween_property(
		self,
		"position",
		_rest_position,
		return_duration
	)

	tween.parallel().tween_property(
		self,
		"rotation_degrees",
		_rest_rotation_degrees,
		return_duration
	)

	await tween.finished
