class_name SniperHeld
extends PistolHeld

@export_group("Scope")
@export_range(5.0, 60.0, 1.0) var scoped_fov := 18.0
@export_range(3.0, 30.0, 0.5) var minimum_scoped_fov := 6.0
@export_range(5.0, 60.0, 0.5) var maximum_scoped_fov := 30.0
@export_range(0.5, 10.0, 0.5) var scope_zoom_step := 2.0
@export_range(0.01, 0.25, 0.01) var scope_zoom_duration := 0.08
@export_range(0.05, 1.0, 0.01) var scoped_sensitivity := 0.32
@export_range(0.01, 0.5, 0.01) var scope_transition_duration := 0.14
@export_range(0.0, 8.0, 0.1) var shot_fov_kick := 1.8

@onready var scope_overlay: Control = $ScopeLayer/ScopeOverlay
@onready var model_root: Node3D = $ModelRoot
@onready var zoom_label: Label = $ScopeLayer/ScopeOverlay/ZoomLabel

var _is_scoped := false
var _unscoped_fov := 75.0
var _scope_tween: Tween
var _scope_recoil_tween: Tween
var _current_scoped_fov := 18.0


func _ready() -> void:
	super._ready()
	_current_scoped_fov = clampf(
		scoped_fov,
		minimum_scoped_fov,
		maximum_scoped_fov
	)
	_update_zoom_label()
	scope_overlay.visible = false
	scope_overlay.modulate.a = 0.0
	fired.connect(_on_fired)


func use_secondary(is_pressed: bool) -> void:
	var shooter := _find_shooter()

	if shooter == null or not shooter.is_multiplayer_authority():
		return

	_set_scoped(is_pressed, shooter)


func adjust_scope_zoom(zoom_steps: float) -> bool:
	if not _is_scoped or is_zero_approx(zoom_steps):
		return false

	var shooter := _find_shooter()

	if shooter == null or not shooter.is_multiplayer_authority():
		return false

	var aim_camera := _find_aim_camera(shooter)

	if aim_camera == null:
		return false

	var previous_fov := _current_scoped_fov
	_current_scoped_fov = clampf(
		_current_scoped_fov - zoom_steps * scope_zoom_step,
		minimum_scoped_fov,
		maximum_scoped_fov
	)

	if is_equal_approx(previous_fov, _current_scoped_fov):
		return true

	if _scope_tween != null and _scope_tween.is_valid():
		_scope_tween.kill()
		scope_overlay.modulate.a = 1.0

	if _scope_recoil_tween != null and _scope_recoil_tween.is_valid():
		_scope_recoil_tween.kill()

	_scope_tween = create_tween()
	_scope_tween.tween_property(
		aim_camera,
		"fov",
		_current_scoped_fov,
		scope_zoom_duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_update_zoom_label()
	return true


func is_scope_active() -> bool:
	return _is_scoped


func get_current_scope_fov() -> float:
	return _current_scoped_fov


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
		_current_scoped_fov = clampf(
			_current_scoped_fov,
			minimum_scoped_fov,
			maximum_scoped_fov
		)
		_update_zoom_label()
		scope_overlay.visible = true
		model_root.visible = false
		_scope_tween.tween_property(
			aim_camera,
			"fov",
			_current_scoped_fov,
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
		minf(_current_scoped_fov + shot_fov_kick, _unscoped_fov),
		0.045
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_scope_recoil_tween.tween_property(
		aim_camera,
		"fov",
		_current_scoped_fov,
		0.16
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _update_zoom_label() -> void:
	if zoom_label == null:
		return

	var reference_fov := maxf(_unscoped_fov, 75.0)
	var magnification := reference_fov / maxf(_current_scoped_fov, 0.1)
	zoom_label.text = "%.1fx  //  .308" % magnification


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
