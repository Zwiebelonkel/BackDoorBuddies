class_name ProceduralLevelGenerator
extends Node3D


@export_group("Rooms")
@export var start_room_scene: PackedScene
@export var room_scenes: Array[PackedScene] = []

@export_group("Generation")
@export_range(1, 100, 1)
var maximum_rooms: int = 15

@export var generation_seed: int = 12345

@export_range(0.0, 0.25, 0.001)
var bounds_shrink: float = 0.03

@onready var rooms_root: Node3D = $GeneratedRooms
@onready var items_root: Node3D = $SpawnedItems

var rng := RandomNumberGenerator.new()
var generated_rooms: Array[ProceduralRoom] = []
var generated_bounds: Array[AABB] = []
var open_sockets: Array[RoomSocket] = []
var active_network_seed: int = 0
var _generation_running := false


func start_network_generation(seed_override: int = 0) -> void:
	if not multiplayer.is_server():
		return

	active_network_seed = seed_override

	if active_network_seed == 0:
		active_network_seed = int(Time.get_unix_time_from_system())

	generate_network_level.rpc(active_network_seed)


func sync_level_to_peer(peer_id: int) -> void:
	if not multiplayer.is_server() or active_network_seed == 0:
		return

	generate_network_level.rpc_id(peer_id, active_network_seed)


@rpc("authority", "call_local", "reliable")
func generate_network_level(seed_value: int) -> void:
	active_network_seed = seed_value
	await generate_level(seed_value, multiplayer.is_server())


func generate_level(
	seed_value: int,
	should_spawn_items: bool = true
) -> void:
	if _generation_running:
		push_warning("Level generation is already running.")
		return

	if start_room_scene == null:
		push_error("No Start Room Scene configured.")
		return

	if room_scenes.is_empty():
		push_error("No Room Scenes configured.")
		return

	_generation_running = true
	_clear_generated_nodes()
	rng.seed = seed_value

	var start_instance := start_room_scene.instantiate()
	var first_room := start_instance as ProceduralRoom

	if first_room == null:
		start_instance.free()
		push_error("The start room requires ProceduralRoom on its root.")
		_generation_running = false
		return

	first_room.name = "Room_000"
	first_room.generation_depth = 0
	first_room.generation_index = 0
	rooms_root.add_child(first_room)

	generated_rooms.append(first_room)
	generated_bounds.append(first_room.get_world_aabb(bounds_shrink))
	open_sockets.append_array(first_room.get_free_sockets())

	while generated_rooms.size() < maximum_rooms and not open_sockets.is_empty():
		var socket_index := rng.randi_range(0, open_sockets.size() - 1)
		var target_socket := open_sockets[socket_index]
		open_sockets.remove_at(socket_index)

		if not is_instance_valid(target_socket) or target_socket.occupied:
			continue

		if not _try_attach_room(target_socket):
			target_socket.close_socket()

	_close_remaining_sockets()
	await get_tree().process_frame

	if should_spawn_items:
		await get_tree().physics_frame

		for room_index in range(generated_rooms.size()):
			var room := generated_rooms[room_index]
			var room_seed := seed_value + (room_index + 1) * 1_000_003
			room.spawn_random_items(room_seed, items_root)

	_generation_running = false
	print("Generation complete. Rooms: %d | Seed: %d" % [generated_rooms.size(), seed_value])


func _clear_generated_nodes() -> void:
	generated_rooms.clear()
	generated_bounds.clear()
	open_sockets.clear()

	for root in [rooms_root, items_root]:
		for child in root.get_children():
			root.remove_child(child)
			child.queue_free()


func _try_attach_room(target_socket: RoomSocket) -> bool:
	var target_room := target_socket.get_room()

	if target_room == null:
		return false

	var next_depth := target_room.generation_depth + 1
	var candidates: Array[PackedScene] = room_scenes.duplicate()
	_shuffle_with_generator(candidates)
	var attempt_number := 0

	for packed_scene in candidates:
		if packed_scene == null:
			continue

		var candidate_instance: Node = packed_scene.instantiate()
		var candidate := candidate_instance as ProceduralRoom

		if candidate == null:
			candidate_instance.free()
			continue

		if (
			next_depth < candidate.minimum_generation_depth
			or next_depth > candidate.maximum_generation_depth
		):
			candidate.free()
			continue

		candidate.name = "Candidate_%d_%d" % [generated_rooms.size(), attempt_number]
		candidate.generation_depth = next_depth
		candidate.generation_index = generated_rooms.size()
		rooms_root.add_child(candidate)

		var entrances := candidate.get_free_sockets()
		_shuffle_with_generator(entrances)

		for entrance in entrances:
			if not target_socket.is_compatible_with(entrance):
				continue

			_align_room_to_socket(candidate, entrance, target_socket)
			var candidate_bounds := candidate.get_world_aabb(bounds_shrink)

			if _bounds_overlap_existing(candidate_bounds):
				continue

			target_socket.occupied = true
			entrance.occupied = true
			candidate.name = "Room_%03d" % generated_rooms.size()
			generated_rooms.append(candidate)
			generated_bounds.append(candidate_bounds)

			for new_socket in candidate.get_free_sockets():
				open_sockets.append(new_socket)

			return true

		rooms_root.remove_child(candidate)
		candidate.queue_free()
		attempt_number += 1

	return false


func _align_room_to_socket(
	room: ProceduralRoom,
	room_socket: RoomSocket,
	target_socket: RoomSocket
) -> void:
	var socket_inside_room := (
		room.global_transform.affine_inverse()
		* room_socket.global_transform
	)
	var flip_transform := Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	var desired_socket_transform := target_socket.global_transform * flip_transform

	room.global_transform = desired_socket_transform * socket_inside_room.affine_inverse()


func _bounds_overlap_existing(candidate_bounds: AABB) -> bool:
	for existing_bounds in generated_bounds:
		if candidate_bounds.intersects(existing_bounds):
			return true

	return false


func _close_remaining_sockets() -> void:
	for socket in open_sockets:
		if is_instance_valid(socket) and not socket.occupied:
			socket.close_socket()

	open_sockets.clear()


func _shuffle_with_generator(values: Array) -> void:
	for index in range(values.size() - 1, 0, -1):
		var random_index := rng.randi_range(0, index)
		var temporary = values[index]

		values[index] = values[random_index]
		values[random_index] = temporary
