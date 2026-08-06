class_name PistolHeld
extends Node3D

signal fired

@export_group("Firing")
@export var fire_cooldown: float = 0.22
@export var automatic: bool = false

@export_group("Recoil Position")
@export var recoil_back_distance: float = 0.09
@export var recoil_up_distance: float = 0.025
@export var recoil_side_distance: float = 0.01

@export_group("Recoil Rotation")
@export var recoil_rotation_degrees := Vector3(
	-10.0,
	0.0,
	2.0
)

@export_group("Recoil Timing")
@export var recoil_duration: float = 0.045
@export var return_duration: float = 0.14

@export_group("Random Recoil")
@export var random_recoil_enabled: bool = true
@export var random_rotation_degrees: float = 1.5
@export var random_side_distance: float = 0.008

var _can_fire := true
var _rest_position: Vector3
var _rest_rotation_degrees: Vector3
var _active_tween: Tween


func _ready() -> void:
	_rest_position = position
	_rest_rotation_degrees = rotation_degrees


func use_primary() -> void:
	if not _can_fire:
		return

	_can_fire = false

	# Hierüber kann der Player später den echten Schuss ausführen.
	fired.emit()

	await _play_recoil_animation()

	var remaining_cooldown := maxf(
		fire_cooldown - recoil_duration - return_duration,
		0.0
	)

	if remaining_cooldown > 0.0:
		await get_tree().create_timer(remaining_cooldown).timeout

	_can_fire = true


func _play_recoil_animation() -> void:
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()

	var random_side := 0.0
	var random_pitch := 0.0
	var random_yaw := 0.0
	var random_roll := 0.0

	if random_recoil_enabled:
		random_side = randf_range(
			-random_side_distance,
			random_side_distance
		)

		random_pitch = randf_range(
			-random_rotation_degrees,
			random_rotation_degrees
		)

		random_yaw = randf_range(
			-random_rotation_degrees,
			random_rotation_degrees
		)

		random_roll = randf_range(
			-random_rotation_degrees,
			random_rotation_degrees
		)

	# Positive Z-Richtung bedeutet bei einem Kamerakind:
	# zurück zur Kamera.
	var recoil_position := (
		_rest_position
		+ Vector3(
			recoil_side_distance + random_side,
			recoil_up_distance,
			recoil_back_distance
		)
	)

	var recoil_rotation := (
		_rest_rotation_degrees
		+ recoil_rotation_degrees
		+ Vector3(
			random_pitch,
			random_yaw,
			random_roll
		)
	)

	_active_tween = create_tween()
	_active_tween.set_trans(Tween.TRANS_QUAD)
	_active_tween.set_ease(Tween.EASE_OUT)

	# Schneller Rückstoß.
	_active_tween.tween_property(
		self,
		"position",
		recoil_position,
		recoil_duration
	)

	_active_tween.parallel().tween_property(
		self,
		"rotation_degrees",
		recoil_rotation,
		recoil_duration
	)

	# Etwas langsamer in die Ruheposition zurück.
	_active_tween.set_trans(Tween.TRANS_SINE)
	_active_tween.set_ease(Tween.EASE_IN_OUT)

	_active_tween.tween_property(
		self,
		"position",
		_rest_position,
		return_duration
	)

	_active_tween.parallel().tween_property(
		self,
		"rotation_degrees",
		_rest_rotation_degrees,
		return_duration
	)

	await _active_tween.finished
