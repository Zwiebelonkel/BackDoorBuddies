extends Node3D


@export_range(0.0, 10.0, 0.1)
var base_light_energy: float = 2.4

@export var flicker_enabled := true

@onready var light: SpotLight3D = $Light
@onready var tube_left: MeshInstance3D = $TubeLeft
@onready var tube_right: MeshInstance3D = $TubeRight
@onready var flicker_timer: Timer = $FlickerTimer

var _flicker_seed := 1
var _flicker_steps_remaining := 0
var _rng := RandomNumberGenerator.new()


func configure(seed_value: int) -> void:
	_flicker_seed = maxi(absi(seed_value), 1)

	if is_node_ready():
		_reset_flicker()


func _ready() -> void:
	_reset_flicker()


func _reset_flicker() -> void:
	_rng.seed = _flicker_seed
	_flicker_steps_remaining = 0
	_set_output(1.0)

	if not flicker_timer.timeout.is_connected(_on_flicker_timer_timeout):
		flicker_timer.timeout.connect(_on_flicker_timer_timeout)

	_schedule_idle_interval()


func _on_flicker_timer_timeout() -> void:
	if not flicker_enabled:
		_set_output(1.0)
		_schedule_idle_interval()
		return

	if _flicker_steps_remaining > 0:
		var output := (
			_rng.randf_range(0.08, 0.48)
			if _flicker_steps_remaining % 2 == 0
			else _rng.randf_range(0.62, 0.92)
		)

		_set_output(output)
		_flicker_steps_remaining -= 1
		flicker_timer.start(_rng.randf_range(0.025, 0.085))
		return

	_set_output(1.0)

	if _rng.randf() < 0.22:
		_flicker_steps_remaining = _rng.randi_range(2, 5)
		flicker_timer.start(_rng.randf_range(0.03, 0.12))
	else:
		_schedule_idle_interval()


func _schedule_idle_interval() -> void:
	flicker_timer.start(_rng.randf_range(1.5, 5.5))


func _set_output(multiplier: float) -> void:
	var safe_multiplier := clampf(multiplier, 0.0, 1.0)

	light.light_energy = base_light_energy * safe_multiplier
	tube_left.visible = safe_multiplier > 0.12
	tube_right.visible = safe_multiplier > 0.12
