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

@export_group("Health")
@export_range(1.0, 1000.0, 1.0) var maximum_health := 100.0
@export_range(1.0, 1000.0, 1.0) var revive_health := 50.0
@export_range(1.0, 10.0, 0.1) var revive_distance := 2.5

@export_group("Combat")
@export_range(0.0, 1000.0, 1.0) var pistol_damage := 34.0
@export_range(0.0, 1000.0, 1.0) var sniper_damage := 100.0
@export_range(0.0, 1000.0, 1.0) var knife_damage := 45.0

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
signal health_changed(current_health: float, maximum_health: float)
signal died
signal revived

# ─────────────────────────────────────────────
# NODES
# ─────────────────────────────────────────────

@onready var head: Node3D                         = $Head
@onready var camera: Camera3D                     = $Head/Camera3D
@onready var live_feed_camera: Camera3D = $Head/LiveFeedCamera
@onready var standing_collision: CollisionShape3D = $CollisionShape3D
@onready var crouch_collision: CollisionShape3D   = $CrouchCollision
@onready var player_hitbox: CollisionShape3D = $PlayerHitbox/CollisionShape3D
@onready var uncroch_raycast: RayCast3D           = $StandingRaycast
@onready var interaction_ray: RayCast3D = $Head/Camera3D/InteractionRay
@onready var item_holder: Marker3D = $Head/Camera3D/ItemHolder
@onready var player_animation: Node = $PlayerAnimationController
@onready var ragdoll_controller: Node = $PlayerRagdollController
@onready var blood_effects: Node = $PlayerBloodEffects
@onready var player_name_label: Label3D = $PlayerNameLabel
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
var current_health: float = 0.0
var is_dead := false
var _sprint_active := false
var _sprint_exhausted := false
var _stamina_recovery_delay_remaining := 0.0
var _base_mouse_sensitivity: float
var _base_controller_sensitivity: float
var _weapon_aim_sensitivity_multiplier := 1.0
var _look_sway_impulse := Vector2.ZERO
var _current_look_sway := Vector2.ZERO
var _current_look_sway_roll := 0.0
var _driven_vehicle: Node3D = null
var _vehicle_entry_scale := Vector3.ONE
var _active_camera_monitor: Node3D = null
var _camera_monitor_mode_active := false
var _monitor_camera_local_transform := Transform3D.IDENTITY
var _monitor_camera_fov := 75.0
var _monitor_previous_mouse_mode := Input.MOUSE_MODE_CAPTURED
var _hovered_pickup: PickupItem = null
var _last_attack_time_by_type: Dictionary = {}
var _steam_name_refresh_remaining := 0.0
var _steam_name_resolved := false

# Multiplayer sync
var _sync_timer: float        = 0.0
var world_held_item_instance: Node3D = null

const STEP_INTERVAL_WALK   := 0.55
const STEP_INTERVAL_SPRINT := 0.42
const PISTOL_ATTACK_RANGE := 105.0
const SNIPER_ATTACK_RANGE := 500.0
const KNIFE_ATTACK_RANGE := 2.5
const PISTOL_SERVER_COOLDOWN_MSEC := 180
const SNIPER_SERVER_COOLDOWN_MSEC := 1200
const KNIFE_SERVER_COOLDOWN_MSEC := 350
const PISTOL_ITEM_PATH := "res://resources/items/1911.tres"
const SNIPER_ITEM_PATH := "res://resources/items/sniper.tres"
const KNIFE_ITEM_PATH := "res://resources/items/knife.tres"
const LOCAL_HEAD_RENDER_LAYER := 20

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
	current_health = maximum_health
	_base_mouse_sensitivity = mouse_sensitivity
	_base_controller_sensitivity = controller_sensitivity

	_item_holder_start_position = item_holder.position
	_item_holder_start_rotation = item_holder.rotation

	if is_multiplayer_authority():
		add_to_group("local_player_controller")
		_load_look_sensitivity()
		_hide_local_head_from_camera()
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

	_setup_player_name_label()


func _hide_local_head_from_camera() -> void:
	camera.set_cull_mask_value(LOCAL_HEAD_RENDER_LAYER, false)

	var skeleton := get_node_or_null(
		"playerModell/Armature/Skeleton3D"
	)

	if skeleton == null:
		push_warning("Spieler-Skelett zum Ausblenden des Kopfes fehlt.")
		return

	for mesh_path in [^"Head", ^"Hair"]:
		var head_part := skeleton.get_node_or_null(mesh_path) as VisualInstance3D

		if head_part == null:
			continue

		head_part.set_layer_mask_value(1, false)
		head_part.set_layer_mask_value(LOCAL_HEAD_RENDER_LAYER, true)


func _process(delta: float) -> void:
	_update_player_name_label_position()

	if player_name_label == null or not player_name_label.visible:
		return

	_steam_name_refresh_remaining -= delta

	if _steam_name_refresh_remaining <= 0.0:
		_refresh_player_name_label()
		_steam_name_refresh_remaining = 10.0 if _steam_name_resolved else 1.0


func _setup_player_name_label() -> void:
	if player_name_label == null:
		return

	var peer_id := get_multiplayer_authority()
	player_name_label.visible = peer_id > 0 and not is_multiplayer_authority()
	player_name_label.text = "Spieler %d" % peer_id
	_steam_name_refresh_remaining = 0.0


func _refresh_player_name_label() -> void:
	if player_name_label == null or not player_name_label.visible:
		return

	var peer_id := get_multiplayer_authority()
	var display_name := Networking.get_player_display_name(peer_id)

	if display_name.is_empty():
		return

	player_name_label.text = display_name
	_steam_name_resolved = true


func _update_player_name_label_position() -> void:
	if player_name_label == null or not player_name_label.visible:
		return

	if is_dead and ragdoll_controller.is_ragdoll_active():
		player_name_label.top_level = true
		player_name_label.global_position = (
			ragdoll_controller.get_ragdoll_center_position()
			+ Vector3.UP * 1.35
		)
		return

	player_name_label.top_level = false
	player_name_label.position = Vector3(0.0, 2.25, 0.0)

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

	if is_using_camera_monitor():
		if event.is_action_pressed("ui_cancel"):
			exit_camera_monitor()
			get_viewport().set_input_as_handled()

		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_mouse_sway_input += event.relative
		_rotate_camera(
			event.relative
			* mouse_sensitivity
			* _weapon_aim_sensitivity_multiplier
		)

	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = \
			Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
			else Input.MOUSE_MODE_CAPTURED

	if event.is_action_released("secondary_use"):
		_use_held_item_secondary(false)

	if is_dead:
		return

	if event.is_action_pressed("secondary_use"):
		_use_held_item_secondary(true)

	if event.is_action_pressed("jump"):
		_jump_buffer = jump_buffer_time

	if event.is_action_pressed("wave") and not is_driving_vehicle():
		player_animation.play_wave()
		_play_wave_remote.rpc()
		
	if event.is_action_pressed("primary_use"):
		_use_held_item()

	if event.is_action_pressed("interact"):
		if is_driving_vehicle():
			if _driven_vehicle.has_method("request_driver_exit"):
				_driven_vehicle.request_driver_exit(self)
		else:
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


func set_weapon_aim_sensitivity_multiplier(multiplier: float) -> void:
	_weapon_aim_sensitivity_multiplier = clampf(multiplier, 0.05, 1.0)

# ─────────────────────────────────────────────
# PHYSICS PROCESS
# ─────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		# Fremde Spieler: Interpolation zum zuletzt empfangenen State
		# (läuft weiter, move_and_slide sorgt für korrekte Kollision)
		return

	if is_dead:
		velocity = Vector3.ZERO

		if interaction_label != null:
			interaction_label.visible = false

		return

	if is_using_camera_monitor():
		_process_camera_monitor(delta)
		return

	if is_driving_vehicle():
		_update_controller_look(delta)
		_update_hand_sway(delta)
		_update_interaction_text()
		velocity = Vector3.ZERO
		_update_tilt(delta)
		_update_look_sway(delta)
		_update_head_bob(delta)
		_broadcast_local_state(delta)
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

	_broadcast_local_state(delta)


func _broadcast_local_state(delta: float) -> void:
	# State an alle anderen Peers broadcasten
	_sync_timer += delta
	if _sync_timer >= 1.0 / sync_rate:
		_sync_timer = 0.0
		_broadcast_state.rpc(
			global_position,
			global_rotation,
			head.rotation.x,
			_is_crouching,
			player_animation.get_locomotion_state()
		)

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
	crouching: bool,
	locomotion_animation: StringName
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
	player_animation.set_locomotion_state(locomotion_animation)


@rpc("authority", "call_remote", "reliable")
func _play_wave_remote() -> void:
	player_animation.play_wave()


func play_player_action(animation_name: StringName) -> void:
	if not is_inside_tree() or not is_multiplayer_authority() or is_dead:
		return

	player_animation.play_action(animation_name)
	_play_player_action_remote.rpc(animation_name)


@rpc("authority", "call_remote", "reliable")
func _play_player_action_remote(animation_name: StringName) -> void:
	player_animation.play_action(animation_name)

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
		_rotate_camera(
			look_input
			* controller_sensitivity
			* _weapon_aim_sensitivity_multiplier
			* delta
		)


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

func request_player_attack(
	target_collider: Object,
	attack_type: StringName,
	hit_position: Vector3,
	hit_normal: Vector3
) -> void:
	if not is_multiplayer_authority() or is_dead:
		return

	var target_player := _find_player_from_node(target_collider)

	if target_player == null or target_player == self:
		return

	var target_peer_id := target_player.get_multiplayer_authority()

	if multiplayer.is_server():
		_server_process_player_attack(
			target_peer_id,
			attack_type,
			hit_position,
			hit_normal
		)
	else:
		_request_player_attack_server.rpc_id(
			1,
			target_peer_id,
			attack_type,
			hit_position,
			hit_normal
		)


@rpc("any_peer", "call_remote", "reliable")
func _request_player_attack_server(
	target_peer_id: int,
	attack_type: StringName,
	hit_position: Vector3,
	hit_normal: Vector3
) -> void:
	if not multiplayer.is_server():
		return

	if multiplayer.get_remote_sender_id() != get_multiplayer_authority():
		return

	_server_process_player_attack(
		target_peer_id,
		attack_type,
		hit_position,
		hit_normal
	)


func _server_process_player_attack(
	target_peer_id: int,
	attack_type: StringName,
	hit_position: Vector3,
	hit_normal: Vector3
) -> void:
	if not multiplayer.is_server() or is_dead:
		return

	var attack_data := _get_server_attack_data(attack_type)

	if attack_data.is_empty():
		return

	if equipped_item_resource_path != attack_data["required_item"]:
		return

	var now := Time.get_ticks_msec()
	var last_attack_time := int(_last_attack_time_by_type.get(attack_type, -10000))

	if now - last_attack_time < int(attack_data["cooldown_msec"]):
		return

	var players_root := get_parent()

	if players_root == null:
		return

	var target_player := players_root.get_node_or_null(
		str(target_peer_id)
	) as FPSController

	if target_player == null or target_player == self or target_player.is_dead:
		return

	if global_position.distance_to(target_player.global_position) > float(
		attack_data["range"]
	):
		return

	if not _server_attack_path_reaches_target(
		target_player,
		hit_position,
		attack_type
	):
		return

	_last_attack_time_by_type[attack_type] = now
	var impulse_direction := (
		target_player.global_position - global_position
	).normalized()

	if impulse_direction.length_squared() < 0.001:
		impulse_direction = -global_basis.z

	target_player.server_receive_damage(
		float(attack_data["damage"]),
		get_multiplayer_authority(),
		hit_position,
		hit_normal,
		impulse_direction * float(attack_data["impulse"])
	)


func _server_attack_path_reaches_target(
	target_player: FPSController,
	hit_position: Vector3,
	attack_type: StringName
) -> bool:
	if hit_position.distance_to(target_player.global_position) > 3.0:
		return false

	var ray_origin := camera.global_position
	var ray_direction := (hit_position - ray_origin).normalized()
	var minimum_aim_dot := 0.7 if attack_type == &"knife" else 0.965

	if attack_type == &"sniper":
		minimum_aim_dot = 0.99

	if (-camera.global_basis.z).dot(ray_direction) < minimum_aim_dot:
		return false

	var query := PhysicsRayQueryParameters3D.create(
		ray_origin,
		hit_position + ray_direction * 0.15
	)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var exclusions: Array[RID] = [get_rid()]
	var own_hitbox := $PlayerHitbox as CollisionObject3D

	if own_hitbox != null:
		exclusions.append(own_hitbox.get_rid())

	query.exclude = exclusions
	var hit := get_world_3d().direct_space_state.intersect_ray(query)

	if hit.is_empty():
		return false

	return _find_player_from_node(hit["collider"]) == target_player


func _get_server_attack_data(attack_type: StringName) -> Dictionary:
	if attack_type == &"pistol":
		return {
			"damage": pistol_damage,
			"range": PISTOL_ATTACK_RANGE,
			"cooldown_msec": PISTOL_SERVER_COOLDOWN_MSEC,
			"required_item": PISTOL_ITEM_PATH,
			"impulse": 2.4,
		}

	if attack_type == &"sniper":
		return {
			"damage": sniper_damage,
			"range": SNIPER_ATTACK_RANGE,
			"cooldown_msec": SNIPER_SERVER_COOLDOWN_MSEC,
			"required_item": SNIPER_ITEM_PATH,
			"impulse": 5.5,
		}

	if attack_type == &"knife":
		return {
			"damage": knife_damage,
			"range": KNIFE_ATTACK_RANGE,
			"cooldown_msec": KNIFE_SERVER_COOLDOWN_MSEC,
			"required_item": KNIFE_ITEM_PATH,
			"impulse": 1.2,
		}

	return {}


func server_receive_damage(
	damage: float,
	_attacker_peer_id: int,
	hit_position: Vector3,
	hit_normal: Vector3,
	death_impulse: Vector3
) -> void:
	if not multiplayer.is_server() or is_dead:
		return

	current_health = maxf(current_health - maxf(damage, 0.0), 0.0)
	var died_from_damage := current_health <= 0.0
	_sync_damage_result.rpc(
		current_health,
		died_from_damage,
		hit_position,
		hit_normal,
		death_impulse
	)


@rpc("any_peer", "call_local", "reliable")
func _sync_damage_result(
	health: float,
	died_from_damage: bool,
	hit_position: Vector3,
	hit_normal: Vector3,
	death_impulse: Vector3
) -> void:
	if not _is_rpc_from_server():
		return

	current_health = clampf(health, 0.0, maximum_health)
	health_changed.emit(current_health, maximum_health)
	blood_effects.spawn_blood_impact(hit_position, hit_normal)

	if died_from_damage and not is_dead:
		_enter_dead_state(death_impulse)
	elif not is_dead:
		player_animation.play_action(&"ual/Hit_Chest")


func get_interaction_text() -> String:
	return "Wiederbeleben" if is_dead else ""


func request_interaction(reviver: Node3D) -> void:
	if not is_dead or reviver == null or reviver == self:
		return

	if not reviver is FPSController or (reviver as FPSController).is_dead:
		return

	if multiplayer.is_server():
		_server_try_revive(reviver.get_multiplayer_authority())
	else:
		_request_revive_server.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_revive_server() -> void:
	if not multiplayer.is_server() or not is_dead:
		return

	_server_try_revive(multiplayer.get_remote_sender_id())


func _server_try_revive(reviver_peer_id: int) -> void:
	if not multiplayer.is_server() or not is_dead:
		return

	var players_root := get_parent()
	var reviver := (
		players_root.get_node_or_null(str(reviver_peer_id)) as FPSController
		if players_root != null
		else null
	)

	if reviver == null or reviver == self or reviver.is_dead:
		return

	var ragdoll_center: Vector3 = ragdoll_controller.get_ragdoll_center_position()

	if reviver.global_position.distance_to(ragdoll_center) > revive_distance:
		return

	current_health = minf(revive_health, maximum_health)
	var revive_position := Vector3(
		ragdoll_center.x,
		global_position.y,
		ragdoll_center.z
	)
	_sync_revive_result.rpc(current_health, revive_position)


@rpc("any_peer", "call_local", "reliable")
func _sync_revive_result(health: float, revive_position: Vector3) -> void:
	if not _is_rpc_from_server():
		return

	current_health = clampf(health, 1.0, maximum_health)
	global_position = revive_position
	health_changed.emit(current_health, maximum_health)
	_leave_dead_state()


func server_sync_vitals_to_peer(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	_sync_vital_snapshot.rpc_id(peer_id, current_health, is_dead)


@rpc("any_peer", "call_remote", "reliable")
func _sync_vital_snapshot(health: float, dead: bool) -> void:
	if not _is_rpc_from_server():
		return

	current_health = clampf(health, 0.0, maximum_health)
	health_changed.emit(current_health, maximum_health)

	if dead and not is_dead:
		_enter_dead_state(Vector3.ZERO)
	elif not dead and is_dead:
		_leave_dead_state()


func _enter_dead_state(death_impulse: Vector3) -> void:
	exit_camera_monitor()
	_use_held_item_secondary(false)
	is_dead = true
	velocity = Vector3.ZERO
	_sprint_active = false
	standing_collision.set_deferred("disabled", true)
	crouch_collision.set_deferred("disabled", true)
	player_hitbox.set_deferred("disabled", true)
	item_holder.visible = false
	world_item_holder.visible = false
	player_animation.set_ragdoll_active(true)
	ragdoll_controller.set_ragdoll_active(true, death_impulse)
	died.emit()


func _leave_dead_state() -> void:
	is_dead = false
	_is_crouching = false
	_target_head_y = stand_head_y
	_target_col_height = stand_height
	ragdoll_controller.set_ragdoll_active(false)
	player_animation.set_ragdoll_active(false)
	standing_collision.set_deferred("disabled", false)
	crouch_collision.set_deferred("disabled", true)
	player_hitbox.set_deferred("disabled", false)
	item_holder.visible = is_multiplayer_authority()
	world_item_holder.visible = not is_multiplayer_authority()
	revived.emit()


func _find_player_from_node(value: Object) -> FPSController:
	var current_node := value as Node

	while current_node != null:
		if current_node is FPSController:
			return current_node as FPSController

		current_node = current_node.get_parent()

	return null


func _is_rpc_from_server() -> bool:
	var sender_peer_id := multiplayer.get_remote_sender_id()
	return sender_peer_id == 0 or sender_peer_id == 1


func is_moving() -> bool:
	return Vector2(velocity.x, velocity.z).length() > 0.1

func is_sprinting() -> bool:
	return _sprint_active and is_moving()

func is_crouching() -> bool:
	return _is_crouching

func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func is_using_camera_monitor(monitor: Node3D = null) -> bool:
	if not _camera_monitor_mode_active:
		return false

	if monitor == null:
		return true

	return (
		is_instance_valid(_active_camera_monitor)
		and _active_camera_monitor == monitor
	)


func enter_camera_monitor(monitor: Node3D) -> bool:
	if (
		monitor == null
		or not is_multiplayer_authority()
		or is_dead
		or is_driving_vehicle()
	):
		return false

	if is_using_camera_monitor(monitor):
		return true

	if is_using_camera_monitor():
		exit_camera_monitor()

	_use_held_item_secondary(false)

	_active_camera_monitor = monitor
	_camera_monitor_mode_active = true
	_monitor_camera_local_transform = camera.transform
	_monitor_camera_fov = camera.fov
	_monitor_previous_mouse_mode = Input.mouse_mode
	velocity = Vector3.ZERO
	item_holder.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_update_camera_monitor_view()
	return true


func exit_camera_monitor() -> void:
	if not is_using_camera_monitor():
		return

	var monitor := _active_camera_monitor
	_camera_monitor_mode_active = false
	_active_camera_monitor = null
	camera.transform = _monitor_camera_local_transform
	camera.fov = _monitor_camera_fov
	item_holder.visible = is_multiplayer_authority()
	Input.mouse_mode = _monitor_previous_mouse_mode

	if is_instance_valid(monitor) and monitor.has_method("end_view"):
		monitor.end_view(self)

	if interaction_label != null:
		interaction_label.visible = false


func get_live_feed_transform() -> Transform3D:
	return live_feed_camera.global_transform


func get_live_feed_fov() -> float:
	return live_feed_camera.fov


func _process_camera_monitor(delta: float) -> void:
	if not is_using_camera_monitor():
		return

	if not is_instance_valid(_active_camera_monitor):
		exit_camera_monitor()
		return

	if Input.is_action_just_pressed("move_forward"):
		_active_camera_monitor.next_camera()
	elif Input.is_action_just_pressed("move_backward"):
		_active_camera_monitor.previous_camera()

	var pan_direction := Input.get_axis("move_left", "move_right")
	_active_camera_monitor.rotate_current_camera(pan_direction, delta)
	velocity = Vector3.ZERO
	_update_camera_monitor_view()

	if interaction_label != null:
		interaction_label.text = (
			"[W/S] Feed  [A/D] Kamera drehen  [ESC] Beenden"
		)
		interaction_label.visible = true

	_broadcast_local_state(delta)


func _update_camera_monitor_view() -> void:
	if not is_using_camera_monitor():
		return

	if (
		not is_instance_valid(_active_camera_monitor)
		or not _active_camera_monitor.has_method("get_view_transform")
	):
		exit_camera_monitor()
		return

	camera.global_transform = _active_camera_monitor.get_view_transform(
		global_position
	)
	camera.fov = _active_camera_monitor.get_viewing_fov()


func is_driving_vehicle() -> bool:
	return is_instance_valid(_driven_vehicle)


func enter_vehicle(
	vehicle: Node3D,
	seat_transform: Transform3D
) -> void:
	if vehicle == null:
		return

	exit_camera_monitor()

	if _driven_vehicle == vehicle:
		return

	_vehicle_entry_scale = global_basis.get_scale()
	_driven_vehicle = vehicle
	velocity = Vector3.ZERO
	global_transform = _vehicle_marker_transform(seat_transform)
	_is_crouching = false
	_target_head_y = stand_head_y
	_target_col_height = stand_height

	if standing_collision != null:
		standing_collision.set_deferred("disabled", true)

	if crouch_collision != null:
		crouch_collision.set_deferred("disabled", true)


func exit_vehicle(
	vehicle: Node3D,
	exit_transform: Transform3D,
	vehicle_velocity: Vector3 = Vector3.ZERO
) -> void:
	if _driven_vehicle != vehicle:
		return

	_driven_vehicle = null
	global_transform = _vehicle_marker_transform(exit_transform)
	velocity = vehicle_velocity
	_is_crouching = false
	_target_head_y = stand_head_y
	_target_col_height = stand_height

	if standing_collision != null:
		standing_collision.set_deferred("disabled", false)

	if crouch_collision != null:
		crouch_collision.set_deferred("disabled", true)


func _vehicle_marker_transform(marker_transform: Transform3D) -> Transform3D:
	# Vehicle markers inherit the vehicle's scale. Keep only their rotation and
	# position so entering or exiting a scaled vehicle cannot resize the player.
	var rotation_basis := marker_transform.basis.orthonormalized()
	return Transform3D(
		rotation_basis.scaled(_vehicle_entry_scale),
		marker_transform.origin
	)


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
	if not is_multiplayer_authority() or is_dead:
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

	var interaction_target := _resolve_interaction_target(collider)

	if interaction_target == null:
		return

	print(
		"InteractionRay trifft: ",
		interaction_target.name,
		" | Klasse: ",
		interaction_target.get_class()
	)

	if interaction_target.has_method("request_interaction"):
		interaction_target.request_interaction(self)
		play_player_action(&"ual/Interact")
	elif interaction_target.has_method("request_pickup"):
		if is_holding_large_item():
			print("Mit einem Großitem in der Hand kann nichts aufgenommen werden.")
			return

		print("Pickup wird angefragt")
		interaction_target.request_pickup()
		play_player_action(&"ual/PickUp_Table")
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

	if held_item_instance.has_method("use_secondary"):
		held_item_instance.use_secondary(false)

	held_item_instance.queue_free()
	held_item_instance = null
func _update_interaction_text() -> void:
	if not is_multiplayer_authority():
		return

	if is_dead:
		_set_hovered_pickup(null)

		if interaction_label != null:
			interaction_label.visible = false

		return

	if interaction_label == null or interaction_ray == null:
		_set_hovered_pickup(null)
		return

	if is_driving_vehicle():
		_set_hovered_pickup(null)
		interaction_label.text = "[W/S] Gas  [A/D] Lenken  [E] Aussteigen"
		interaction_label.visible = true
		return

	interaction_ray.force_raycast_update()

	if not interaction_ray.is_colliding():
		_set_hovered_pickup(null)
		interaction_label.visible = false
		return

	var collider := interaction_ray.get_collider()

	if collider == null:
		_set_hovered_pickup(null)
		interaction_label.visible = false
		return

	var interaction_target := _resolve_interaction_target(collider)

	if interaction_target == null:
		_set_hovered_pickup(null)
		interaction_label.visible = false
		return

	if interaction_target.has_method("get_interaction_text"):
		_set_hovered_pickup(null)
		var text := str(interaction_target.get_interaction_text())
		interaction_label.text = "[E] " + text
		interaction_label.visible = not text.is_empty()
	elif interaction_target is PickupItem:
		var pickup := interaction_target as PickupItem
		_set_hovered_pickup(pickup)

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
		_set_hovered_pickup(null)
		interaction_label.visible = false


func _resolve_interaction_target(collider: Object) -> Node:
	var current_node := collider as Node

	while current_node != null:
		if (
			current_node.has_method("request_interaction")
			or current_node.has_method("request_pickup")
		):
			return current_node

		current_node = current_node.get_parent()

	return null


func _set_hovered_pickup(pickup: PickupItem) -> void:
	if _hovered_pickup == pickup:
		return

	if is_instance_valid(_hovered_pickup):
		_hovered_pickup.set_hovered(false)

	_hovered_pickup = pickup

	if is_instance_valid(_hovered_pickup):
		_hovered_pickup.set_hovered(true)

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
	exit_camera_monitor()
	_set_hovered_pickup(null)
	_clear_held_item()
	inventory.clear()

	if is_instance_valid(player_hud):
		player_hud.queue_free()

	player_hud = null
	
func _use_held_item() -> void:
	if not is_multiplayer_authority() or is_dead:
		return

	if held_item_instance == null:
		return

	if held_item_instance.has_method("use_primary"):
		held_item_instance.use_primary()

	_play_world_item_use.rpc()


func _use_held_item_secondary(is_pressed: bool) -> void:
	if not is_multiplayer_authority():
		return

	if held_item_instance == null:
		set_weapon_aim_sensitivity_multiplier(1.0)
		return

	if held_item_instance.has_method("use_secondary"):
		held_item_instance.use_secondary(is_pressed)
	
	
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
