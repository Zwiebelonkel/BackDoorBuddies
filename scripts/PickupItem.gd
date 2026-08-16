class_name PickupItem
extends Area3D

const OUTLINE_SHADER := preload("res://shaders/outline.gdshader")

@export_group("Item")
@export var item_data: ItemData:
	set(value):
		item_data = value

		if is_node_ready():
			_apply_item_data()

@export_group("Pickup")
@export var pickup_distance: float = 3.5
@export var can_be_picked_up: bool = true
@export var initial_pickup_delay: float = 0.35

@export_group("Vehicle Cargo")
@export var van_attached := false
@export var van_local_transform := Transform3D.IDENTITY

@export_group("Animation")
@export var rotate_model: bool = false
@export var rotation_speed: float = 35.0
@export var floating_enabled: bool = false
@export var floating_height: float = 0.08
@export var floating_speed: float = 2.0

@onready var model_container: Node3D = $ModelContainer
@onready var pickup_audio: AudioStreamPlayer3D = $AudioStreamPlayer3D

var _model_instance: Node3D
var _was_picked_up := false
var _start_model_position := Vector3.ZERO
var _floating_time := 0.0
var use_initial_pickup_delay := false
var _is_hovered := false
var _outline_material: ShaderMaterial
var _previous_material_overlays: Dictionary = {}


func _ready() -> void:
	_apply_item_data()

	if model_container:
		_start_model_position = model_container.position

	if use_initial_pickup_delay and initial_pickup_delay > 0.0:
		can_be_picked_up = false
		_unlock_pickup_after_delay()


func _unlock_pickup_after_delay() -> void:
	await get_tree().create_timer(initial_pickup_delay).timeout

	if is_inside_tree() and not _was_picked_up:
		can_be_picked_up = true


func _process(delta: float) -> void:
	if rotate_model and model_container:
		model_container.rotate_y(deg_to_rad(rotation_speed) * delta)

	if floating_enabled and model_container:
		_floating_time += delta * floating_speed
		model_container.position.y = (
			_start_model_position.y
			+ sin(_floating_time) * floating_height
		)


func _apply_item_data() -> void:
	if not is_node_ready():
		return

	_clear_current_model()

	if item_data == null:
		push_warning("PickupItem besitzt keine ItemData.")
		return

	if item_data.world_model == null:
		push_warning(
			"Item '%s' besitzt kein World Model."
			% item_data.display_name
		)
		return

	var model := item_data.world_model.instantiate()

	if not model is Node3D:
		model.queue_free()
		push_error("Das World Model muss einen Node3D als Root haben.")
		return

	_model_instance = model as Node3D
	model_container.add_child(_model_instance)

	_model_instance.position = item_data.model_offset
	_model_instance.rotation_degrees = item_data.model_rotation_degrees
	_model_instance.scale = item_data.model_scale

	pickup_audio.stream = item_data.pickup_sound

	if _is_hovered:
		_apply_hover_outline()


func _clear_current_model() -> void:
	if _model_instance == null:
		return

	_remove_hover_outline()
	_model_instance.queue_free()
	_model_instance = null


func set_hovered(hovered: bool) -> void:
	if _is_hovered == hovered:
		return

	_is_hovered = hovered

	if _is_hovered:
		_apply_hover_outline()
	else:
		_remove_hover_outline()


func _apply_hover_outline() -> void:
	if _model_instance == null:
		return

	if _outline_material == null:
		_outline_material = ShaderMaterial.new()
		_outline_material.shader = OUTLINE_SHADER
		_outline_material.set_shader_parameter(
			"outline_color",
			Color(0.0, 1.0, 0.0352941, 1.0)
		)
		_outline_material.set_shader_parameter("thickness", 0.04)
		_outline_material.set_shader_parameter("outline_energy", 4.0)
		_outline_material.set_shader_parameter("outline_transparency", 1.0)
		_outline_material.set_shader_parameter("merge_group", true)
		_outline_material.set_shader_parameter("merge_depth_range", 0.1)

	_previous_material_overlays.clear()

	for child in _model_instance.find_children(
		"*",
		"MeshInstance3D",
		true,
		false
	):
		var mesh_instance := child as MeshInstance3D
		_previous_material_overlays[mesh_instance] = mesh_instance.material_overlay
		mesh_instance.material_overlay = _outline_material


func _remove_hover_outline() -> void:
	for mesh_variant in _previous_material_overlays:
		var mesh_instance := mesh_variant as MeshInstance3D

		if is_instance_valid(mesh_instance):
			mesh_instance.material_overlay = _previous_material_overlays[mesh_variant]

	_previous_material_overlays.clear()


func attach_to_van(van_transform: Transform3D) -> void:
	if not multiplayer.is_server() or van_attached:
		return

	van_local_transform = (
		van_transform.affine_inverse()
		* global_transform
	)
	van_attached = true


func detach_from_van() -> void:
	if not multiplayer.is_server():
		return

	van_attached = false
	van_local_transform = Transform3D.IDENTITY


func apply_van_transform(van_transform: Transform3D) -> void:
	if van_attached:
		global_transform = van_transform * van_local_transform
	
func request_pickup() -> void:
	if not can_be_picked_up:
		return

	if _was_picked_up:
		return

	if item_data == null:
		return

	var peer_id := multiplayer.get_unique_id()

	if multiplayer.is_server():
		_server_try_pickup(peer_id)
	else:
		_request_pickup_server.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_pickup_server() -> void:
	if not multiplayer.is_server():
		return

	var sender_peer_id := multiplayer.get_remote_sender_id()
	_server_try_pickup(sender_peer_id)


func _server_try_pickup(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	if _was_picked_up:
		return

	if not can_be_picked_up:
		return

	if item_data == null:
		return

	var player := _find_player(peer_id)

	if player == null:
		push_warning(
			"Spieler mit Peer-ID %s wurde nicht gefunden."
			% peer_id
		)
		return

	var distance := global_position.distance_to(player.global_position)

	if distance > pickup_distance:
		print(
			"Pickup von %s abgelehnt: Entfernung %.2f Meter."
			% [peer_id, distance]
		)
		return

	if not player.has_method("server_receive_item"):
		push_error("Player besitzt keine server_receive_item()-Methode.")
		return

	_was_picked_up = true

	# Zunächst Inventar serverseitig ändern.
	var accepted: bool = player.server_receive_item(item_data)

	if not accepted:
		_was_picked_up = false
		return

	# Danach bei allen Peers entfernen.
	_confirm_pickup.rpc()


func _find_player(peer_id: int) -> Node3D:
	var current_scene := get_tree().current_scene

	if current_scene == null:
		return null

	var players := current_scene.get_node_or_null("Players")

	if players == null:
		return null

	return players.get_node_or_null(str(peer_id)) as Node3D


@rpc("authority", "call_local", "reliable")
func _confirm_pickup() -> void:
	can_be_picked_up = false
	_was_picked_up = true

	set_deferred("monitoring", false)
	set_deferred("monitorable", false)

	for child in get_children():
		if child is CollisionShape3D:
			child.set_deferred("disabled", true)

	if model_container:
		model_container.visible = false

	if pickup_audio != null and pickup_audio.stream != null:
		pickup_audio.play()
		await pickup_audio.finished

	queue_free()
