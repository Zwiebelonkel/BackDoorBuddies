class_name DrivableVan
extends CharacterBody3D


@export_group("Driving")
@export_range(1.0, 30.0, 0.5) var maximum_forward_speed := 10.0
@export_range(1.0, 20.0, 0.5) var maximum_reverse_speed := 4.0
@export_range(0.5, 30.0, 0.5) var acceleration := 7.0
@export_range(0.5, 40.0, 0.5) var braking := 14.0
@export_range(0.5, 20.0, 0.5) var rolling_drag := 4.0
@export_range(5.0, 120.0, 1.0) var steering_speed_degrees := 48.0

@export_group("Interaction")
@export_range(1.0, 6.0, 0.1) var interaction_distance := 3.0

@export_group("Networking")
@export_range(5, 60, 1) var sync_rate := 30
@export_range(1.0, 30.0, 0.5) var network_smoothing := 12.0
@export_range(0.1, 2.0, 0.05) var input_timeout := 0.5

@onready var cargo_area: Area3D = $CargoArea
@onready var cargo_shape: CollisionShape3D = $CargoArea/CollisionShape3D
@onready var driver_interaction: Area3D = $DriverInteraction
@onready var driver_seat: Marker3D = $DriverSeat
@onready var driver_exit: Marker3D = $DriverExit
@onready var headlights: Array[SpotLight3D] = [
	$SpotLight3D,
	$SpotLight3D2,
]
@onready var headlight_glass := get_node_or_null(
	^"van/Sketchfab_model/41667f2016ad477e8bcc5dadecbea5dd_fbx/RootNode/Shvan92_Headlights_Glass/Object_22/Shvan92_Headlights_Glass_UCB_Lights_and_Glass_Transperent_0"
) as MeshInstance3D

var _driver_peer_id := 0
var _driver_throttle := 0.0
var _driver_steering := 0.0
var _current_speed := 0.0
var _input_age := 0.0
var _sync_time := 0.0
var _target_position := Vector3.ZERO
var _target_yaw := 0.0


func _ready() -> void:
	add_to_group(&"drivable_van")
	process_physics_priority = -100
	_target_position = global_position
	_target_yaw = global_rotation.y
	_set_headlights_enabled(false)

	if (
		multiplayer.is_server()
		and not multiplayer.peer_disconnected.is_connected(
			_on_peer_disconnected
		)
	):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)


func _physics_process(delta: float) -> void:
	_process_local_driver_input()

	if multiplayer.is_server():
		_attach_new_cargo_items()

	var previous_transform := global_transform
	var passengers := _collect_passengers()

	if multiplayer.is_server():
		_simulate_server_movement(delta)
	else:
		_interpolate_remote_transform(delta)

	_carry_passengers(passengers, previous_transform)
	_update_attached_cargo()
	_anchor_driver()

	if multiplayer.is_server():
		_sync_time += delta

		if _sync_time >= 1.0 / float(sync_rate):
			_sync_time = 0.0
			_sync_vehicle_state.rpc(
				global_position,
				global_rotation.y,
				_current_speed,
				_driver_peer_id
			)


func get_driver_interaction_text() -> String:
	if _driver_peer_id == 0:
		return "Van fahren"

	return "Van ist besetzt"


func request_drive(player: Node3D) -> void:
	if player == null or not player.is_multiplayer_authority():
		return

	if multiplayer.is_server():
		_server_try_enter(multiplayer.get_unique_id())
	else:
		_request_enter_server.rpc_id(1)


func request_driver_exit(player: Node3D) -> void:
	if player == null or not player.is_multiplayer_authority():
		return

	if multiplayer.is_server():
		_server_try_exit(multiplayer.get_unique_id())
	else:
		_request_exit_server.rpc_id(1)


func get_driver_peer_id() -> int:
	return _driver_peer_id


func get_vehicle_velocity() -> Vector3:
	return global_transform.basis.x.normalized() * _current_speed


@rpc("any_peer", "call_remote", "reliable")
func _request_enter_server() -> void:
	if multiplayer.is_server():
		_server_try_enter(multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "reliable")
func _request_exit_server() -> void:
	if multiplayer.is_server():
		_server_try_exit(multiplayer.get_remote_sender_id())


func _server_try_enter(peer_id: int) -> void:
	if not multiplayer.is_server() or _driver_peer_id != 0:
		return

	var player := _find_player(peer_id)

	if player == null:
		return

	if (
		player.global_position.distance_to(driver_interaction.global_position)
		> interaction_distance
	):
		return

	if (
		player.has_method("is_driving_vehicle")
		and player.is_driving_vehicle()
	):
		return

	_apply_driver_assignment.rpc(peer_id)


func _server_try_exit(peer_id: int) -> void:
	if not multiplayer.is_server() or peer_id != _driver_peer_id:
		return

	_apply_driver_exit.rpc(peer_id, driver_exit.global_transform)


@rpc("authority", "call_local", "reliable")
func _apply_driver_assignment(peer_id: int) -> void:
	if peer_id <= 0:
		return

	if _driver_peer_id != 0 and _driver_peer_id != peer_id:
		_release_driver_locally(
			_driver_peer_id,
			driver_exit.global_transform
		)

	_driver_peer_id = peer_id
	_driver_throttle = 0.0
	_driver_steering = 0.0
	_input_age = 0.0
	_set_headlights_enabled(true)

	var player := _find_player(peer_id)

	if player != null and player.has_method("enter_vehicle"):
		player.enter_vehicle(self, driver_seat.global_transform)

	_anchor_driver()


@rpc("authority", "call_local", "reliable")
func _apply_driver_exit(
	peer_id: int,
	exit_transform: Transform3D
) -> void:
	_release_driver_locally(peer_id, exit_transform)

	if _driver_peer_id == peer_id:
		_driver_peer_id = 0

	_driver_throttle = 0.0
	_driver_steering = 0.0
	_input_age = 0.0
	_set_headlights_enabled(false)


func _release_driver_locally(
	peer_id: int,
	exit_transform: Transform3D
) -> void:
	var player := _find_player(peer_id)

	if player != null and player.has_method("exit_vehicle"):
		player.exit_vehicle(self, exit_transform, get_vehicle_velocity())


func _set_headlights_enabled(enabled: bool) -> void:
	for headlight in headlights:
		if is_instance_valid(headlight):
			headlight.visible = enabled

	if is_instance_valid(headlight_glass):
		headlight_glass.visible = enabled


func _process_local_driver_input() -> void:
	if _driver_peer_id != multiplayer.get_unique_id():
		return

	var throttle := Input.get_axis("move_backward", "move_forward")
	var steering := Input.get_axis("move_right", "move_left")

	if multiplayer.is_server():
		_set_driver_input(throttle, steering)
	else:
		_submit_driver_input.rpc_id(1, throttle, steering)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _submit_driver_input(throttle: float, steering: float) -> void:
	if not multiplayer.is_server():
		return

	if multiplayer.get_remote_sender_id() != _driver_peer_id:
		return

	_set_driver_input(throttle, steering)


func _set_driver_input(throttle: float, steering: float) -> void:
	_driver_throttle = clampf(throttle, -1.0, 1.0)
	_driver_steering = clampf(steering, -1.0, 1.0)
	_input_age = 0.0


func _simulate_server_movement(delta: float) -> void:
	_input_age += delta

	if _driver_peer_id == 0 or _input_age > input_timeout:
		_driver_throttle = 0.0
		_driver_steering = 0.0

	var target_speed := 0.0

	if _driver_throttle > 0.0:
		target_speed = _driver_throttle * maximum_forward_speed
	elif _driver_throttle < 0.0:
		target_speed = _driver_throttle * maximum_reverse_speed

	var speed_change := acceleration

	if is_zero_approx(_driver_throttle):
		speed_change = rolling_drag
	elif (
		not is_zero_approx(_current_speed)
		and signf(target_speed) != signf(_current_speed)
	):
		speed_change = braking

	_current_speed = move_toward(
		_current_speed,
		target_speed,
		speed_change * delta
	)

	if absf(_current_speed) > 0.05:
		var maximum_speed := (
			maximum_forward_speed
			if _current_speed >= 0.0
			else maximum_reverse_speed
		)
		var speed_ratio := clampf(
			absf(_current_speed) / maximum_speed,
			0.15,
			1.0
		)
		var reverse_steering := 1.0 if _current_speed >= 0.0 else -1.0
		rotate_y(
			deg_to_rad(steering_speed_degrees)
			* _driver_steering
			* reverse_steering
			* speed_ratio
			* delta
		)

	velocity = global_transform.basis.x.normalized() * _current_speed
	var collided := move_and_slide()

	if collided and get_slide_collision_count() > 0:
		_current_speed = move_toward(_current_speed, 0.0, braking * delta)

	velocity = Vector3.ZERO


func _interpolate_remote_transform(delta: float) -> void:
	var weight := 1.0 - exp(-network_smoothing * delta)
	global_position = global_position.lerp(_target_position, weight)
	global_rotation = Vector3(
		0.0,
		lerp_angle(global_rotation.y, _target_yaw, weight),
		0.0
	)


@rpc("authority", "call_remote", "unreliable_ordered")
func _sync_vehicle_state(
	position: Vector3,
	yaw: float,
	current_speed: float,
	driver_peer_id: int
) -> void:
	_target_position = position
	_target_yaw = yaw
	_current_speed = current_speed

	if driver_peer_id != _driver_peer_id:
		if driver_peer_id == 0:
			_apply_driver_exit(
				_driver_peer_id,
				driver_exit.global_transform
			)
		else:
			_apply_driver_assignment(driver_peer_id)


func _collect_passengers() -> Array[Node3D]:
	var passengers: Array[Node3D] = []
	var players := _get_players_container()

	if players == null:
		return passengers

	for child in players.get_children():
		var player := child as Node3D

		if player == null:
			continue

		if (
			player.name.to_int() == _driver_peer_id
			or _is_point_in_cargo(player.global_position)
		):
			passengers.append(player)

	return passengers


func _carry_passengers(
	passengers: Array[Node3D],
	previous_transform: Transform3D
) -> void:
	if previous_transform.is_equal_approx(global_transform):
		return

	var transform_delta := (
		global_transform
		* previous_transform.affine_inverse()
	)

	for passenger in passengers:
		if is_instance_valid(passenger):
			passenger.global_transform = (
				transform_delta
				* passenger.global_transform
			)


func _anchor_driver() -> void:
	if _driver_peer_id == 0:
		return

	var player := _find_player(_driver_peer_id)

	if player == null:
		return

	if player.has_method("enter_vehicle"):
		player.enter_vehicle(self, driver_seat.global_transform)

	player.global_position = driver_seat.global_position


func _attach_new_cargo_items() -> void:
	var items := _get_items_container()

	if items == null:
		return

	for child in items.get_children():
		var pickup := child as PickupItem

		if (
			pickup == null
			or pickup.van_attached
			or not _is_point_in_cargo(pickup.global_position)
		):
			continue

		pickup.attach_to_van(global_transform)


func _update_attached_cargo() -> void:
	var items := _get_items_container()

	if items == null:
		return

	for child in items.get_children():
		var pickup := child as PickupItem

		if pickup != null and pickup.van_attached:
			pickup.apply_van_transform(global_transform)


func _is_point_in_cargo(point: Vector3) -> bool:
	if cargo_shape == null:
		return false

	var box := cargo_shape.shape as BoxShape3D

	if box == null:
		return false

	var local_point := cargo_shape.global_transform.affine_inverse() * point
	var half_size := box.size * 0.5

	return (
		absf(local_point.x) <= half_size.x
		and absf(local_point.y) <= half_size.y
		and absf(local_point.z) <= half_size.z
	)


func _find_player(peer_id: int) -> Node3D:
	var players := _get_players_container()

	if players == null:
		return null

	return players.get_node_or_null(str(peer_id)) as Node3D


func _get_players_container() -> Node3D:
	var current_scene := get_tree().current_scene

	if current_scene == null:
		return null

	return current_scene.get_node_or_null("Players") as Node3D


func _get_items_container() -> Node3D:
	var current_scene := get_tree().current_scene

	if current_scene == null:
		return null

	return current_scene.get_node_or_null(
		"ProceduralLevelGenerator/SpawnedItems"
	) as Node3D


func _on_peer_disconnected(peer_id: int) -> void:
	if multiplayer.is_server() and peer_id == _driver_peer_id:
		_apply_driver_exit.rpc(peer_id, driver_exit.global_transform)
