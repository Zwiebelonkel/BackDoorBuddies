extends Node


const TEST_SEED := 424242

@onready var generator: ProceduralLevelGenerator = $ProceduralLevelGenerator


func _ready() -> void:
	var exit_code := await _run_test()
	get_tree().quit(exit_code)


func _run_test() -> int:
	await generator.generate_level(TEST_SEED, true)

	if generator.generated_rooms.size() < 2:
		return _fail("Generation produced fewer than two rooms.")

	if generator.items_root.get_child_count() == 0:
		return _fail("Generation produced no items.")

	if _has_overlapping_bounds():
		return _fail("Generated room bounds overlap.")

	if _has_open_socket():
		return _fail("At least one remaining socket was not capped.")

	var first_signature := _create_signature()
	var first_room_count := generator.generated_rooms.size()
	var first_item_count := generator.items_root.get_child_count()

	await generator.generate_level(TEST_SEED, true)
	var second_signature := _create_signature()

	if first_signature != second_signature:
		return _fail("The same seed produced a different level signature.")

	await generator.generate_level(TEST_SEED + 1, true)

	if first_signature == _create_signature():
		return _fail("A different seed produced the same level signature.")

	print(
		"PROCEDURAL_SMOKE_TEST_OK rooms=%d items=%d signature=%d"
		% [first_room_count, first_item_count, first_signature.hash()]
	)
	return 0


func _create_signature() -> String:
	var parts := PackedStringArray()

	for room in generator.generated_rooms:
		parts.append(
			"room:%s:%s" % [
				room.room_id,
				str(room.global_transform)
			]
		)

	for item_node in generator.items_root.get_children():
		var item := item_node as Node3D

		if item == null:
			continue

		parts.append(
			"item:%s:%s" % [
				String(item.get_meta("item_id", &"unknown")),
				str(item.global_transform)
			]
		)

	return "|".join(parts)


func _has_overlapping_bounds() -> bool:
	for first_index in range(generator.generated_bounds.size()):
		for second_index in range(first_index + 1, generator.generated_bounds.size()):
			if generator.generated_bounds[first_index].intersects(
				generator.generated_bounds[second_index]
			):
				return true

	return false


func _has_open_socket() -> bool:
	for room in generator.generated_rooms:
		for socket in room.get_free_sockets():
			if not socket.occupied:
				return true

	return false


func _fail(message: String) -> int:
	push_error("PROCEDURAL_SMOKE_TEST_FAILED: " + message)
	return 1
