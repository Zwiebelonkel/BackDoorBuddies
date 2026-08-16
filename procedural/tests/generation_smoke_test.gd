extends Node


const TEST_SEED := 424242
const PLAYER_SCENE := preload("res://scenes/PlayerController.tscn")
const BLENDER_ROOM_TEMPLATE := preload(
	"res://procedural/rooms/blender_room_template.tscn"
)
const EXPECTED_FLOOR_MATERIAL := preload(
	"res://resources/textures/metal.tres"
)
const EXPECTED_WALL_MATERIAL := preload(
	"res://resources/textures/darkBricks.tres"
)

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

	var large_room_error := _validate_large_rooms()

	if not large_room_error.is_empty():
		return _fail(large_room_error)

	var surveillance_error := _validate_surveillance_cameras()

	if not surveillance_error.is_empty():
		return _fail(surveillance_error)

	var blender_template_error := _validate_blender_room_template()

	if not blender_template_error.is_empty():
		return _fail(blender_template_error)

	var pickup_error := _validate_pickup_layers()

	if not pickup_error.is_empty():
		return _fail(pickup_error)

	var value_tracking_error: String = await _validate_value_tracking()

	if not value_tracking_error.is_empty():
		return _fail(value_tracking_error)

	var van_system_error: String = await _validate_van_systems()

	if not van_system_error.is_empty():
		return _fail(van_system_error)

	var player_system_error: String = await _validate_player_systems()

	if not player_system_error.is_empty():
		return _fail(player_system_error)

	var wall_error := _validate_wall_inset()

	if not wall_error.is_empty():
		return _fail(wall_error)

	var surface_material_error := _validate_room_surface_materials()

	if not surface_material_error.is_empty():
		return _fail(surface_material_error)

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


func _validate_large_rooms() -> String:
	var large_room_count := 0

	for room in generator.generated_rooms:
		if room.room_type != &"large":
			continue

		large_room_count += 1
		var bounds_box := room.bounds_shape.shape as BoxShape3D

		if (
			bounds_box == null
			or bounds_box.size.x < 9.0
			or bounds_box.size.z < 7.0
		):
			return "A configured large room does not have a large footprint."

	if large_room_count < generator.minimum_large_rooms:
		return "Generation did not create the required number of large rooms."

	return ""


func _validate_room_surface_materials() -> String:
	var hall_floor := $Hall/Geometry/Floor as MeshInstance3D

	if (
		hall_floor == null
		or hall_floor.mesh == null
		or hall_floor.mesh.surface_get_material(0)
		!= EXPECTED_FLOOR_MATERIAL
	):
		return "The van hall floor is not using metal.tres."

	for wall_name in [&"SouthWall", &"EastWall", &"WestWall", &"WestWall2"]:
		var hall_wall := $Hall/Geometry.get_node_or_null(
			NodePath(wall_name)
		) as MeshInstance3D

		if (
			hall_wall == null
			or hall_wall.mesh == null
			or hall_wall.mesh.surface_get_material(0)
			!= EXPECTED_WALL_MATERIAL
		):
			return "A van hall wall is not using darkBricks.tres."

	for room in generator.generated_rooms:
		var floor_mesh := room.get_node_or_null(
			"Geometry/Floor/FloorMesh"
		) as MeshInstance3D
		var walls_root := room.get_node_or_null(
			"Geometry/Walls"
		) as Node3D

		if (
			floor_mesh == null
			or floor_mesh.mesh == null
			or floor_mesh.mesh.surface_get_material(0)
			!= EXPECTED_FLOOR_MATERIAL
		):
			return "A generated room floor is not using metal.tres."

		if walls_root == null or walls_root.get_child_count() == 0:
			return "A generated room has no wall meshes to validate."

		for child in walls_root.get_children():
			var wall_mesh := child as MeshInstance3D

			if (
				wall_mesh == null
				or wall_mesh.mesh == null
				or wall_mesh.mesh.surface_get_material(0)
				!= EXPECTED_WALL_MATERIAL
			):
				return "A generated room wall is not using darkBricks.tres."

	return ""


func _validate_blender_room_template() -> String:
	var template := BLENDER_ROOM_TEMPLATE.instantiate() as ProceduralRoom

	if template == null:
		return "Blender room template does not use ProceduralRoom at its root."

	if not template._get_configuration_warnings().is_empty():
		var warning_text := ", ".join(template._get_configuration_warnings())
		template.free()
		return "Blender room template is incomplete: " + warning_text

	var bounds := template.get_node_or_null(
		"RoomBounds/CollisionShape3D"
	) as CollisionShape3D

	if bounds == null or not bounds.shape is BoxShape3D:
		template.free()
		return "Blender room template has no BoxShape3D room bounds."

	var sockets_root := template.get_node_or_null("DoorSockets")

	if sockets_root == null or sockets_root.get_child_count() < 1:
		template.free()
		return "Blender room template has no door socket examples."

	for child in sockets_root.get_children():
		var socket := child as RoomSocket

		if socket == null:
			continue

		var outward := Vector3(socket.position.x, 0.0, socket.position.z)

		if outward.is_zero_approx():
			template.free()
			return "Blender room template socket is not on a room boundary."

		outward = outward.normalized()

		if socket.basis.z.normalized().dot(outward) < 0.99:
			template.free()
			return "Blender room template socket +Z does not point outward."

	template.free()
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

	player.player_hud.call("_update_performance_display")

	if (
		player.player_hud.fps_label == null
		or not player.player_hud.fps_label.text.begins_with("FPS  ")
		or player.player_hud.ping_label == null
		or not player.player_hud.ping_label.text.begins_with("PING  ")
		or not Networking.has_method("get_server_ping_ms")
	):
		_cleanup_test_player(player)
		return "Local HUD FPS or server ping display is incomplete."

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

	if (
		not minimap_map.has_method("get_scanned_camera_count")
		or minimap_map.get_scanned_camera_count()
		!= generator.generated_surveillance_cameras.size()
	):
		return "Generated surveillance cameras are missing from the room scan."

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
	await get_tree().physics_frame
	value_tracker.refresh_values()
	await get_tree().process_frame

	if not first_item.van_attached:
		first_item.global_transform = original_transform
		return "An item inside the van was not attached as cargo."

	if value_tracker.van_value != moved_item_value:
		_restore_test_cargo_item(first_item, original_transform)
		return "An item inside the van was not added to the van value."

	if value_tracker.generated_room_value != expected_room_value - moved_item_value:
		_restore_test_cargo_item(first_item, original_transform)
		return "An item moved into the van remained in the generated room value."

	if (
		minimap_map.get_scanned_item_count()
		!= generator.items_root.get_child_count() - 1
	):
		_restore_test_cargo_item(first_item, original_transform)
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
		_restore_test_cargo_item(first_item, original_transform)
		return "Van item overview did not update its van value."

	if room_value_label.text != "$%d" % (expected_room_value - moved_item_value):
		_restore_test_cargo_item(first_item, original_transform)
		return "Van item overview did not update its generated room value."

	var van := $Hall/Van as DrivableVan
	var original_van_transform := van.global_transform
	var cargo_local_transform := first_item.van_local_transform

	van.global_position += van.global_transform.basis.x.normalized() * 0.75
	van.rotate_y(0.15)
	first_item.apply_van_transform(van.global_transform)

	if not first_item.global_transform.is_equal_approx(
		van.global_transform * cargo_local_transform
	):
		van.global_transform = original_van_transform
		_restore_test_cargo_item(first_item, original_transform)
		return "Attached van cargo did not preserve its local transform."

	van.global_transform = original_van_transform
	_restore_test_cargo_item(first_item, original_transform)
	value_tracker.refresh_values()
	return ""


func _validate_surveillance_cameras() -> String:
	var cameras := generator.generated_surveillance_cameras
	var minimum_expected := mini(
		generator.minimum_surveillance_cameras,
		generator.generated_rooms.size()
	)
	var maximum_expected := mini(
		maxi(generator.maximum_surveillance_cameras, minimum_expected),
		generator.generated_rooms.size()
	)

	if cameras.size() < minimum_expected or cameras.size() > maximum_expected:
		return "Generated surveillance camera count is outside its configured range."

	var occupied_rooms := {}

	for surveillance_camera in cameras:
		if (
			surveillance_camera == null
			or surveillance_camera.feed_camera == null
			or not surveillance_camera.get_parent() is ProceduralRoom
		):
			return "A generated surveillance camera is incomplete."

		if occupied_rooms.has(surveillance_camera.room_generation_index):
			return "A generated room received more than one surveillance camera."

		occupied_rooms[surveillance_camera.room_generation_index] = true

	var monitor := $Hall/Van/CameraMonitor
	var viewport := monitor.get_node_or_null("SubViewport") as SubViewport
	var interaction := monitor.get_node_or_null("Interaction")

	if viewport == null or viewport.size != Vector2i(512, 512):
		return "Van camera monitor SubViewport is missing or has the wrong size."

	if interaction == null or not interaction.has_method("request_interaction"):
		return "Van camera monitor cannot be accessed by the player."

	monitor.refresh_cameras()

	if monitor.get_camera_count() != cameras.size():
		return "Van camera monitor did not discover the generated cameras."

	if cameras.size() > 1:
		var first_camera_id: int = monitor.get_current_camera_id()
		monitor.next_camera()

		if monitor.get_current_camera_id() == first_camera_id:
			return "Van camera monitor did not switch to the next feed."

	monitor.call("_update_feed")
	var feed_camera := monitor.get_node("SubViewport/FeedCamera") as Camera3D
	var active_camera: SurveillanceCamera = null

	if (
		feed_camera == null
		or feed_camera.environment == null
		or feed_camera.environment.fog_enabled
		or feed_camera.environment.volumetric_fog_enabled
	):
		return "Van camera monitor feed is not using a fog-free environment."

	for surveillance_camera in cameras:
		if surveillance_camera.camera_id == monitor.get_current_camera_id():
			active_camera = surveillance_camera
			break

	if (
		feed_camera == null
		or active_camera == null
		or not feed_camera.global_transform.is_equal_approx(
			active_camera.get_feed_transform()
		)
	):
		return "Van camera monitor did not display the selected camera feed."

	var test_player := PLAYER_SCENE.instantiate() as FPSController
	test_player.name = "1"
	$Players.add_child(test_player)
	test_player.set_physics_process(false)
	monitor.refresh_cameras()

	if monitor.get_camera_count() != cameras.size() + 1:
		_cleanup_test_player(test_player)
		monitor.refresh_cameras()
		return "Van camera monitor did not add a live feed for each player."

	var live_feed_camera := test_player.get_node_or_null(
		"Head/LiveFeedCamera"
	) as Camera3D

	if live_feed_camera == null or live_feed_camera.current:
		_cleanup_test_player(test_player)
		monitor.refresh_cameras()
		return "Player live feed camera is missing or became the gameplay camera."

	var original_camera_transform := test_player.camera.transform
	var original_camera_fov := test_player.camera.fov

	if not monitor.begin_view(test_player):
		_cleanup_test_player(test_player)
		monitor.refresh_cameras()
		return "Player could not enter the van camera monitor view."

	var feed_spotlight := monitor.get_node(
		"SubViewport/FeedCamera/FeedSpotLight"
	) as SpotLight3D

	if (
		not test_player.is_using_camera_monitor(monitor)
		or feed_spotlight == null
		or not feed_spotlight.visible
	):
		test_player.exit_camera_monitor()
		_cleanup_test_player(test_player)
		monitor.refresh_cameras()
		return "Monitor view or its local green spotlight was not activated."

	test_player.call("_update_camera_monitor_view")

	if (
		not test_player.camera.global_transform.is_equal_approx(
			monitor.get_view_transform(test_player.global_position)
		)
		or not is_equal_approx(
			test_player.camera.fov,
			monitor.get_viewing_fov()
		)
	):
		test_player.exit_camera_monitor()
		_cleanup_test_player(test_player)
		monitor.refresh_cameras()
		return "Monitor view did not fix and zoom the player camera onto the screen."

	var rotatable_camera := cameras[0]
	var original_surveillance_transform := rotatable_camera.global_transform
	var original_pan := rotatable_camera.pan_degrees

	for _index in range(monitor.get_camera_count()):
		if monitor.get_current_camera_id() == rotatable_camera.camera_id:
			break

		monitor.next_camera()

	monitor.rotate_current_camera(1.0, 0.25)

	if is_equal_approx(rotatable_camera.pan_degrees, original_pan):
		test_player.exit_camera_monitor()
		_cleanup_test_player(test_player)
		monitor.refresh_cameras()
		return "A/D camera rotation did not pan the selected room camera."

	rotatable_camera.global_transform = original_surveillance_transform
	rotatable_camera.pan_degrees = original_pan

	for _index in range(monitor.get_camera_count()):
		if monitor.get_current_camera_id() < 0:
			break

		monitor.next_camera()

	monitor.call("_update_feed")

	if not feed_camera.global_transform.is_equal_approx(
		test_player.get_live_feed_transform()
	):
		test_player.exit_camera_monitor()
		_cleanup_test_player(test_player)
		monitor.refresh_cameras()
		return "Van monitor did not display the player's dedicated live feed."

	test_player.exit_camera_monitor()

	if (
		test_player.is_using_camera_monitor()
		or feed_spotlight.visible
		or not test_player.camera.transform.is_equal_approx(
			original_camera_transform
		)
		or not is_equal_approx(test_player.camera.fov, original_camera_fov)
	):
		_cleanup_test_player(test_player)
		monitor.refresh_cameras()
		return "Leaving monitor view did not restore the player camera."

	_cleanup_test_player(test_player)
	monitor.refresh_cameras()

	return ""


func _restore_test_cargo_item(
	item: PickupItem,
	original_transform: Transform3D
) -> void:
	item.detach_from_van()
	item.global_transform = original_transform


func _validate_van_systems() -> String:
	var van := $Hall/Van as DrivableVan
	var cargo_area := $Hall/Van/CargoArea as Area3D

	if van == null or cargo_area == null:
		return "The drivable van or its cargo area is missing."

	if (
		van.get_node_or_null("DriverSeat") == null
		or van.get_node_or_null("DriverExit") == null
		or van.get_node_or_null("DriverInteraction") == null
	):
		return "The van driver interaction markers are incomplete."

	var player := PLAYER_SCENE.instantiate() as FPSController
	player.name = "1"
	$Players.add_child(player)
	player.set_physics_process(false)
	player.global_position = cargo_area.global_position

	var original_van_transform := van.global_transform
	var original_player_scale := player.global_basis.get_scale()
	var original_player_path := player.get_path()
	var passenger_local_transform := (
		van.global_transform.affine_inverse()
		* player.global_transform
	)

	van.set("_current_speed", 2.0)
	van.call("_physics_process", 0.1)
	van.set("_current_speed", 0.0)

	var carried_local_transform := (
		van.global_transform.affine_inverse()
		* player.global_transform
	)

	if not carried_local_transform.is_equal_approx(passenger_local_transform):
		_cleanup_van_test(van, player, original_van_transform)
		return "A passenger inside the van was not carried with it."

	if player.get_path() != original_player_path or player.get_parent() != $Players:
		_cleanup_van_test(van, player, original_van_transform)
		return "Van passenger carrying changed the player multiplayer path."

	player.global_position = (
		van.get_node("DriverInteraction") as Node3D
	).global_position
	van.request_drive(player)

	if van.get_driver_peer_id() != 1 or not player.is_driving_vehicle():
		_cleanup_van_test(van, player, original_van_transform)
		return "The local player could not take the van driver seat."

	if player.get_path() != original_player_path or player.get_parent() != $Players:
		_cleanup_van_test(van, player, original_van_transform)
		return "Entering the van changed the player multiplayer path."

	if not player.global_basis.get_scale().is_equal_approx(original_player_scale):
		_cleanup_van_test(van, player, original_van_transform)
		return "Entering the scaled van changed the player size."

	van.request_driver_exit(player)

	if van.get_driver_peer_id() != 0 or player.is_driving_vehicle():
		_cleanup_van_test(van, player, original_van_transform)
		return "The driver could not exit the van."

	if not player.global_basis.get_scale().is_equal_approx(original_player_scale):
		_cleanup_van_test(van, player, original_van_transform)
		return "Exiting the scaled van changed the player size."

	_cleanup_van_test(van, player, original_van_transform)
	return ""


func _cleanup_van_test(
	van: DrivableVan,
	player: FPSController,
	original_van_transform: Transform3D
) -> void:
	if van.get_driver_peer_id() == 1:
		van.call(
			"_apply_driver_exit",
			1,
			(van.get_node("DriverExit") as Marker3D).global_transform
		)

	van.set("_current_speed", 0.0)
	van.global_transform = original_van_transform
	_cleanup_test_player(player)


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

	for surveillance_camera in generator.generated_surveillance_cameras:
		parts.append(
			"camera:%d:%d:%s" % [
				surveillance_camera.camera_id,
				surveillance_camera.room_generation_index,
				str(surveillance_camera.global_transform)
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
