extends Node


const TEST_SEED := 731_993

@onready var generator: ProceduralLevelGenerator = $ProceduralLevelGenerator


func _ready() -> void:
	var exit_code := await _run_test()

	generator.call("_clear_generated_nodes")
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(exit_code)


func _run_test() -> int:
	await generator.generate_level(TEST_SEED, false)

	var room_limit_error := _validate_small_room_limits()

	if not room_limit_error.is_empty():
		return _fail(room_limit_error)

	var neon_error := _validate_generated_neon_bulbs()

	if not neon_error.is_empty():
		return _fail(neon_error)

	var warehouse_error := _validate_generated_warehouse()

	if not warehouse_error.is_empty():
		return _fail(warehouse_error)

	var neon_signature := _create_neon_signature()
	await generator.generate_level(TEST_SEED, false)

	if neon_signature != _create_neon_signature():
		return _fail("The same seed changed the ceiling neon layout.")

	await get_tree().physics_frame
	var loot_error := _validate_warehouse_loot()

	if not loot_error.is_empty():
		return _fail(loot_error)

	print(
		"WAREHOUSE_GENERATION_SMOKE_TEST_OK rooms=%d"
		% generator.generated_rooms.size()
	)
	return 0


func _validate_small_room_limits() -> String:
	var found_rooms := {
		&"bathroom": false,
		&"bedroom": false,
		&"kitchen": false,
	}

	for room in generator.generated_rooms:
		if room.room_id == &"bathroom":
			found_rooms[&"bathroom"] = true

			if room.get_effective_maximum_items() > 1:
				return "Bathroom loot limit exceeds 1."

		if room.room_id in [&"bedroom", &"kitchen"]:
			found_rooms[room.room_id] = true

			if room.get_effective_maximum_items() > 2:
				return "%s loot limit exceeds 2." % room.room_id

	for room_id in found_rooms:
		if not found_rooms[room_id]:
			return "Test seed did not generate room type %s." % room_id

	return ""


func _validate_generated_neon_bulbs() -> String:
	if generator.generated_neon_bulbs.size() < generator.generated_rooms.size():
		return "Not every generated room received a ceiling neon bulb."

	for room in generator.generated_rooms:
		var lights_root := room.get_node_or_null("CeilingNeonBulbs") as Node3D

		if lights_root == null:
			return "Room %s has no ceiling neon root." % room.room_id

		var light_count := lights_root.get_child_count()

		if (
			light_count < 1
			or light_count > generator.maximum_neon_bulbs_per_room
		):
			return "Room %s generated %d neon bulbs." % [
				room.room_id,
				light_count,
			]

		var bounds_box := room.bounds_shape.shape as BoxShape3D
		var half_size := bounds_box.size * 0.5
		var floor_area := bounds_box.size.x * bounds_box.size.z

		if floor_area <= ProceduralRoom.SMALL_ROOM_FLOOR_AREA and light_count != 1:
			return "Small room %s generated more than one NeonBulb." % room.room_id

		for child in lights_root.get_children():
			var bulb := child as Node3D

			if bulb == null or not bulb.is_in_group("procedural_neon_bulb"):
				return "A generated ceiling light is not a NeonBulb instance."

			if bulb.get_node_or_null("Light") as SpotLight3D == null:
				return "A NeonBulb has no downward SpotLight3D."

			var flicker_timer := bulb.get_node_or_null("FlickerTimer") as Timer

			if (
				not bool(bulb.get("flicker_enabled"))
				or flicker_timer == null
				or flicker_timer.is_stopped()
			):
				return "A NeonBulb does not have active occasional flicker."

			var bounds_local_position := (
				room.bounds_shape.transform.affine_inverse()
				* bulb.transform.origin
			)

			if absf(bounds_local_position.y - (half_size.y - 0.07)) > 0.01:
				return "A NeonBulb is not mounted against the ceiling."

			if (
				absf(bounds_local_position.x) > half_size.x
				or absf(bounds_local_position.z) > half_size.z
			):
				return "A NeonBulb was placed outside its room bounds."

	return ""


func _create_neon_signature() -> String:
	var parts := PackedStringArray()

	for room in generator.generated_rooms:
		var lights_root := room.get_node_or_null("CeilingNeonBulbs") as Node3D

		if lights_root == null:
			continue

		for child in lights_root.get_children():
			var bulb := child as Node3D

			if bulb == null:
				continue

			parts.append(
				"%d|%.4f|%.4f|%.4f|%.4f" % [
					room.generation_index,
					bulb.position.x,
					bulb.position.y,
					bulb.position.z,
					bulb.rotation.y,
				]
			)

	return ";".join(parts)


func _validate_generated_warehouse() -> String:
	var warehouses: Array[ProceduralRoom] = []

	for room in generator.generated_rooms:
		if room.room_type == &"rare":
			warehouses.append(room)

	if warehouses.size() != 1:
		return "Forced rare generation created %d warehouses instead of 1." % (
			warehouses.size()
		)

	var warehouse := warehouses[0]
	var bounds_box := warehouse.bounds_shape.shape as BoxShape3D

	if warehouse.room_id != &"warehouse":
		return "The rare room is not identified as warehouse."

	if bounds_box == null or bounds_box.size.x < 11.0 or bounds_box.size.z < 8.0:
		return "The warehouse footprint is too small."

	var socket_count := 0

	for child in warehouse.sockets_root.get_children():
		if child is RoomSocket:
			socket_count += 1

	if socket_count != 4:
		return "The warehouse does not expose four door sockets."

	if warehouse.item_spawn_points.get_child_count() < 10:
		return "The warehouse needs at least ten distributed loot positions."

	if warehouse.get_effective_maximum_items() != warehouse.maximum_items:
		return "The small-room loot cap incorrectly affects the warehouse."

	return ""


func _validate_warehouse_loot() -> String:
	for room in generator.generated_rooms:
		if room.room_id != &"warehouse":
			continue

		var spawned_items := room.spawn_random_items(
			TEST_SEED + 17,
			generator.items_root
		)

		if spawned_items.size() < 3 or spawned_items.size() > 6:
			return "Warehouse loot spawning produced %d items." % (
				spawned_items.size()
			)

		return ""

	return "The generated warehouse disappeared before loot validation."


func _fail(message: String) -> int:
	push_error(message)
	return 1
