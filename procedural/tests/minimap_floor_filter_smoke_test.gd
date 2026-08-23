extends Node


const TEST_SEED := 9_461_027
const FLOOR_COUNT := 3
const STAIR_ROOM_PATH := "res://procedural/rooms/stairwell.tscn"
const PICKUP_SCENE := preload("res://procedural/items/weed_pickup.tscn")
const CAMERA_SCENE := preload(
	"res://procedural/cameras/surveillance_camera.tscn"
)

@onready var generator: ProceduralLevelGenerator = $ProceduralLevelGenerator
@onready var minimap: Control = $Minimap/SubViewport/Map
@onready var players_root: Node3D = $Players
@onready var cameras_root: Node3D = $TestCameras

var _test_pickups: Array[PickupItem] = []
var _test_cameras: Array[SurveillanceCamera] = []
var _test_players: Array[Node3D] = []


func _ready() -> void:
	call_deferred("_run_and_exit")


func _run_and_exit() -> void:
	var exit_code := await _run_test()
	_cleanup_test_entities()

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
		return _fail("The minimap test cannot load the stairwell scene.")

	generator.set(&"stair_room_scene", stair_room_scene)
	generator.set(&"minimum_floors", FLOOR_COUNT)
	generator.set(&"maximum_floors", FLOOR_COUNT)
	generator.maximum_rooms = 36
	generator.minimum_large_rooms = 0
	generator.ceiling_neon_enabled = false
	generator.rare_room_chance = 0.0
	generator.minimum_surveillance_cameras = 0
	generator.maximum_surveillance_cameras = 0

	await generator.generate_level(TEST_SEED, false)

	if int(generator.call("get_generated_floor_count")) != FLOOR_COUNT:
		return _fail("The minimap fixture did not generate three floors.")

	if minimap.has_method("_resolve_world_nodes"):
		minimap.call("_resolve_world_nodes")

	if minimap.has_method("_refresh_floor_layout"):
		minimap.call("_refresh_floor_layout")

	await get_tree().process_frame

	var boundary_error := _validate_stair_floor_boundaries()

	if not boundary_error.is_empty():
		return _fail(boundary_error)

	var entrance_error := await _validate_entrance_marker()

	if not entrance_error.is_empty():
		return _fail(entrance_error)

	var fixture_error := _create_floor_entities()

	if not fixture_error.is_empty():
		return _fail(fixture_error)

	await get_tree().process_frame

	if (
		minimap.has_method("get_total_scanned_item_count")
		and int(minimap.call("get_total_scanned_item_count")) != FLOOR_COUNT
	):
		return _fail("Minimap fixture item total is incorrect.")

	if (
		minimap.has_method("get_total_scanned_camera_count")
		and int(minimap.call("get_total_scanned_camera_count")) != FLOOR_COUNT
	):
		return _fail("Minimap fixture camera total is incorrect.")

	if (
		minimap.has_method("get_available_floor_count")
		and int(minimap.call("get_available_floor_count")) != FLOOR_COUNT
	):
		return _fail("Minimap available floor count is incorrect.")

	for floor_index in range(FLOOR_COUNT):
		var floor_error := await _validate_selected_floor(floor_index)

		if not floor_error.is_empty():
			return _fail(floor_error)

	var navigation_error := await _validate_floor_navigation()

	if not navigation_error.is_empty():
		return _fail(navigation_error)

	print("MINIMAP_FLOOR_FILTER_SMOKE_TEST_OK floors=%d" % FLOOR_COUNT)
	return 0


func _validate_stair_floor_boundaries() -> String:
	for room in generator.generated_rooms:
		if room.floor_span <= 1:
			continue

		var lower_floor := room.floor_index
		var upper_floor := lower_floor + 1
		var lower_point := Vector3(
			room.global_position.x,
			float(generator.call("get_floor_world_y", lower_floor)),
			room.global_position.z
		)
		var upper_point := Vector3(
			room.global_position.x,
			float(generator.call("get_floor_world_y", upper_floor)),
			room.global_position.z
		)

		if int(minimap.call("_get_floor_index_for_point", lower_point)) != lower_floor:
			return "A stairwell lower landing maps to the wrong floor."

		if int(minimap.call("_get_floor_index_for_point", upper_point)) != upper_floor:
			return "A stairwell upper landing maps to the wrong floor."

	return ""


func _validate_entrance_marker() -> String:
	var start_room: ProceduralRoom = null

	for room in generator.generated_rooms:
		if room.room_id == &"start_room":
			start_room = room
			break

	if start_room == null or start_room.floor_index != 0:
		return "The generated StartRoom is missing from floor zero."

	var entrance := start_room.get_node_or_null("ExitDoor") as ExitDoor

	if entrance == null:
		return "The generated StartRoom has no real ExitDoor."

	if not entrance.is_in_group(&"procedural_scan_entrance"):
		return "The real StartRoom ExitDoor is not marked for the room scan."

	if entrance.global_position.is_equal_approx(start_room.global_position):
		return "The entrance marker collapsed to the StartRoom origin."

	if int(minimap.call(
		"_get_floor_index_for_point",
		entrance.global_position
	)) != 0:
		return "The real StartRoom ExitDoor does not map to floor zero."

	for floor_index in range(FLOOR_COUNT):
		minimap.call("set_selected_floor", floor_index)
		await get_tree().process_frame

		var expected_count := 1 if floor_index == 0 else 0
		var actual_count := int(minimap.call(
			"get_scanned_entrance_count"
		))
		var positions_value: Variant = minimap.call(
			"get_scanned_entrance_world_positions"
		)

		if not positions_value is Array:
			return "Minimap entrance positions are not exposed as an array."

		var positions := positions_value as Array

		if actual_count != expected_count or positions.size() != expected_count:
			return "Floor %d exposed %d entrance markers instead of %d." % [
				floor_index,
				actual_count,
				expected_count,
			]

		if (
			floor_index == 0
			and (
				not positions[0] is Vector3
				or not (positions[0] as Vector3).is_equal_approx(
					entrance.global_position
				)
			)
		):
			return "The entrance marker does not use the real ExitDoor position."

	minimap.call("set_selected_floor", 0)
	await get_tree().process_frame

	if (
		int(minimap.call("get_scanned_entrance_count")) != 1
		or (minimap.call(
			"get_scanned_entrance_world_positions"
		) as Array).size() != 1
	):
		return "Returning to floor zero did not restore the entrance marker."

	return ""


func _validate_required_api() -> String:
	for generator_property in [
		&"stair_room_scene",
		&"minimum_floors",
		&"maximum_floors",
	]:
		if not _has_property(generator, generator_property):
			return "Generator property '%s' is missing." % generator_property

	for generator_method in [&"get_generated_floor_count", &"get_rooms_on_floor"]:
		if not generator.has_method(generator_method):
			return "Generator method '%s' is missing." % generator_method

	var required_minimap_methods: Array[StringName] = [
		&"set_selected_floor",
		&"select_next_floor",
		&"select_previous_floor",
		&"get_selected_floor",
		&"get_scanned_room_count",
		&"get_scanned_item_count",
		&"get_scanned_camera_count",
		&"get_scanned_player_count",
		&"get_scanned_entrance_count",
		&"get_scanned_entrance_world_positions",
	]

	for method_name in required_minimap_methods:
		if not minimap.has_method(method_name):
			return "Minimap method '%s' is missing." % method_name

	return ""


func _create_floor_entities() -> String:
	for floor_index in range(FLOOR_COUNT):
		var room := _find_single_floor_room(floor_index)

		if room == null:
			return "Floor %d has no single-floor room for map fixtures." % floor_index

		var room_bounds := room.get_world_aabb(0.0)
		var room_center := room_bounds.get_center()
		var pickup_position := Vector3(
			room_center.x,
			room.global_position.y + 0.03,
			room_center.z
		)
		var player_position := Vector3(
			room_center.x - 0.2,
			room.global_position.y,
			room_center.z - 0.2
		)

		var pickup := PICKUP_SCENE.instantiate() as PickupItem

		if pickup == null:
			return "Could not instantiate a minimap pickup fixture."

		pickup.name = "Floor%dPickup" % floor_index
		generator.items_root.add_child(pickup)
		pickup.global_position = pickup_position
		_test_pickups.append(pickup)

		var camera := CAMERA_SCENE.instantiate() as SurveillanceCamera

		if camera == null:
			return "Could not instantiate a minimap camera fixture."

		camera.name = "Floor%dCamera" % floor_index
		cameras_root.add_child(camera)
		camera.global_position = Vector3(
			room_center.x + 0.2,
			room.global_position.y + 0.5,
			room_center.z + 0.2
		)
		camera.configure(floor_index + 1, room.generation_index, room.room_id)
		generator.generated_surveillance_cameras.append(camera)
		_test_cameras.append(camera)

		var player := Node3D.new()
		player.name = str(100 + floor_index)
		players_root.add_child(player)
		player.global_position = player_position
		_test_players.append(player)

	return ""


func _validate_selected_floor(floor_index: int) -> String:
	minimap.call("set_selected_floor", floor_index)
	await get_tree().process_frame

	if int(minimap.call("get_selected_floor")) != floor_index:
		return "Minimap did not select floor %d." % floor_index

	var expected_room_count := _get_rooms_on_floor(floor_index).size()
	var actual_counts := {
		"rooms": int(minimap.call("get_scanned_room_count")),
		"items": int(minimap.call("get_scanned_item_count")),
		"cameras": int(minimap.call("get_scanned_camera_count")),
		"players": int(minimap.call("get_scanned_player_count")),
	}

	if actual_counts["rooms"] != expected_room_count:
		return "Floor %d room scan returned %d instead of %d." % [
			floor_index,
			actual_counts["rooms"],
			expected_room_count,
		]

	for category in ["items", "cameras", "players"]:
		if actual_counts[category] != 1:
			return "Floor %d %s scan leaked entities from another floor." % [
				floor_index,
				category,
			]

	return ""


func _validate_floor_navigation() -> String:
	minimap.call("set_selected_floor", 0)
	minimap.call("select_next_floor")
	await get_tree().process_frame

	if int(minimap.call("get_selected_floor")) != 1:
		return "Minimap next-floor navigation skipped floor one."

	minimap.call("select_next_floor")
	await get_tree().process_frame

	if int(minimap.call("get_selected_floor")) != 2:
		return "Minimap next-floor navigation did not reach floor two."

	minimap.call("select_next_floor")
	await get_tree().process_frame

	if int(minimap.call("get_selected_floor")) != 0:
		return "Minimap next-floor navigation did not wrap at the floor cap."

	minimap.call("select_previous_floor")
	await get_tree().process_frame

	if int(minimap.call("get_selected_floor")) != 2:
		return "Minimap previous-floor navigation did not wrap to the top floor."

	minimap.call("select_previous_floor")
	await get_tree().process_frame
	minimap.call("select_previous_floor")
	await get_tree().process_frame

	if int(minimap.call("get_selected_floor")) != 0:
		return "Minimap previous-floor navigation skipped a floor."

	return ""


func _find_single_floor_room(floor_index: int) -> ProceduralRoom:
	for room in _get_rooms_on_floor(floor_index):
		if (
			room is ProceduralRoom
			and int(room.get(&"floor_index")) == floor_index
			and int(room.get(&"floor_span")) == 1
		):
			return room as ProceduralRoom

	return null


func _get_rooms_on_floor(floor_index: int) -> Array:
	var result: Variant = generator.call("get_rooms_on_floor", floor_index)
	return result as Array if result is Array else []


func _cleanup_test_entities() -> void:
	for camera in _test_cameras:
		generator.generated_surveillance_cameras.erase(camera)

	for node_list in [_test_pickups, _test_cameras, _test_players]:
		for node in node_list:
			var test_node := node as Node

			if not is_instance_valid(test_node):
				continue

			var parent: Node = test_node.get_parent()

			if parent != null:
				parent.remove_child(test_node)

			test_node.free()

	_test_pickups.clear()
	_test_cameras.clear()
	_test_players.clear()


func _has_property(object: Object, property_name: StringName) -> bool:
	for property_data in object.get_property_list():
		if StringName(property_data.get("name", "")) == property_name:
			return true

	return false


func _fail(message: String) -> int:
	push_error("MINIMAP_FLOOR_FILTER_SMOKE_TEST_FAILED: " + message)
	return 1
