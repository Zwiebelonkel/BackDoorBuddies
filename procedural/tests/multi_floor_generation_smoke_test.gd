extends Node


const TEST_SEED := 8_817_311
const REQUIRED_FLOOR_COUNT := 3
const STAIR_ROOM_PATH := "res://procedural/rooms/stairwell.tscn"
const POSITION_TOLERANCE := 0.08
const VISUAL_SEAM_TOLERANCE := 0.015

@onready var generator: ProceduralLevelGenerator = $ProceduralLevelGenerator


func _ready() -> void:
	call_deferred("_run_and_exit")


func _run_and_exit() -> void:
	var exit_code := await _run_test()

	if generator.has_method("_clear_generated_nodes"):
		generator.call("_clear_generated_nodes")

	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(exit_code)


func _run_test() -> int:
	var api_error := _validate_required_api()

	if not api_error.is_empty():
		return _fail(api_error)

	var stair_room_scene := load(STAIR_ROOM_PATH) as PackedScene

	if stair_room_scene == null:
		return _fail("The procedural stairwell scene is missing.")

	generator.set(&"stair_room_scene", stair_room_scene)
	generator.set(&"minimum_floors", REQUIRED_FLOOR_COUNT)
	generator.set(&"maximum_floors", REQUIRED_FLOOR_COUNT)
	generator.maximum_rooms = 36
	generator.minimum_large_rooms = 0
	generator.ceiling_neon_enabled = false
	generator.rare_room_chance = 0.0
	generator.minimum_surveillance_cameras = 0
	generator.maximum_surveillance_cameras = 0

	await generator.generate_level(TEST_SEED, false)

	var generation_error := _validate_three_floor_generation()

	if not generation_error.is_empty():
		return _fail(generation_error)

	var movement_error := await _validate_generated_stair_movement()

	if not movement_error.is_empty():
		return _fail(movement_error)

	var first_signature := _create_floor_signature()
	await generator.generate_level(TEST_SEED, false)

	if first_signature != _create_floor_signature():
		return _fail("The same seed changed the multi-floor layout.")

	generator.set(&"minimum_floors", 1)
	generator.set(&"maximum_floors", 1)
	await generator.generate_level(TEST_SEED + 1, false)

	var single_floor_error := _validate_single_floor_cap()

	if not single_floor_error.is_empty():
		return _fail(single_floor_error)

	print(
		"MULTI_FLOOR_GENERATION_SMOKE_TEST_OK floors=%d single_floor_cap=OK"
		% REQUIRED_FLOOR_COUNT
	)
	return 0


func _validate_required_api() -> String:
	var required_generator_properties: Array[StringName] = [
		&"stair_room_scene",
		&"minimum_floors",
		&"maximum_floors",
		&"floor_height",
		&"target_floor_count",
		&"generated_floor_count",
	]

	for property_name in required_generator_properties:
		if not _has_property(generator, property_name):
			return "Generator property '%s' is missing." % property_name

	for method_name in [&"get_generated_floor_count", &"get_rooms_on_floor"]:
		if not generator.has_method(method_name):
			return "Generator method '%s' is missing." % method_name

	var room_scene := generator.start_room_scene.instantiate()
	var room := room_scene as ProceduralRoom

	if room == null:
		room_scene.free()
		return "The configured start room is not a ProceduralRoom."

	var room_properties_ok := (
		_has_property(room, &"floor_index")
		and _has_property(room, &"floor_span")
	)
	var room_methods_ok := (
		room.has_method("get_highest_floor_index")
		and room.has_method("occupies_floor")
	)
	room.free()

	if not room_properties_ok or not room_methods_ok:
		return "ProceduralRoom floor span API is incomplete."

	var socket := RoomSocket.new()
	var socket_api_ok := _has_property(socket, &"floor_offset")
	socket.free()

	if not socket_api_ok:
		return "RoomSocket.floor_offset is missing."

	return ""


func _validate_three_floor_generation() -> String:
	if generator.generated_rooms.is_empty():
		return "Three-floor generation produced no rooms."

	if int(generator.get(&"target_floor_count")) != REQUIRED_FLOOR_COUNT:
		return "The deterministic target floor count is not three."

	if _get_generated_floor_count() != REQUIRED_FLOOR_COUNT:
		return "The generator did not create exactly three reachable floors."

	if int(generator.get(&"generated_floor_count")) != REQUIRED_FLOOR_COUNT:
		return "generated_floor_count disagrees with its public helper."

	var floor_height := float(generator.get(&"floor_height"))

	if floor_height <= 0.0:
		return "Generator floor_height must be positive."

	var floor_zero_y := _get_floor_zero_y()

	if not is_finite(floor_zero_y):
		return "Floor zero has no generated room."

	for room in generator.generated_rooms:
		var room_error := _validate_room_floor_data(
			room,
			floor_zero_y,
			floor_height,
			REQUIRED_FLOOR_COUNT
		)

		if not room_error.is_empty():
			return room_error

	for floor_index in range(REQUIRED_FLOOR_COUNT):
		var floor_error := _validate_floor_query(floor_index)

		if not floor_error.is_empty():
			return floor_error

	if not _get_rooms_on_floor(-1).is_empty():
		return "get_rooms_on_floor accepted a negative floor index."

	if not _get_rooms_on_floor(REQUIRED_FLOOR_COUNT).is_empty():
		return "get_rooms_on_floor returned rooms above the floor cap."

	return _validate_stair_connections(REQUIRED_FLOOR_COUNT, floor_height)


func _validate_room_floor_data(
	room: ProceduralRoom,
	floor_zero_y: float,
	floor_height: float,
	floor_count: int
) -> String:
	if not _has_property(room, &"floor_index") or not _has_property(
		room,
		&"floor_span"
	):
		return "A generated room has no floor metadata."

	var floor_index := int(room.get(&"floor_index"))
	var floor_span := int(room.get(&"floor_span"))
	var highest_floor := int(room.call("get_highest_floor_index"))

	if floor_index < 0 or floor_index >= floor_count:
		return "Room %s has invalid floor_index %d." % [room.name, floor_index]

	if floor_span < 1 or highest_floor != floor_index + floor_span - 1:
		return "Room %s has inconsistent floor span data." % room.name

	if highest_floor >= floor_count:
		return "Room %s extends above the configured floor cap." % room.name

	var expected_y := floor_zero_y + float(floor_index) * floor_height

	if absf(room.global_position.y - expected_y) > POSITION_TOLERANCE:
		return "Room %s is vertically misaligned on floor %d." % [
			room.name,
			floor_index,
		]

	for occupied_floor in range(floor_count):
		var expected_occupancy := (
			occupied_floor >= floor_index and occupied_floor <= highest_floor
		)

		if bool(room.call("occupies_floor", occupied_floor)) != expected_occupancy:
			return "Room %s reports incorrect floor occupancy." % room.name

	return ""


func _validate_floor_query(floor_index: int) -> String:
	var queried_rooms := _get_rooms_on_floor(floor_index)
	var expected_rooms: Array[ProceduralRoom] = []

	for room in generator.generated_rooms:
		if bool(room.call("occupies_floor", floor_index)):
			expected_rooms.append(room)

	if queried_rooms.size() != expected_rooms.size():
		return "Floor %d room query returned %d rooms instead of %d." % [
			floor_index,
			queried_rooms.size(),
			expected_rooms.size(),
		]

	for room in queried_rooms:
		if (
			not is_instance_valid(room)
			or room not in generator.generated_rooms
			or not bool(room.call("occupies_floor", floor_index))
		):
			return "Floor %d query contains an unrelated room." % floor_index

	return ""


func _validate_stair_connections(floor_count: int, floor_height: float) -> String:
	var stair_rooms: Array[ProceduralRoom] = []

	for room in generator.generated_rooms:
		if int(room.get(&"floor_span")) > 1:
			stair_rooms.append(room)

	if stair_rooms.size() < floor_count - 1:
		return "Not every adjacent floor pair received a stair transition."

	for lower_floor in range(floor_count - 1):
		var has_connection := false

		for stair_room in stair_rooms:
			if (
				bool(stair_room.call("occupies_floor", lower_floor))
				and bool(stair_room.call("occupies_floor", lower_floor + 1))
			):
				has_connection = true
				break

		if not has_connection:
			return "Floors %d and %d have no stair connection." % [
				lower_floor,
				lower_floor + 1,
			]

	for stair_room in stair_rooms:
		var stair_error := _validate_stair_room(stair_room, floor_height)

		if not stair_error.is_empty():
			return stair_error

	return ""


func _validate_stair_room(
	stair_room: ProceduralRoom,
	floor_height: float
) -> String:
	if int(stair_room.get(&"floor_span")) != 2:
		return "Stair room %s must span exactly two floors." % stair_room.name

	var sockets: Array[RoomSocket] = []
	_collect_room_sockets(stair_room, sockets)
	var lower_socket_heights: Array[float] = []
	var upper_socket_heights: Array[float] = []

	for socket in sockets:
		if not _has_property(socket, &"floor_offset"):
			return "A stairwell socket has no floor_offset."

		var floor_offset := int(socket.get(&"floor_offset"))

		match floor_offset:
			0:
				lower_socket_heights.append(socket.global_position.y)
			1:
				upper_socket_heights.append(socket.global_position.y)
			_:
				return "A stairwell socket points outside its two-floor span."

	if lower_socket_heights.is_empty() or upper_socket_heights.is_empty():
		return "Stair room %s lacks lower or upper floor sockets." % stair_room.name

	var lower_y := _average(lower_socket_heights)
	var upper_y := _average(upper_socket_heights)

	if absf((upper_y - lower_y) - floor_height) > 0.2:
		return "Stair room %s sockets do not match floor_height." % stair_room.name

	var staircase := _find_authored_staircase(stair_room)

	if staircase == null:
		return "Stair room %s has no physical staircase instance." % stair_room.name

	var ramp := staircase.get_node_or_null("RampCollision") as CollisionShape3D

	if ramp == null or ramp.shape == null:
		return "Stair room %s has no staircase collision ramp." % stair_room.name

	var visual_seam_error := _validate_stair_visual_landings(
		stair_room,
		staircase
	)

	if not visual_seam_error.is_empty():
		return visual_seam_error

	var bottom := staircase.get_node_or_null("Bottom") as Marker3D
	var top := staircase.get_node_or_null("Top") as Marker3D

	if (
		bottom == null
		or top == null
		or absf(
			(top.global_position.y - bottom.global_position.y) - floor_height
		) > 0.12
	):
		return "Stair room %s physical rise does not match floor_height." % (
			stair_room.name
		)

	return ""


func _validate_stair_visual_landings(
	stair_room: ProceduralRoom,
	staircase: StaticBody3D
) -> String:
	var bottom_landing := stair_room.get_node_or_null(
		"Geometry/Floor/FloorMesh"
	) as MeshInstance3D
	var top_landing := stair_room.get_node_or_null(
		"Geometry/Floor/TopLandingMesh"
	) as MeshInstance3D
	var first_step := staircase.get_node_or_null("Step01") as MeshInstance3D
	var last_step := staircase.get_node_or_null("Step12") as MeshInstance3D

	if (
		bottom_landing == null
		or top_landing == null
		or first_step == null
		or last_step == null
		or bottom_landing.mesh == null
		or top_landing.mesh == null
		or first_step.mesh == null
		or last_step.mesh == null
	):
		return "Stair room %s has incomplete visual landing geometry." % (
			stair_room.name
		)

	var bottom_bounds := _get_room_local_mesh_aabb(
		stair_room,
		bottom_landing
	)
	var top_bounds := _get_room_local_mesh_aabb(stair_room, top_landing)
	var first_step_bounds := _get_room_local_mesh_aabb(
		stair_room,
		first_step
	)
	var last_step_bounds := _get_room_local_mesh_aabb(
		stair_room,
		last_step
	)
	var bottom_z_seam := (
		first_step_bounds.position.z - bottom_bounds.end.z
	)
	var top_z_seam := top_bounds.position.z - last_step_bounds.end.z
	var bottom_y_seam := (
		first_step_bounds.position.y - bottom_bounds.end.y
	)
	var top_y_seam := top_bounds.end.y - last_step_bounds.end.y

	if (
		absf(bottom_z_seam) > VISUAL_SEAM_TOLERANCE
		or absf(bottom_y_seam) > VISUAL_SEAM_TOLERANCE
	):
		return (
			"Stair room %s has a visible bottom landing gap "
			+ "(z=%.3f, y=%.3f)."
		) % [stair_room.name, bottom_z_seam, bottom_y_seam]

	if (
		absf(top_z_seam) > VISUAL_SEAM_TOLERANCE
		or absf(top_y_seam) > VISUAL_SEAM_TOLERANCE
	):
		return (
			"Stair room %s has a visible top landing gap "
			+ "(z=%.3f, y=%.3f)."
		) % [stair_room.name, top_z_seam, top_y_seam]

	return ""


func _get_room_local_mesh_aabb(
	stair_room: ProceduralRoom,
	mesh_instance: MeshInstance3D
) -> AABB:
	var room_local_transform := (
		stair_room.global_transform.affine_inverse()
		* mesh_instance.global_transform
	)
	return room_local_transform * mesh_instance.mesh.get_aabb()


func _validate_generated_stair_movement() -> String:
	var player_scene := load(
		"res://scenes/PlayerController.tscn"
	) as PackedScene

	if player_scene == null:
		return "The FPSController scene could not be loaded for stair testing."

	var player := player_scene.instantiate() as FPSController

	if player == null:
		return "The generated stair test could not instantiate an FPSController."

	player.name = "1"
	$Players.add_child(player)
	await get_tree().process_frame
	await get_tree().physics_frame

	if player.camera != null:
		player.camera.current = false

	var tested_stair_count := 0

	for room in generator.generated_rooms:
		if int(room.get(&"floor_span")) <= 1:
			continue

		var staircase := _find_authored_staircase(room)

		if staircase == null:
			_cleanup_test_player(player)
			return "A generated stair room has no traversable staircase."

		var bottom := staircase.get_node_or_null("Bottom") as Marker3D
		var top := staircase.get_node_or_null("Top") as Marker3D

		if bottom == null or top == null:
			_cleanup_test_player(player)
			return "A generated staircase lacks Bottom or Top movement markers."

		var seam_error := _validate_stair_landing_seams(bottom, top)

		if not seam_error.is_empty():
			_cleanup_test_player(player)
			return seam_error

		var ascent_error := await _walk_stair_segment(player, bottom, top, true)

		if not ascent_error.is_empty():
			_cleanup_test_player(player)
			return ascent_error

		var descent_error := await _walk_stair_segment(player, top, bottom, false)

		if not descent_error.is_empty():
			_cleanup_test_player(player)
			return descent_error

		tested_stair_count += 1

	_cleanup_test_player(player)

	if tested_stair_count < REQUIRED_FLOOR_COUNT - 1:
		return "Too few generated stair transitions were physically tested."

	return ""


func _walk_stair_segment(
	player: FPSController,
	start: Marker3D,
	target: Marker3D,
	is_ascent: bool
) -> String:
	Input.action_release("jump")
	Input.action_release("move_forward")
	player.velocity = Vector3.ZERO
	player.global_position = start.global_position + Vector3.UP * 0.04
	var horizontal_target := Vector3(
		target.global_position.x,
		player.global_position.y,
		target.global_position.z
	)

	if player.global_position.distance_to(horizontal_target) < 0.1:
		return "A generated staircase has coincident movement markers."

	player.look_at(horizontal_target, Vector3.UP)

	for _frame in range(8):
		await get_tree().physics_frame

	Input.action_press("move_forward")
	var reached_target := false
	var longest_airborne_run := 0
	var current_airborne_run := 0
	var highest_upward_velocity := 0.0

	for _frame in range(300):
		await get_tree().physics_frame

		if not player.global_position.is_finite():
			break

		highest_upward_velocity = maxf(highest_upward_velocity, player.velocity.y)

		if player.is_on_floor():
			current_airborne_run = 0
		else:
			current_airborne_run += 1
			longest_airborne_run = maxi(
				longest_airborne_run,
				current_airborne_run
			)

		var horizontal_distance := Vector2(
			player.global_position.x - target.global_position.x,
			player.global_position.z - target.global_position.z
		).length()
		var reached_height := (
			player.global_position.y >= target.global_position.y - 0.35
			if is_ascent
			else player.global_position.y <= target.global_position.y + 0.35
		)

		if horizontal_distance <= 0.8 and reached_height:
			reached_target = true
			break

	Input.action_release("move_forward")

	for _frame in range(8):
		await get_tree().physics_frame

	if not reached_target or not player.global_position.is_finite():
		return (
			"FPSController could not walk %s a generated staircase without jumping."
			% ("up" if is_ascent else "down")
		)

	if not player.is_on_floor() or longest_airborne_run > 8:
		return "A generated staircase has an unstable landing seam."

	if is_ascent and highest_upward_velocity >= player.jump_velocity * 0.75:
		return "Generated stair ascent applied a jump-like vertical impulse."

	return ""


func _validate_stair_landing_seams(bottom: Marker3D, top: Marker3D) -> String:
	var space_state: PhysicsDirectSpaceState3D = (
		generator.get_world_3d().direct_space_state
	)

	for marker in [bottom, top]:
		var query := PhysicsRayQueryParameters3D.create(
			marker.global_position + Vector3.UP * 0.8,
			marker.global_position + Vector3.DOWN * 1.2
		)
		query.collision_mask = 1
		var hit: Dictionary = space_state.intersect_ray(query)

		if hit.is_empty():
			return "A generated staircase landing has no floor collision."

		var hit_position: Vector3 = hit.get("position", Vector3.ZERO)

		if absf(hit_position.y - marker.global_position.y) > 0.4:
			return "A generated staircase marker is not flush with its landing."

	return ""


func _cleanup_test_player(player: FPSController) -> void:
	Input.action_release("jump")
	Input.action_release("move_forward")
	var hud := player.player_hud
	$Players.remove_child(player)
	player.free()

	if is_instance_valid(hud):
		hud.queue_free()


func _validate_single_floor_cap() -> String:
	if _get_generated_floor_count() != 1:
		return "A one-floor configuration generated multiple floors."

	if int(generator.get(&"target_floor_count")) != 1:
		return "The one-floor target was not respected."

	for room in generator.generated_rooms:
		if (
			int(room.get(&"floor_index")) != 0
			or int(room.get(&"floor_span")) != 1
			or not bool(room.call("occupies_floor", 0))
		):
			return "A room escaped the one-floor generation cap."

	return ""


func _get_generated_floor_count() -> int:
	return int(generator.call("get_generated_floor_count"))


func _get_rooms_on_floor(floor_index: int) -> Array:
	var result: Variant = generator.call("get_rooms_on_floor", floor_index)
	return result as Array if result is Array else []


func _get_floor_zero_y() -> float:
	for room in generator.generated_rooms:
		if int(room.get(&"floor_index")) == 0:
			return room.global_position.y

	return NAN


func _create_floor_signature() -> String:
	var parts := PackedStringArray()

	for room in generator.generated_rooms:
		parts.append(
			"%s|%d|%d|%.3f|%.3f|%.3f|%.3f" % [
				room.room_id,
				int(room.get(&"floor_index")),
				int(room.get(&"floor_span")),
				room.global_position.x,
				room.global_position.y,
				room.global_position.z,
				room.global_rotation.y,
			]
		)

	return ";".join(parts)


func _collect_room_sockets(node: Node, result: Array[RoomSocket]) -> void:
	for child in node.get_children():
		if child is RoomSocket:
			result.append(child as RoomSocket)

		_collect_room_sockets(child, result)


func _find_authored_staircase(room: Node) -> StaticBody3D:
	if room is StaticBody3D and int(room.get_meta(&"step_count", 0)) > 0:
		return room as StaticBody3D

	for child in room.get_children():
		var staircase := _find_authored_staircase(child)

		if staircase != null:
			return staircase

	return null


func _average(values: Array[float]) -> float:
	var total := 0.0

	for value in values:
		total += value

	return total / float(values.size())


func _has_property(object: Object, property_name: StringName) -> bool:
	for property_data in object.get_property_list():
		if StringName(property_data.get("name", "")) == property_name:
			return true

	return false


func _fail(message: String) -> int:
	Input.action_release("jump")
	Input.action_release("move_forward")
	push_error("MULTI_FLOOR_GENERATION_SMOKE_TEST_FAILED: " + message)
	return 1
