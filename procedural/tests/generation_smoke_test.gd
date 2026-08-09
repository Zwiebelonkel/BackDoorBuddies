extends Node


const TEST_SEED := 424242
const PLAYER_SCENE := preload("res://scenes/PlayerController.tscn")

@onready var generator: ProceduralLevelGenerator = $ProceduralLevelGenerator
@onready var value_tracker: ItemValueTracker = $ItemValueTracker


func _ready() -> void:
	var exit_code := await _run_test()
	get_tree().quit(exit_code)


func _run_test() -> int:
	await generator.generate_level(TEST_SEED, true)

	if generator.generated_rooms.size() < 2:
		return _fail("Generation produced fewer than two rooms.")

	if generator.items_root.get_child_count() == 0:
		return _fail("Generation produced no items.")

	var pickup_error := _validate_pickup_layers()

	if not pickup_error.is_empty():
		return _fail(pickup_error)

	var value_tracking_error: String = await _validate_value_tracking()

	if not value_tracking_error.is_empty():
		return _fail(value_tracking_error)

	var player_system_error: String = await _validate_player_systems()

	if not player_system_error.is_empty():
		return _fail(player_system_error)

	var wall_error := _validate_wall_inset()

	if not wall_error.is_empty():
		return _fail(wall_error)

	var door_error := _validate_exit_door()

	if not door_error.is_empty():
		return _fail(door_error)

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


func _validate_pickup_layers() -> String:
	var player: Node = PLAYER_SCENE.instantiate()
	var interaction_ray := player.get_node("Head/Camera3D/InteractionRay") as RayCast3D
	var item := generator.items_root.get_child(0) as CollisionObject3D

	if interaction_ray == null or (interaction_ray.collision_mask & 4) == 0:
		player.free()
		return "InteractionRay does not include the pickup layer."

	if item == null or (item.collision_layer & 4) == 0:
		player.free()
		return "A generated item is not on the pickup layer."

	player.free()
	return ""


func _validate_player_systems() -> String:
	var expected_weights := {
		"res://resources/items/weed.tres": 0.15,
		"res://resources/items/mdma.tres": 0.1,
		"res://resources/items/cocaine.tres": 0.25,
		"res://resources/items/knife.tres": 0.7,
		"res://resources/items/1911.tres": 1.2,
		"res://resources/items/weedBag.tres": 6.0,
		"res://resources/items/cokeBrick.tres": 8.0,
	}
	var expected_values := {
		"res://resources/items/weed.tres": 80,
		"res://resources/items/mdma.tres": 120,
		"res://resources/items/cocaine.tres": 250,
		"res://resources/items/knife.tres": 150,
		"res://resources/items/1911.tres": 650,
		"res://resources/items/weedBag.tres": 1250,
		"res://resources/items/cokeBrick.tres": 2500,
	}

	for item_path: String in expected_weights:
		var item_data := load(item_path) as ItemData
		var expected_weight: float = expected_weights[item_path]

		if item_data == null or not is_equal_approx(item_data.weight, expected_weight):
			return "Item weight is missing or incorrect: " + item_path

		if item_data.value != int(expected_values[item_path]):
			return "Item value is missing or incorrect: " + item_path

	var weed_bag := load("res://resources/items/weedBag.tres") as ItemData
	var coke_brick := load("res://resources/items/cokeBrick.tres") as ItemData
	var weed := load("res://resources/items/weed.tres") as ItemData
	var mdma := load("res://resources/items/mdma.tres") as ItemData

	if not weed_bag.is_large_item or not coke_brick.is_large_item:
		return "Both large item resources must be marked as large."

	var player := PLAYER_SCENE.instantiate() as FPSController
	player.name = "1"
	$Players.add_child(player)
	player.global_transform = (
		generator.generated_rooms[0]
		.get_node("PlayerArrival")
		.global_transform
	)
	player.inventory.append(weed)
	player.inventory.append(mdma)
	player.server_inventory_paths.append(weed.resource_path)
	player.server_inventory_paths.append(mdma.resource_path)
	player.select_inventory_item(0)

	if not player.server_receive_item(weed_bag):
		_cleanup_test_player(player)
		return "Server rejected a valid large item pickup."

	if (
		player.selected_inventory_index != 2
		or player.equipped_item_resource_path != weed_bag.resource_path
	):
		_cleanup_test_player(player)
		return "A picked-up large item was not equipped immediately."

	if not is_equal_approx(player.get_total_inventory_weight(), 6.25):
		_cleanup_test_player(player)
		return "Player inventory weight is not summed correctly."

	if not is_equal_approx(player.get_weight_speed_multiplier(), 0.78125):
		_cleanup_test_player(player)
		return "Weight speed multiplier is incorrect."

	if player.server_receive_item(coke_brick):
		_cleanup_test_player(player)
		return "Server accepted a pickup while a large item was held."

	player.select_inventory_item(1)

	if player.selected_inventory_index != 2:
		_cleanup_test_player(player)
		return "Player switched away from a held large item."

	player.select_inventory_item(3)

	if player.selected_inventory_index != 2 or not player.is_holding_large_item():
		_cleanup_test_player(player)
		return "Player unequipped a large item through an empty slot."

	player._sync_equipped_item(weed.resource_path)

	if player.equipped_item_resource_path != weed_bag.resource_path:
		_cleanup_test_player(player)
		return "Server accepted an equipment switch away from a large item."

	player.inventory_changed.emit(
		player.inventory,
		player.selected_inventory_index
	)
	player.stamina_changed.emit(42.0, 100.0)

	if player.player_hud.weight_label.text != "GEWICHT  6.25 KG":
		_cleanup_test_player(player)
		return "Local HUD weight display is incorrect."

	if player.player_hud.inventory_value_label.text != "WERT  $1450":
		_cleanup_test_player(player)
		return "Local HUD inventory value display is incorrect."

	if not is_equal_approx(player.player_hud.stamina_bar.value, 42.0):
		_cleanup_test_player(player)
		return "Local HUD stamina display is incorrect."

	for _frame in range(45):
		await get_tree().physics_frame

	if not player.is_on_floor():
		_cleanup_test_player(player)
		return "Stamina test player did not reach the floor."

	var stamina_before_sprint := player.current_stamina
	Input.action_press("move_forward")
	Input.action_press("sprint")

	for _frame in range(8):
		await get_tree().physics_frame

	Input.action_release("sprint")
	Input.action_release("move_forward")

	if player.current_stamina >= stamina_before_sprint:
		_cleanup_test_player(player)
		return "Sprinting did not consume stamina."

	player._server_drop_item(2)

	if player.is_holding_large_item() or player.selected_inventory_index != 1:
		_cleanup_test_player(player)
		return "Dropping a large item did not release the inventory lock."

	player.select_inventory_item(0)

	if player.selected_inventory_index != 0:
		_cleanup_test_player(player)
		return "Inventory switching stayed locked after dropping the large item."

	_cleanup_test_player(player)
	return ""


func _validate_value_tracking() -> String:
	var minimap_viewport := $Hall/Van/Minimap/SubViewport as SubViewport
	var minimap_map := $Hall/Van/Minimap/SubViewport/Map as Control
	var overview_viewport := $Hall/Van/ItemOverview/SubViewport as SubViewport

	if minimap_viewport == null or minimap_viewport.size != Vector2i(512, 512):
		return "Van minimap SubViewport is missing or has the wrong size."

	if overview_viewport == null or overview_viewport.size != Vector2i(512, 512):
		return "Van item overview SubViewport is missing or has the wrong size."

	if (
		minimap_map == null
		or not minimap_map.has_method("get_scanned_item_count")
		or minimap_map.get_scanned_item_count()
		!= generator.items_root.get_child_count()
	):
		return "Generated room items are missing from the room scan."

	var expected_room_value := 0

	for child in generator.items_root.get_children():
		var pickup := child as PickupItem

		if pickup != null and pickup.item_data != null:
			expected_room_value += pickup.item_data.value

	value_tracker.refresh_values()

	if value_tracker.van_value != 0:
		return "Van value is non-zero before an item enters the van."

	if value_tracker.generated_room_value != expected_room_value:
		return "Generated room item value is not summed correctly."

	var first_item := generator.items_root.get_child(0) as PickupItem
	var cargo_area := $Hall/Van/CargoArea as Area3D

	if first_item == null or cargo_area == null:
		return "Value tracking test could not find an item or the van cargo area."

	var original_transform := first_item.global_transform
	var moved_item_value := first_item.item_data.value
	first_item.global_position = cargo_area.global_position
	value_tracker.refresh_values()
	await get_tree().process_frame

	if value_tracker.van_value != moved_item_value:
		first_item.global_transform = original_transform
		return "An item inside the van was not added to the van value."

	if value_tracker.generated_room_value != expected_room_value - moved_item_value:
		first_item.global_transform = original_transform
		return "An item moved into the van remained in the generated room value."

	if (
		minimap_map.get_scanned_item_count()
		!= generator.items_root.get_child_count() - 1
	):
		first_item.global_transform = original_transform
		return "An item inside the van remained visible on the room scan."

	var van_value_label := (
		$Hall/Van/ItemOverview/SubViewport/Interface/Margin/Content/VanValue
		as Label
	)
	var room_value_label := (
		$Hall/Van/ItemOverview/SubViewport/Interface/Margin/Content/RoomValue
		as Label
	)

	if van_value_label.text != "$%d" % moved_item_value:
		first_item.global_transform = original_transform
		return "Van item overview did not update its van value."

	if room_value_label.text != "$%d" % (expected_room_value - moved_item_value):
		first_item.global_transform = original_transform
		return "Van item overview did not update its generated room value."

	first_item.global_transform = original_transform
	value_tracker.refresh_values()
	return ""


func _cleanup_test_player(player: FPSController) -> void:
	var hud := player.player_hud

	$Players.remove_child(player)
	player.free()

	if is_instance_valid(hud):
		hud.queue_free()


func server_spawn_dropped_item(
	_item_path: String,
	_spawn_position: Vector3,
	_spawn_rotation: Vector3
) -> void:
	pass


func _validate_wall_inset() -> String:
	var start_room := generator.generated_rooms[0]
	var north_wall := start_room.get_node_or_null("Geometry/Walls/NorthLeft") as Node3D
	var south_wall := start_room.get_node_or_null("Geometry/Walls/SouthLeft") as Node3D

	if north_wall == null or south_wall == null:
		return "Start room wall pieces are missing."

	if not is_equal_approx(north_wall.position.z, -2.425):
		return "North wall is not inset from the socket plane."

	if not is_equal_approx(south_wall.position.z, 2.425):
		return "South wall is not inset from the socket plane."

	return ""


func _validate_exit_door() -> String:
	var start_room := generator.generated_rooms[0]
	var exit_door := start_room.get_node_or_null("ExitDoor") as ExitDoor

	if exit_door == null:
		return "The procedural start room has no exit door."

	var player := CharacterBody3D.new()
	player.name = "1"
	$Players.add_child(player)
	player.global_position = exit_door.global_position - exit_door.global_basis.z
	exit_door.request_interaction(player)

	var destination := $Hall/HallSpawnPoint as Marker3D
	var reached_destination := player.global_position.is_equal_approx(
		destination.global_position
	)

	if not reached_destination:
		$Players.remove_child(player)
		player.free()
		return "The exit door did not teleport the player to the hall marker."

	var hall_door := $Hall/BuildingEntrance as ExitDoor
	var building_destination := start_room.get_node("PlayerArrival") as Marker3D
	player.global_position = hall_door.global_position - hall_door.global_basis.z
	hall_door.request_interaction(player)
	var returned_to_building := player.global_position.is_equal_approx(
		building_destination.global_position
	)

	$Players.remove_child(player)
	player.free()

	if not returned_to_building:
		return "The hall entrance did not teleport the player into the building."

	return ""


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
