class_name ExitDoor
extends StaticBody3D


@export var interaction_text := "Zurück in die Halle"
@export var destination_group: StringName = &"hall_spawn_point"
@export_range(1.0, 10.0, 0.1) var interaction_distance := 3.0


func get_interaction_text() -> String:
	return interaction_text


func request_interaction(player: Node3D) -> void:
	if player == null or not player.is_multiplayer_authority():
		return

	if multiplayer.is_server():
		_server_try_use(multiplayer.get_unique_id())
	else:
		_request_use_server.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_use_server() -> void:
	if not multiplayer.is_server():
		return

	_server_try_use(multiplayer.get_remote_sender_id())


func _server_try_use(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	var player := _find_player(peer_id)
	var destination := _find_destination()

	if player == null or destination == null:
		return

	if player.global_position.distance_to(global_position) > interaction_distance:
		return

	var target_position := destination.global_position
	var target_rotation := destination.global_rotation

	_apply_teleport(player, target_position, target_rotation)

	if peer_id != multiplayer.get_unique_id():
		_teleport_peer.rpc_id(peer_id, target_position, target_rotation)


@rpc("authority", "call_remote", "reliable")
func _teleport_peer(target_position: Vector3, target_rotation: Vector3) -> void:
	var player := _find_player(multiplayer.get_unique_id())

	if player != null:
		_apply_teleport(player, target_position, target_rotation)


func _apply_teleport(
	player: Node3D,
	target_position: Vector3,
	target_rotation: Vector3
) -> void:
	player.global_position = target_position
	player.global_rotation = target_rotation

	if player is CharacterBody3D:
		(player as CharacterBody3D).velocity = Vector3.ZERO


func _find_player(peer_id: int) -> Node3D:
	var current_scene := get_tree().current_scene

	if current_scene == null:
		return null

	var players := current_scene.get_node_or_null("Players")

	if players == null:
		return null

	return players.get_node_or_null(str(peer_id)) as Node3D


func _find_destination() -> Marker3D:
	return get_tree().get_first_node_in_group(destination_group) as Marker3D
