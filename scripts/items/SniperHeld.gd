class_name SniperHeld
extends PistolHeld

@export_group("Scope")
@export_range(5.0, 60.0, 1.0) var scoped_fov := 18.0
@export_range(0.05, 1.0, 0.01) var scoped_sensitivity := 0.32
@export_range(0.01, 0.5, 0.01) var scope_transition_duration := 0.14
@export_range(0.0, 8.0, 0.1) var shot_fov_kick := 1.8

@onready var scope_overlay: Control = $ScopeLayer/ScopeOverlay
@onready var model_root: Node3D = $ModelRoot

var _is_scoped := false
var _unscoped_fov := 75.0
var _scope_tween: Tween
var _scope_recoil_tween: Tween


func _ready() -> void:
	super._ready()
	scope_overlay.visible = false
	scope_overlay.modulate.a = 0.0
	fired.connect(_on_fired)


func use_secondary(is_pressed: bool) -> void:
	var shooter := _find_shooter()

	if shooter == null or not shooter.is_multiplayer_authority():
		return

	_set_scoped(is_pressed, shooter)


func _set_scoped(enabled: bool, shooter: CollisionObject3D) -> void:
	if _is_scoped == enabled:
		return

	var aim_camera := _find_aim_camera(shooter)

	if aim_camera == null:
		return

	_is_scoped = enabled

	if _scope_tween != null and _scope_tween.is_valid():
		_scope_tween.kill()

	if _scope_recoil_tween != null and _scope_recoil_tween.is_valid():
		_scope_recoil_tween.kill()

	_scope_tween = create_tween().set_parallel(true)
	_scope_tween.set_trans(Tween.TRANS_SINE)
	_scope_tween.set_ease(Tween.EASE_IN_OUT)

	if enabled:
		_unscoped_fov = aim_camera.fov
		scope_overlay.visible = true
		model_root.visible = false
		_scope_tween.tween_property(
			aim_camera,
			"fov",
			scoped_fov,
			scope_transition_duration
		)
		_scope_tween.tween_property(
			scope_overlay,
			"modulate:a",
			1.0,
			scope_transition_duration
		)
	else:
		model_root.visible = true
		_scope_tween.tween_property(
			aim_camera,
			"fov",
			_unscoped_fov,
			scope_transition_duration
		)
		_scope_tween.tween_property(
			scope_overlay,
			"modulate:a",
			0.0,
			scope_transition_duration
		)
		_scope_tween.chain().tween_callback(
			func() -> void:
				if not _is_scoped:
					scope_overlay.visible = false
		)

	if shooter.has_method("set_weapon_aim_sensitivity_multiplier"):
		shooter.set_weapon_aim_sensitivity_multiplier(
			scoped_sensitivity if enabled else 1.0
		)


func _on_fired() -> void:
	if not _is_scoped:
		return

	var shooter := _find_shooter()
	var aim_camera := _find_aim_camera(shooter)

	if aim_camera == null:
		return

	if _scope_recoil_tween != null and _scope_recoil_tween.is_valid():
		_scope_recoil_tween.kill()

	_scope_recoil_tween = create_tween()
	_scope_recoil_tween.tween_property(
		aim_camera,
		"fov",
		minf(scoped_fov + shot_fov_kick, _unscoped_fov),
		0.045
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_scope_recoil_tween.tween_property(
		aim_camera,
		"fov",
		scoped_fov,
		0.16
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _exit_tree() -> void:
	if not _is_scoped:
		return

	var shooter := _find_shooter()
	var aim_camera := _find_aim_camera(shooter)

	if aim_camera != null:
		aim_camera.fov = _unscoped_fov

	if shooter != null and shooter.has_method(
		"set_weapon_aim_sensitivity_multiplier"
	):
		shooter.set_weapon_aim_sensitivity_multiplier(1.0)

