extends Node


const TEST_SEED := 7_421_903
const EXPECTED_ROOM_COUNT := 42
const EXPECTED_FLOOR_COUNT := 3

@onready var host_generator: ProceduralLevelGenerator = $HostGenerator
@onready var client_generator: ProceduralLevelGenerator = $ClientGenerator


func _ready() -> void:
	call_deferred("_run_and_exit")


func _run_and_exit() -> void:
	var exit_code := await _run_test()

	for generator in [host_generator, client_generator]:
		if generator.has_method("_clear_generated_nodes"):
			generator.call("_clear_generated_nodes")

	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(exit_code)


func _run_test() -> int:
	for method_name in [
		&"get_generation_settings_snapshot",
		&"apply_generation_settings_snapshot",
		&"generate_network_level",
	]:
		if not host_generator.has_method(method_name):
			return _fail("Missing generator API: %s" % method_name)

	var host_snapshot := host_generator.get_generation_settings_snapshot()

	if host_snapshot.is_empty():
		return _fail("Host could not create a generation settings snapshot.")

	if int(host_snapshot.get("maximum_rooms", 0)) != EXPECTED_ROOM_COUNT:
		return _fail("Difficulty-adjusted room count is missing from snapshot.")

	if (
		int(host_snapshot.get("minimum_floors", 0))
		!= EXPECTED_FLOOR_COUNT
		or int(host_snapshot.get("maximum_floors", 0))
		!= EXPECTED_FLOOR_COUNT
		or str(host_snapshot.get("stair_room_scene_path", "")).is_empty()
	):
		return _fail("Floor or stair settings are missing from snapshot.")

	# Exercise the same Variant encoding used by high-level multiplayer RPCs.
	var encoded_snapshot := var_to_bytes(host_snapshot)
	var decoded_value = bytes_to_var(encoded_snapshot)

	if not decoded_value is Dictionary:
		return _fail("Generation snapshot is not Variant-serializable.")

	var decoded_snapshot := decoded_value as Dictionary
	var original_client_room_count := client_generator.maximum_rooms
	var invalid_snapshot := decoded_snapshot.duplicate(true)
	invalid_snapshot["maximum_rooms"] = 101

	if client_generator.apply_generation_settings_snapshot(invalid_snapshot):
		return _fail("Client accepted an out-of-range generation snapshot.")

	if client_generator.maximum_rooms != original_client_room_count:
		return _fail("Invalid snapshot changed client settings partially.")

	if not client_generator.apply_generation_settings_snapshot(
		decoded_snapshot
	):
		return _fail("Client rejected the authoritative host snapshot.")

	var applied_snapshot := client_generator.get_generation_settings_snapshot()

	if applied_snapshot != decoded_snapshot:
		return _fail("Client settings do not exactly match the host snapshot.")

	# The stored active snapshot must remain stable for late joiners even if a
	# local property is changed after the original network level started.
	host_generator.active_network_generation_settings = (
		decoded_snapshot.duplicate(true)
	)
	host_generator.maximum_rooms = 12

	if (
		int(host_generator.active_network_generation_settings["maximum_rooms"])
		!= EXPECTED_ROOM_COUNT
	):
		return _fail("Late-join snapshot changed with local generator state.")

	host_generator.maximum_rooms = EXPECTED_ROOM_COUNT
	await host_generator.generate_level(TEST_SEED, false)
	await client_generator.generate_level(TEST_SEED, false)

	if (
		host_generator.generated_rooms.size() <= 30
		or host_generator.generated_rooms.size() != EXPECTED_ROOM_COUNT
	):
		return _fail("Test seed did not exercise the >30-room difficulty case.")

	if host_generator.generated_floor_count != EXPECTED_FLOOR_COUNT:
		return _fail("Host did not generate the synchronized floor count.")

	if _generation_signature(host_generator) != _generation_signature(
		client_generator
	):
		return _fail("Host and client diverged with the synchronized snapshot.")

	# Preserve the original one-argument entry point used by existing callers.
	client_generator.maximum_rooms = 5
	client_generator.minimum_floors = 1
	client_generator.maximum_floors = 1
	client_generator.rare_room_chance = 0.0
	client_generator.minimum_surveillance_cameras = 0
	client_generator.maximum_surveillance_cameras = 0
	await client_generator.generate_network_level(TEST_SEED + 1)

	if (
		client_generator.active_network_seed != TEST_SEED + 1
		or client_generator.generated_rooms.size() != 5
	):
		return _fail("Legacy one-argument network generation no longer works.")

	print(
		"NETWORK_GENERATION_SETTINGS_SMOKE_TEST_OK rooms=%d floors=%d"
		% [EXPECTED_ROOM_COUNT, EXPECTED_FLOOR_COUNT]
	)
	return 0


func _generation_signature(generator: ProceduralLevelGenerator) -> Array[String]:
	var signature: Array[String] = []

	for room in generator.generated_rooms:
		signature.append(
			"%s|%s|%d|%s"
			% [
				room.room_id,
				room.room_type,
				room.floor_index,
				_transform_signature(room.global_transform),
			]
		)

	for camera in generator.generated_surveillance_cameras:
		signature.append(
			"camera|%s" % _transform_signature(camera.global_transform)
		)

	signature.append("floors|%d" % generator.generated_floor_count)
	return signature


func _transform_signature(value: Transform3D) -> String:
	var components := [
		value.origin.x,
		value.origin.y,
		value.origin.z,
		value.basis.x.x,
		value.basis.x.y,
		value.basis.x.z,
		value.basis.y.x,
		value.basis.y.y,
		value.basis.y.z,
		value.basis.z.x,
		value.basis.z.y,
		value.basis.z.z,
	]
	var formatted: Array[String] = []

	for component in components:
		formatted.append("%.4f" % snappedf(float(component), 0.0001))

	return ",".join(formatted)


func _fail(message: String) -> int:
	push_error("NETWORK_GENERATION_SETTINGS_SMOKE_TEST_FAILED: " + message)
	return 1
