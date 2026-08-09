class_name FPSController
extends CharacterBody3D

# ─────────────────────────────────────────────
# EXPORTS – im Inspector anpassbar
# ─────────────────────────────────────────────

@export_group("Movement")
@export var walk_speed: float         = 4.5
@export var sprint_speed: float       = 8.0
@export var crouch_speed: float       = 2.2
@export var acceleration: float       = 12.0
@export var friction: float           = 10.0
@export var air_friction: float       = 2.0

@export_group("Inventory Weight")
@export_range(0.0, 0.2, 0.001)
var speed_penalty_per_kilogram: float = 0.035

@export_range(0.1, 1.0, 0.01)
var minimum_weight_speed_multiplier: float = 0.45

@export_group("Stamina")
@export_range(1.0, 500.0, 1.0) var maximum_stamina: float = 100.0
@export_range(0.0, 100.0, 0.5) var stamina_drain_per_second: float = 25.0
@export_range(0.0, 100.0, 0.5) var stamina_recovery_per_second: float = 18.0
@export_range(0.0, 5.0, 0.05) var stamina_recovery_delay: float = 1.0
@export_range(0.0, 100.0, 1.0) var stamina_restart_threshold: float = 20.0

@export_group("Jumping")
@export var jump_velocity: float      = 5.5
@export var gravity_scale: float      = 2.2
@export var coyote_time: float        = 0.12
@export var jump_buffer_time: float   = 0.15

@export_group("Look")
@export var mouse_sensitivity: float  = 0.002
@export var controller_sensitivity: float = 2.5
@export var max_pitch_degrees: float  = 88.0

@export_group("Look Sway")
@export var look_sway_enabled: bool = true
@export_range(0.0, 1.5, 0.05) var look_sway_max_degrees: float = 0.6
@export_range(0.0, 1.0, 0.05) var look_sway_amount: float = 0.3
@export_range(0.0, 1.0, 0.05) var look_sway_roll_amount: float = 0.15
@export_range(1.0, 30.0, 0.5) var look_sway_smoothing: float = 9.0

@export_group("Head Bob")
@export var bob_enabled: bool         = true
@export var bob_frequency_walk: float = 2.0
@export var bob_frequency_sprint: float = 2.8
@export var bob_amplitude_y: float    = 0.06
@export var bob_amplitude_x: float    = 0.03

@export_group("Camera Tilt (Strafe)")
@export var tilt_enabled: bool        = true
@export var tilt_max_degrees: float   = 3.5
@export var tilt_speed: float         = 8.0

@export_group("Crouching")
@export var crouch_enabled: bool      = true
@export var crouch_height: float      = 1.0
@export var stand_height: float       = 1.8
@export var crouch_head_y: float      = 0.1
@export var stand_head_y: float       = 0.7
@export var crouch_transition_speed: float = 10.0

@export_group("Hand Sway")
@export var hand_sway_enabled: bool = true

@export var sway_position_amount: float = 0.0015
@export var sway_rotation_amount: float = 0.08

@export var sway_max_position: float = 0.08
@export var sway_max_rotation_degrees: float = 6.0

@export var sway_smoothing: float = 12.0

@export var movement_sway_amount: float = 0.025
@export var movement_rotation_amount: float = 2.0

@export var idle_sway_enabled: bool = true
@export var idle_sway_amount: float = 0.004
@export var idle_sway_speed: float = 1.2

@export_group("Multiplayer")
## Wie oft pro Sekunde wird der State an andere Peers gesendet (Authority → alle)
@export var sync_rate: int            = 30

# ─────────────────────────────────────────────
# SIGNALS
# ─────────────────────────────────────────────

signal jumped
signal landed
signal footstep(speed_ratio: float)
signal crouched(is_crouching: bool)
signal inventory_changed(items: Array[ItemData], selected_index: int)
signal stamina_changed(current_stamina: float, maximum_stamina: float)

# ─────────────────────────────────────────────
# NODES
# ─────────────────────────────────────────────

@onready var head: Node3D                         = $Head
@onready var camera: Camera3D                     = $Head/Camera3D
@onready var standing_collision: CollisionShape3D = $CollisionShape3D
@onready var crouch_collision: CollisionShape3D   = $CrouchCollision
@onready var uncroch_raycast: RayCast3D           = $StandingRaycast
@onready var interaction_ray: RayCast3D = $Head/Camera3D/InteractionRay
@onready var item_holder: Marker3D = $Head/Camera3D/ItemHolder
var interaction_label: Label = null
@onready var world_item_holder: Marker3D = $Head/Camera3D/WorldItemHolder

# ─────────────────────────────────────────────
# PRIVATE STATE
# ─────────────────────────────────────────────

var _gravity: float           = ProjectSettings.get_setting("physics/3d/default_gravity")
var _pitch: float             = 0.0
var _coyote_timer: float      = 0.0
var _jump_buffer: float       = 0.0
var _bob_time: float          = 0.0
var _bob_offset: Vector3      = Vector3.ZERO
var _was_on_floor: bool       = false
var _step_distance: float     = 0.0
var _is_crouching: bool       = false
var _target_head_y: float     = 0.7
var _target_col_height: float = 1.8
var _current_tilt: float      = 0.0
var inventory: Array[ItemData] = []
var selected_inventory_index: int = -1
var server_inventory_paths: Array[String] = []
var equipped_item_resource_path: String = ""
var held_item_instance: Node3D = null
var _mouse_sway_input := Vector2.ZERO
var _item_holder_start_position := Vector3.ZERO
var _item_holder_start_rotation := Vector3.ZERO
var _idle_sway_time := 0.0
var current_stamina: float = 0.0
var _sprint_active := false
var _sprint_exhausted := false
var _stamina_recovery_delay_remaining := 0.0
var _base_mouse_sensitivity: float
var _base_controller_sensitivity: float
var _look_sway_impulse := Vector2.ZERO
var _current_look_sway := Vector2.ZERO
var _current_look_sway_roll := 0.0

# Multiplayer sync
var _sync_timer: float        = 0.0
var world_held_item_instance: Node3D = null

const STEP_INTERVAL_WALK   := 0.55
const STEP_INTERVAL_SPRINT := 0.42

const MAX_INVENTORY_SIZE := 4
var player_hud: PlayerHUD = null

const PLAYER_HUD_SCENE := preload(
	"res://scenes/UI/PlayerHUD.tscn"
)

# ─────────────────────────────────────────────
# READY
# ─────────────────────────────────────────────

func _ready() -> void:
	set_multiplayer_authority(name.to_int())
	current_stamina = maximum_stamina
	_base_mouse_sensitivity = mouse_sensitivity
	_base_controller_sensitivity = controller_sensitivity

	_item_holder_start_position = item_holder.position
	_item_holder_start_rotation = item_holder.rotation

	if is_multiplayer_authority():
		add_to_group("local_player_controller")
		_load_look_sensitivity()
		camera.make_current()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

		item_holder.visible = true
		world_item_holder.visible = false

		_create_local_hud()
	else:
		camera.current = false

		item_holder.visible = false
		world_item_holder.visible = true

	if crouch_collision:
		crouch_collision.disabled = true

# ─────────────────────────────────────────────
# INPUT  (nur Authority)
# ─────────────────────────────────────────────

func _create_local_hud() -> void:
	if player_hud != null:
		return

	player_hud = PLAYER_HUD_SCENE.instantiate() as PlayerHUD

	if player_hud == null:
		push_error("PlayerHUD konnte nicht erstellt werden.")
		return

	get_tree().current_scene.add_child(player_hud)
	player_hud.bind_player(self)
	interaction_label = player_hud.interaction_label
	interaction_label.visible = false

	_emit_inventory_changed()

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_mouse_sway_input += event.relative
		_rotate_camera(event.relative * mouse_sensitivity)

	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = \
			Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
			else Input.MOUSE_MODE_CAPTURED

	if event.is_action_pressed("jump"):
		_jump_buffer = jump_buffer_time
		
	if event.is_action_pressed("primary_use"):
		_use_held_item()

	if event.is_action_pressed("interact"):
		_try_interact()

	if event.is_action_pressed("inventory_slot_1"):
		select_inventory_item(0)

	if event.is_action_pressed("inventory_slot_2"):
		select_inventory_item(1)

	if event.is_action_pressed("inventory_slot_3"):
		select_inventory_item(2)
		
	if event.is_action_pressed("inventory_slot_4"):
		select_inventory_item(3)

	if event.is_action_pressed("drop_item"):
		_request_drop_selected_item()

func _rotate_camera(delta_2d: Vector2) -> void:
	_look_sway_impulse += delta_2d
	rotate_y(-delta_2d.x)
	_pitch = clampf(_pitch - delta_2d.y, -deg_to_rad(max_pitch_degrees), deg_to_rad(max_pitch_degrees))
	head.rotation.x = _pitch


func _load_look_sensitivity() -> void:
	var config := ConfigFile.new()
	config.load("user://options.cfg")
	var sensitivity := float(
		config.get_value("controls", "look_sensitivity", 1.0)
	)
	apply_look_sensitivity(sensitivity)


func apply_look_sensitivity(sensitivity: float) -> void:
	var clamped_sensitivity := clampf(sensitivity, 0.25, 3.0)
	mouse_sensitivity = _base_mouse_sensitivity * clamped_sensitivity
	controller_sensitivity = (
		_base_controller_sensitivity * clamped_sensitivity
	)

# ─────────────────────────────────────────────
# PHYSICS PROCESS
# ─────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		# Fremde Spieler: Interpolation zum zuletzt empfangenen State
		# (läuft weiter, move_and_slide sorgt für korrekte Kollision)
		return

	_update_controller_look(delta)
	_update_hand_sway(delta)
	_update_interaction_text()
	_handle_crouch(delta)
	_apply_gravity(delta)
	_handle_jump()
	_update_stamina(delta)
	_handle_movement(delta)
	_update_tilt(delta)
	_update_look_sway(delta)
	_update_head_bob(delta)
	_update_footsteps()
	_handle_landing()
	move_and_slide()

	# State an alle anderen Peers broadcasten
	_sync_timer += delta
	if _sync_timer >= 1.0 / sync_rate:
		_sync_timer = 0.0
		_broadcast_state.rpc(global_position, global_rotation, head.rotation.x, _is_crouching)

# ─────────────────────────────────────────────
# MULTIPLAYER RPC – State-Sync
# ─────────────────────────────────────────────

## Wird vom Authority-Peer an alle anderen gesendet.
## any_peer damit der Server es auch weiterleiten kann.
@rpc("authority", "unreliable_ordered", "call_remote")
func _broadcast_state(
	pos: Vector3,
	rot: Vector3,
	pitch: float,
	crouching: bool
) -> void:
	# Empfänger: smooth interpolieren statt harter Zuweisung
	global_position = global_position.lerp(pos, 0.3)
	global_rotation = rot
	head.rotation.x = pitch

	# Crouch-State synchronisieren (ohne lokale Collision-Logik auszulösen)
	if crouching != _is_crouching:
		_is_crouching = crouching
		_target_head_y = crouch_head_y if crouching else stand_head_y

	head.position.y = lerpf(head.position.y, _target_head_y, 0.2)

# ─────────────────────────────────────────────
# GRAVITY & COYOTE TIME
# ─────────────────────────────────────────────

func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		_coyote_timer = coyote_time
	else:
		_coyote_timer -= delta
		velocity.y -= _gravity * gravity_scale * delta

# ─────────────────────────────────────────────
# JUMPING
# ─────────────────────────────────────────────

func _handle_jump() -> void:
	_jump_buffer -= get_physics_process_delta_time()
	if _coyote_timer > 0.0 and _jump_buffer > 0.0:
		velocity.y = jump_velocity
		_coyote_timer = 0.0
		_jump_buffer = 0.0
		emit_signal("jumped")

# ─────────────────────────────────────────────
# MOVEMENT
# ─────────────────────────────────────────────

func _handle_movement(delta: float) -> void:
	var base_speed := walk_speed

	if _is_crouching:
		base_speed = crouch_speed
	elif _sprint_active:
		base_speed = sprint_speed

	var target_speed := base_speed * get_weight_speed_multiplier()

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	var accel := acceleration if is_on_floor() else air_friction
	var fric  := friction     if is_on_floor() else air_friction

	if direction.length() > 0.01:
		velocity.x = move_toward(velocity.x, direction.x * target_speed, accel * delta)
		velocity.z = move_toward(velocity.z, direction.z * target_speed, accel * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, fric * delta)
		velocity.z = move_toward(velocity.z, 0.0, fric * delta)


func _update_stamina(delta: float) -> void:
	var previous_stamina := current_stamina
	var movement_input := Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_backward"
	)
	var wants_to_sprint := (
		Input.is_action_pressed("sprint")
		and movement_input.length() > 0.1
		and not _is_crouching
		and is_on_floor()
	)

	if (
		_sprint_exhausted
		and current_stamina >= minf(stamina_restart_threshold, maximum_stamina)
	):
		_sprint_exhausted = false

	_sprint_active = (
		wants_to_sprint
		and not _sprint_exhausted
		and current_stamina > 0.0
	)

	if _sprint_active:
		current_stamina = maxf(
			current_stamina - stamina_drain_per_second * delta,
			0.0
		)
		_stamina_recovery_delay_remaining = stamina_recovery_delay

		if current_stamina <= 0.0:
			_sprint_active = false
			_sprint_exhausted = true
	else:
		_stamina_recovery_delay_remaining = maxf(
			_stamina_recovery_delay_remaining - delta,
			0.0
		)

		if _stamina_recovery_delay_remaining <= 0.0:
			current_stamina = minf(
				current_stamina + stamina_recovery_per_second * delta,
				maximum_stamina
			)

	if not is_equal_approx(previous_stamina, current_stamina):
		stamina_changed.emit(current_stamina, maximum_stamina)

# ─────────────────────────────────────────────
# CAMERA TILT
# ─────────────────────────────────────────────

func _update_tilt(delta: float) -> void:
	if not tilt_enabled:
		_current_tilt = 0.0
		camera.rotation.z = 0.0
		return
	var strafe := Input.get_axis("move_left", "move_right")
	var target_tilt := deg_to_rad(-tilt_max_degrees) * strafe
	_current_tilt = move_toward(_current_tilt, target_tilt, deg_to_rad(tilt_max_degrees) * tilt_speed * delta)
	camera.rotation.z = _current_tilt


func _update_controller_look(delta: float) -> void:
	var look_input := Input.get_vector(
		"look_left",
		"look_right",
		"look_up",
		"look_down"
	)

	if look_input.length() > 0.1:
		_rotate_camera(look_input * controller_sensitivity * delta)


func _update_look_sway(delta: float) -> void:
	var target_sway := Vector2.ZERO
	var target_roll := 0.0

	if look_sway_enabled:
		var max_sway := deg_to_rad(look_sway_max_degrees)
		target_sway = Vector2(
			clampf(
				_look_sway_impulse.y * look_sway_amount,
				-max_sway,
				max_sway
			),
			clampf(
				_look_sway_impulse.x * look_sway_amount,
				-max_sway,
				max_sway
			)
		)
		target_roll = clampf(
			-_look_sway_impulse.x * look_sway_roll_amount,
			-max_sway,
			max_sway
		)

	var smoothing_weight := 1.0 - exp(-look_sway_smoothing * delta)
	_current_look_sway = _current_look_sway.lerp(
		target_sway,
		smoothing_weight
	)
	_current_look_sway_roll = lerpf(
		_current_look_sway_roll,
		target_roll,
		smoothing_weight
	)

	camera.rotation.x = _current_look_sway.x
	camera.rotation.y = _current_look_sway.y
	camera.rotation.z = _current_tilt + _current_look_sway_roll
	_look_sway_impulse = Vector2.ZERO

# ─────────────────────────────────────────────
# HEAD BOB
# ─────────────────────────────────────────────

func _update_head_bob(delta: float) -> void:
	if not bob_enabled:
		camera.position = Vector3.ZERO
		return
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var sprinting := _sprint_active
	if is_on_floor() and horizontal_speed > 0.5:
		var freq := bob_frequency_sprint if sprinting else bob_frequency_walk
		_bob_time += delta * freq * TAU
		var speed_ratio := clampf(horizontal_speed / sprint_speed, 0.0, 1.0)
		_bob_offset.y = sin(_bob_time) * bob_amplitude_y * speed_ratio
		_bob_offset.x = cos(_bob_time * 0.5) * bob_amplitude_x * speed_ratio
	else:
		_bob_time = 0.0
		_bob_offset = _bob_offset.lerp(Vector3.ZERO, delta * 8.0)
	camera.position = camera.position.lerp(_bob_offset, delta * 10.0)

# ─────────────────────────────────────────────
# FOOTSTEPS
# ─────────────────────────────────────────────

func _update_footsteps() -> void:
	if not is_on_floor():
		return
	var h_speed := Vector2(velocity.x, velocity.z).length()
	if h_speed < 0.5:
		return
	var sprinting := _sprint_active
	var interval := STEP_INTERVAL_SPRINT if sprinting else STEP_INTERVAL_WALK
	_step_distance += h_speed * get_physics_process_delta_time()
	if _step_distance >= interval:
		_step_distance = 0.0
		emit_signal("footstep", clampf(h_speed / sprint_speed, 0.0, 1.0))

# ─────────────────────────────────────────────
# LANDING
# ─────────────────────────────────────────────

func _handle_landing() -> void:
	var on_floor_now := is_on_floor()
	if on_floor_now and not _was_on_floor:
		emit_signal("landed")
	_was_on_floor = on_floor_now

# ─────────────────────────────────────────────
# CROUCHING
# ─────────────────────────────────────────────

func _handle_crouch(delta: float) -> void:
	if not crouch_enabled:
		return
	var wants_crouch := Input.is_action_pressed("crouch")
	if wants_crouch and not _is_crouching:
		_set_crouch(true)
	elif not wants_crouch and _is_crouching:
		if not _ceiling_blocks_standup():
			_set_crouch(false)
	head.position.y = lerpf(head.position.y, _target_head_y, crouch_transition_speed * delta)
	_smooth_collision_height(delta)

func _set_crouch(crouching: bool) -> void:
	_is_crouching = crouching
	_target_head_y     = crouch_head_y if crouching else stand_head_y
	_target_col_height = crouch_height if crouching else stand_height
	if crouch_collision:
		crouch_collision.disabled = not crouching
	if standing_collision:
		standing_collision.disabled = crouching
	emit_signal("crouched", crouching)

func _smooth_collision_height(delta: float) -> void:
	var shape := standing_collision.shape as CapsuleShape3D
	if shape == null:
		return
	shape.height = lerpf(shape.height, _target_col_height, crouch_transition_speed * delta)

func _ceiling_blocks_standup() -> bool:
	if uncroch_raycast == null:
		return false
	uncroch_raycast.force_raycast_update()
	return uncroch_raycast.is_colliding()

# ─────────────────────────────────────────────
# PUBLIC HELPERS
# ─────────────────────────────────────────────

func is_moving() -> bool:
	return Vector2(velocity.x, velocity.z).length() > 0.1

func is_sprinting() -> bool:
	return _sprint_active and is_moving()

func is_crouching() -> bool:
	return _is_crouching

func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func get_total_inventory_weight() -> float:
	var total_weight := 0.0

	for item in inventory:
		if item != null:
			total_weight += maxf(item.weight, 0.0)

	return total_weight


func get_weight_speed_multiplier() -> float:
	return clampf(
		1.0 - get_total_inventory_weight() * speed_penalty_per_kilogram,
		minimum_weight_speed_multiplier,
		1.0
	)


func is_holding_large_item() -> bool:
	var equipped_data := _load_item_data(equipped_item_resource_path)
	return equipped_data != null and equipped_data.is_large_item


func _load_item_data(item_resource_path: String) -> ItemData:
	if item_resource_path.is_empty():
		return null

	var loaded_resource := load(item_resource_path)

	if loaded_resource is ItemData:
		return loaded_resource as ItemData

	return null

func _try_interact() -> void:
	if not is_multiplayer_authority():
		print("Keine Authority")
		return

	if interaction_ray == null:
		print("InteractionRay fehlt")
		return

	interaction_ray.force_raycast_update()

	if not interaction_ray.is_colliding():
		print("InteractionRay trifft nichts")
		return

	var collider := interaction_ray.get_collider()

	if collider == null:
		print("Collider ist null")
		return

	print(
		"InteractionRay trifft: ",
		collider.name,
		" | Klasse: ",
		collider.get_class()
	)

	if collider.has_method("request_interaction"):
		collider.request_interaction(self)
	elif collider.has_method("request_pickup"):
		if is_holding_large_item():
			print("Mit einem Großitem in der Hand kann nichts aufgenommen werden.")
			return

		print("Pickup wird angefragt")
		collider.request_pickup()
	else:
		print("Getroffenes Objekt besitzt keine Interaktionsmethode")


func server_receive_item(data: ItemData) -> bool:
	if not multiplayer.is_server():
		return false

	if data == null:
		return false

	if data.resource_path.is_empty():
		push_error("ItemData muss als .tres-Datei gespeichert sein.")
		return false

	if is_holding_large_item():
		print(
			"Aufnahme abgelehnt: Spieler hält bereits ein Großitem."
		)
		return false

	if server_inventory_paths.size() >= MAX_INVENTORY_SIZE:
		print(
			"Inventar von Peer ",
			get_multiplayer_authority(),
			" ist voll."
		)
		return false

	server_inventory_paths.append(data.resource_path)

	if server_inventory_paths.size() == 1 or data.is_large_item:
		equipped_item_resource_path = data.resource_path

	var player_peer_id := get_multiplayer_authority()

	if player_peer_id == multiplayer.get_unique_id():
		_receive_item_local(data.resource_path)
	else:
		_receive_item.rpc_id(player_peer_id, data.resource_path)

	return true


func _request_drop_selected_item() -> void:
	if not is_multiplayer_authority():
		return

	if selected_inventory_index < 0:
		return

	if selected_inventory_index >= inventory.size():
		return

	if multiplayer.is_server():
		_server_drop_item(selected_inventory_index)
	else:
		_request_drop_item_server.rpc_id(1, selected_inventory_index)


@rpc("any_peer", "call_remote", "reliable")
func _request_drop_item_server(slot_index: int) -> void:
	if not multiplayer.is_server():
		return

	var sender_peer_id := multiplayer.get_remote_sender_id()

	if sender_peer_id != get_multiplayer_authority():
		push_warning(
			"Peer %s wollte aus fremdem Inventar droppen."
			% sender_peer_id
		)
		return

	_server_drop_item(slot_index)


func _server_drop_item(slot_index: int) -> void:
	if not multiplayer.is_server():
		return

	if slot_index < 0 or slot_index >= server_inventory_paths.size():
		return

	var item_path := server_inventory_paths[slot_index]

	if item_path.is_empty():
		return

	var drop_global_position := _find_drop_position()

	var drop_global_rotation := Vector3(
		0.0,
		global_rotation.y,
		0.0
	)

	var main := get_tree().current_scene

	if main == null or not main.has_method("server_spawn_dropped_item"):
		push_error("Main besitzt keine server_spawn_dropped_item()-Methode.")
		return

	main.server_spawn_dropped_item(
		item_path,
		drop_global_position,
		drop_global_rotation
	)

	server_inventory_paths.remove_at(slot_index)

	if server_inventory_paths.is_empty():
		equipped_item_resource_path = ""
	else:
		var replacement_index := mini(
			slot_index,
			server_inventory_paths.size() - 1
		)
		equipped_item_resource_path = server_inventory_paths[replacement_index]

	var owner_peer_id := get_multiplayer_authority()

	if owner_peer_id == multiplayer.get_unique_id():
		_remove_dropped_item_local(slot_index)
	else:
		_confirm_drop.rpc_id(owner_peer_id, slot_index)

@rpc("any_peer", "call_remote", "reliable")
func _confirm_drop(slot_index: int) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return

	if not is_multiplayer_authority():
		return

	_remove_dropped_item_local(slot_index)

func _find_drop_position() -> Vector3:
	var forward := -global_transform.basis.z.normalized()

	# Gewünschte Stelle etwas vor dem Spieler.
	var target_position := (
		global_position
		+ forward * 0.5
	)

	# Oberhalb beginnen und mehrere Meter nach unten suchen.
	var ray_start := target_position + Vector3.UP * 2.0
	var ray_end := target_position + Vector3.DOWN * 5.0

	var query := PhysicsRayQueryParameters3D.create(
		ray_start,
		ray_end
	)

	# Den eigenen Spieler beim RayCast ignorieren.
	query.exclude = [get_rid()]

	# Hier ggf. nur den Boden-Layer eintragen.
	query.collision_mask = 1

	query.collide_with_bodies = true
	query.collide_with_areas = false

	var space_state := get_world_3d().direct_space_state
	var result := space_state.intersect_ray(query)

	if not result.is_empty():
		var floor_position: Vector3 = result["position"]

		# Ein kleines Stück über dem Boden, damit das Modell
		# nicht im Boden steckt.
		return floor_position + Vector3.UP * 0.05

	# Fallback, falls kein Boden gefunden wurde.
	return target_position + Vector3.UP * 0.1

func _remove_dropped_item_local(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= inventory.size():
		return

	inventory.remove_at(slot_index)
	_clear_held_item()

	if inventory.is_empty():
		selected_inventory_index = -1
		equipped_item_resource_path = ""
		_sync_equipped_item.rpc("")
	else:
		selected_inventory_index = mini(slot_index, inventory.size() - 1)
		var replacement_item := inventory[selected_inventory_index]
		equipped_item_resource_path = replacement_item.resource_path
		_equip_item(replacement_item)
		_sync_equipped_item.rpc(equipped_item_resource_path)

	_emit_inventory_changed()

	print(
		"Item fallengelassen | Inventar: ",
		inventory.size(),
		"/",
		MAX_INVENTORY_SIZE
	)

@rpc("any_peer", "call_remote", "reliable")
func _receive_item(item_resource_path: String) -> void:
	# Das serverseitige Player-Node gehört dem Client. Deshalb darf der Server
	# diese Bestätigung senden, obwohl er nicht die Multiplayer-Authority ist.
	if multiplayer.get_remote_sender_id() != 1:
		return

	if not is_multiplayer_authority():
		return

	_receive_item_local(item_resource_path)


func _receive_item_local(item_resource_path: String) -> void:
	if inventory.size() >= MAX_INVENTORY_SIZE:
		push_warning("Lokales Inventar ist bereits voll.")
		return

	var loaded_resource := load(item_resource_path)

	if not loaded_resource is ItemData:
		push_error(
			"ItemData konnte nicht geladen werden: %s"
			% item_resource_path
		)
		return

	var data := loaded_resource as ItemData
	inventory.append(data)

	print(
		"Aufgenommen: ",
		data.display_name,
		" | Inventar: ",
		inventory.size(),
		"/",
		MAX_INVENTORY_SIZE
	)

	if data.is_large_item:
		select_inventory_item(inventory.size() - 1)
	elif selected_inventory_index == -1:
		select_inventory_item(0)
	else:
		_emit_inventory_changed()
	
func _emit_inventory_changed() -> void:
	inventory_changed.emit(inventory, selected_inventory_index)
	
func select_inventory_item(index: int) -> void:
	if not is_multiplayer_authority():
		return

	if index < 0 or index >= MAX_INVENTORY_SIZE:
		return

	if is_holding_large_item():
		var requested_item := (
			inventory[index]
			if index < inventory.size()
			else null
		)

		if (
			requested_item == null
			or requested_item.resource_path != equipped_item_resource_path
		):
			print(
				"Slotwechsel blockiert: Großitem muss zuerst abgelegt werden."
			)
			return

	# Leerer Slot: aktuelles Item abwählen.
	if index >= inventory.size():
		unequip_current_item()
		return

	selected_inventory_index = index

	var selected_item := inventory[index]
	equipped_item_resource_path = selected_item.resource_path
	_equip_item(selected_item)
	_sync_equipped_item.rpc(equipped_item_resource_path)

	_emit_inventory_changed()

	# Später ggf. World-Item-Synchronisierung aufrufen.

@rpc("authority", "call_remote", "reliable")
func _sync_equipped_item(item_resource_path: String) -> void:
	if (
		multiplayer.is_server()
		and is_holding_large_item()
		and item_resource_path != equipped_item_resource_path
	):
		print(
			"Ausrüstungswechsel abgelehnt: Großitem muss zuerst abgelegt werden."
		)
		return

	if (
		multiplayer.is_server()
		and not item_resource_path.is_empty()
		and item_resource_path not in server_inventory_paths
	):
		push_warning("Ausgerüstetes Item ist nicht im Server-Inventar.")
		return

	equipped_item_resource_path = item_resource_path
	_clear_world_held_item()

	if item_resource_path.is_empty():
		return

	var loaded_resource := load(item_resource_path)

	if not loaded_resource is ItemData:
		push_error("World ItemData konnte nicht geladen werden: " + item_resource_path)
		return

	var data := loaded_resource as ItemData
	_equip_world_item(data)
	
func _equip_world_item(data: ItemData) -> void:
	_clear_world_held_item()

	if data == null:
		return

	if data.held_model == null:
		return

	var instance := data.held_model.instantiate()

	if not instance is Node3D:
		instance.queue_free()
		return

	world_held_item_instance = instance as Node3D

	world_held_item_instance.position = data.held_offset
	world_held_item_instance.rotation_degrees = data.held_rotation_degrees
	world_held_item_instance.scale = data.held_scale

	world_item_holder.add_child(world_held_item_instance)
	
func _clear_world_held_item() -> void:
	if world_held_item_instance == null:
		return

	world_held_item_instance.queue_free()
	world_held_item_instance = null

func _equip_item(data: ItemData) -> void:
	_clear_held_item()

	if data == null:
		return

	if data.held_model == null:
		push_warning(
			"Item '%s' besitzt kein Held Model."
			% data.display_name
		)
		return

	var instance := data.held_model.instantiate()

	if not instance is Node3D:
		instance.queue_free()
		push_error(
			"Held Model von '%s' muss einen Node3D als Root besitzen."
			% data.display_name
		)
		return

	held_item_instance = instance as Node3D

	# Erst Transform setzen.
	held_item_instance.position = data.held_offset
	held_item_instance.rotation_degrees = data.held_rotation_degrees
	held_item_instance.scale = data.held_scale

	# Danach hinzufügen, damit _ready() die richtigen Werte speichert.
	item_holder.add_child(held_item_instance)

func unequip_current_item() -> void:
	if is_holding_large_item():
		print("Großitem kann nur durch Ablegen abgewählt werden.")
		return

	selected_inventory_index = -1
	equipped_item_resource_path = ""
	_clear_held_item()
	_sync_equipped_item.rpc("")
	_emit_inventory_changed()


func _clear_held_item() -> void:
	if held_item_instance == null:
		return

	held_item_instance.queue_free()
	held_item_instance = null
func _update_interaction_text() -> void:
	if not is_multiplayer_authority():
		return

	if interaction_label == null or interaction_ray == null:
		return

	interaction_ray.force_raycast_update()

	if not interaction_ray.is_colliding():
		interaction_label.visible = false
		return

	var collider := interaction_ray.get_collider()

	if collider == null:
		interaction_label.visible = false
		return

	if collider.has_method("get_interaction_text"):
		interaction_label.text = "[E] " + str(collider.get_interaction_text())
		interaction_label.visible = true
	elif collider is PickupItem:
		var pickup := collider as PickupItem

		if pickup.item_data == null:
			interaction_label.visible = false
			return

		if is_holding_large_item():
			interaction_label.text = "[E] Hände voll (Großitem)"
			interaction_label.visible = true
			return

		interaction_label.text = "[E] " + pickup.item_data.interaction_text
		interaction_label.visible = true
	else:
		interaction_label.visible = false

func clear_inventory() -> void:
	inventory.clear()

	if multiplayer.is_server():
		server_inventory_paths.clear()

	selected_inventory_index = -1
	equipped_item_resource_path = ""
	_clear_held_item()
	_sync_equipped_item.rpc("")
	_emit_inventory_changed()

	print("Inventar wurde geleert.")
	
func _exit_tree() -> void:
	_clear_held_item()
	inventory.clear()

	if is_instance_valid(player_hud):
		player_hud.queue_free()

	player_hud = null
	
func _use_held_item() -> void:
	if not is_multiplayer_authority():
		return

	if held_item_instance == null:
		return

	if held_item_instance.has_method("use_primary"):
		held_item_instance.use_primary()

	_play_world_item_use.rpc()
	
	
@rpc("authority", "call_remote", "unreliable")
func _play_world_item_use() -> void:
	if world_held_item_instance == null:
		return

	if world_held_item_instance.has_method("use_primary"):
		world_held_item_instance.use_primary()

func _update_hand_sway(delta: float) -> void:
	if item_holder == null:
		return

	if not hand_sway_enabled:
		var reset_weight := 1.0 - exp(-sway_smoothing * delta)

		item_holder.position = item_holder.position.lerp(
			_item_holder_start_position,
			reset_weight
		)

		item_holder.rotation = item_holder.rotation.lerp(
			_item_holder_start_rotation,
			reset_weight
		)

		_mouse_sway_input = Vector2.ZERO
		return

	var max_rotation := deg_to_rad(sway_max_rotation_degrees)

	# Mausbewegung
	var mouse_position_offset := Vector3(
		-_mouse_sway_input.x * sway_position_amount,
		_mouse_sway_input.y * sway_position_amount,
		0.0
	)

	mouse_position_offset.x = clampf(
		mouse_position_offset.x,
		-sway_max_position,
		sway_max_position
	)

	mouse_position_offset.y = clampf(
		mouse_position_offset.y,
		-sway_max_position,
		sway_max_position
	)

	var mouse_rotation_offset := Vector3(
		deg_to_rad(_mouse_sway_input.y * sway_rotation_amount),
		deg_to_rad(_mouse_sway_input.x * sway_rotation_amount),
		deg_to_rad(_mouse_sway_input.x * sway_rotation_amount * 0.5)
	)

	mouse_rotation_offset.x = clampf(
		mouse_rotation_offset.x,
		-max_rotation,
		max_rotation
	)

	mouse_rotation_offset.y = clampf(
		mouse_rotation_offset.y,
		-max_rotation,
		max_rotation
	)

	mouse_rotation_offset.z = clampf(
		mouse_rotation_offset.z,
		-max_rotation,
		max_rotation
	)

	# Laufbewegung
	var movement_input := Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_backward"
	)

	var movement_position_offset := Vector3(
		-movement_input.x * movement_sway_amount,
		-absf(movement_input.y) * movement_sway_amount * 0.2,
		0.0
	)

	var movement_rotation_offset := Vector3(
		deg_to_rad(-movement_input.y * movement_rotation_amount),
		0.0,
		deg_to_rad(-movement_input.x * movement_rotation_amount)
	)

	# Leichte Idle-Bewegung
	var idle_position_offset := Vector3.ZERO
	var idle_rotation_offset := Vector3.ZERO

	if idle_sway_enabled:
		_idle_sway_time += delta * idle_sway_speed

		idle_position_offset = Vector3(
			sin(_idle_sway_time) * idle_sway_amount,
			cos(_idle_sway_time * 0.7) * idle_sway_amount,
			0.0
		)

		idle_rotation_offset = Vector3(
			deg_to_rad(cos(_idle_sway_time * 0.6) * 0.3),
			deg_to_rad(sin(_idle_sway_time * 0.5) * 0.3),
			0.0
		)

	var target_position := (
		_item_holder_start_position
		+ mouse_position_offset
		+ movement_position_offset
		+ idle_position_offset
	)

	var target_rotation := (
		_item_holder_start_rotation
		+ mouse_rotation_offset
		+ movement_rotation_offset
		+ idle_rotation_offset
	)

	var smoothing_weight := 1.0 - exp(-sway_smoothing * delta)

	item_holder.position = item_holder.position.lerp(
		target_position,
		smoothing_weight
	)

	item_holder.rotation = item_holder.rotation.lerp(
		target_rotation,
		smoothing_weight
	)

	_mouse_sway_input = _mouse_sway_input.lerp(
		Vector2.ZERO,
		smoothing_weight
	)
