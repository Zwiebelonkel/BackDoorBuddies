class_name MachinePistolHeld
extends PistolHeld


@export_group("Machine Pistol")
@export_range(0.02, 0.3, 0.005) var machine_fire_cooldown := 0.075

@export_group("Burst Recoil")
@export_range(0.0, 5.0, 0.05) var recoil_build_up_per_shot := 0.35
@export_range(0.0, 10.0, 0.1) var maximum_recoil_build_up := 3.0
@export_range(0.1, 20.0, 0.1) var recoil_recovery_speed := 6.0

@export_range(0.0, 5.0, 0.05) var vertical_camera_kick := 0.45
@export_range(0.0, 5.0, 0.05) var horizontal_camera_kick := 0.18

@export_group("Machine Pistol Spread")
@export_range(0.0, 10.0, 0.05) var base_spread := 0.15
@export_range(0.0, 10.0, 0.05) var spread_per_shot := 0.12
@export_range(0.0, 15.0, 0.1) var maximum_spread := 2.5


var _recoil_build_up := 0.0
var _current_spread := 0.0


func _ready() -> void:
	super._ready()

	automatic = true
	fire_cooldown = machine_fire_cooldown

	fired.connect(_on_machine_pistol_fired)


func _process(delta: float) -> void:
	var shooter := _find_shooter()

	if (
		automatic
		and Input.is_action_pressed("primary_use")
		and shooter != null
		and shooter.is_multiplayer_authority()
	):
		use_primary()

	_recoil_build_up = move_toward(
		_recoil_build_up,
		0.0,
		recoil_recovery_speed * delta
	)

	_current_spread = move_toward(
		_current_spread,
		base_spread,
		recoil_recovery_speed * delta
	)


func use_primary() -> void:
	if not _can_fire:
		return

	_can_fire = false
	fired.emit()
	_play_mechanical_animation()
	_play_owner_animation(&"ual/Pistol_Shoot")
	_fire_hitscan()

	# Der visuelle Rueckstoss darf die hohe Feuerrate nicht blockieren. Ein
	# neuer Schuss unterbricht den laufenden Tween und startet ihn erneut.
	_play_recoil_animation()

	await get_tree().create_timer(machine_fire_cooldown).timeout
	_can_fire = true


func _on_machine_pistol_fired() -> void:
	_recoil_build_up = minf(
		_recoil_build_up + recoil_build_up_per_shot,
		maximum_recoil_build_up
	)

	_current_spread = minf(
		_current_spread + spread_per_shot,
		maximum_spread
	)

	_apply_camera_kick()


func _apply_camera_kick() -> void:
	var shooter := _find_shooter()

	if shooter == null:
		return

	if not shooter.is_multiplayer_authority():
		return

	#
	# Falls dein FPSController eine eigene Recoil-Funktion besitzt,
	# wird diese benutzt.
	#
	if shooter.has_method("add_camera_recoil"):
		var pitch := (
			vertical_camera_kick
			+ _recoil_build_up
		)

		var yaw := randf_range(
			-horizontal_camera_kick,
			horizontal_camera_kick
		)

		shooter.add_camera_recoil(
			Vector2(
				yaw,
				pitch
			)
		)
