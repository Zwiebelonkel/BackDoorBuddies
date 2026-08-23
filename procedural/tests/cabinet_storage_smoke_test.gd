extends Node3D


const PLAYER_SCENE := preload("res://scenes/PlayerController.tscn")
const VAN_SCENE := preload("res://scenes/props/van/Van.tscn")

@onready var cabinet: Area3D = $Cabinet/Interaction

var player: FPSController


func _ready() -> void:
	var exit_code := await _run_test()
	get_tree().quit(exit_code)


func _run_test() -> int:
	player = PLAYER_SCENE.instantiate() as FPSController
	player.name = "1"
	$Players.add_child(player)
	await get_tree().process_frame
	await get_tree().process_frame
	player.set_physics_process(false)

	var van := VAN_SCENE.instantiate() as Node3D
	add_child(van)
	await get_tree().physics_frame
	var instanced_cabinet := van.get_node_or_null("Cabinet") as Node3D
	var instanced_storage := (
		instanced_cabinet.get_node_or_null("Interaction") as Area3D
		if instanced_cabinet != null
		else null
	)

	if (
		instanced_cabinet == null
		or instanced_storage == null
		or not instanced_storage.has_method("request_interaction")
		or not instanced_storage.has_method("get_interaction_text")
		or instanced_cabinet.get_node_or_null("Interaction/CollisionShape3D")
		== null
	):
		return _fail("The Cabinet instance in Van.tscn is not interactable.")

	var interaction_area := instanced_storage
	var ray_start := instanced_cabinet.to_global(
		Vector3(0.0, 0.488352, 1.3)
	)
	var ray_end := instanced_cabinet.to_global(
		Vector3(0.0, 0.488352, -0.21)
	)
	var ray_query := PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	ray_query.collision_mask = 5
	ray_query.collide_with_areas = true
	ray_query.collide_with_bodies = true
	var ray_hit := get_world_3d().direct_space_state.intersect_ray(ray_query)

	if ray_hit.is_empty() or ray_hit.get("collider") != interaction_area:
		return _fail("The player interaction ray cannot reach the Van cabinet.")

	player.global_position = ray_start - Vector3.UP * 1.683
	player.camera.look_at(interaction_area.global_position, Vector3.UP)
	player.interaction_ray.force_raycast_update()

	if player.interaction_ray.get_collider() != interaction_area:
		return _fail("The actual Player InteractionRay misses the Van cabinet.")

	player._try_interact()
	await get_tree().process_frame

	if (
		not player.is_using_cabinet_storage(interaction_area)
		or not bool(interaction_area.get("storage_interface").call(
			"is_open_for",
			player
		))
	):
		return _fail("Pressing interact did not open the Van cabinet interface.")

	player.exit_cabinet_storage()
	van.queue_free()
	await get_tree().process_frame
	player.global_position = cabinet.global_position + Vector3(0.0, 0.0, 1.0)

	var pistol := load("res://resources/items/1911.tres") as ItemData
	var weed := load("res://resources/items/weed.tres") as ItemData

	if pistol == null or weed == null:
		return _fail("Cabinet test ItemData could not be loaded.")

	if not player.server_receive_item(pistol, "cabinet_pistol"):
		return _fail("Player could not receive the cabinet test item.")

	cabinet.call(
		"request_store_item",
		player,
		"cabinet_pistol",
		pistol.resource_path
	)
	await get_tree().process_frame

	if (
		cabinet.get("stored_item_instance_ids") != ["cabinet_pistol"]
		or not player.inventory.is_empty()
		or not player.server_inventory_paths.is_empty()
	):
		return _fail("Depositing did not atomically move the item into storage.")

	cabinet.call("request_interaction", player)
	await get_tree().process_frame

	if (
		not player.is_using_cabinet_storage(cabinet)
		or not bool(cabinet.get("storage_interface").call("is_open_for", player))
		or player.player_hud.visible
		or cabinet.get("storage_interface").get_node(
			"Root/Window/Margin/Layout/Content/StoragePanel/Margin/Section/StorageGrid"
		).get_child_count() != 15
	):
		return _fail("Cabinet interaction did not open the 15-slot interface.")

	var storage_interface := (
		cabinet.get("storage_interface") as StorageInterface
	)
	var inventory_grid := storage_interface.inventory_grid
	var storage_grid := storage_interface.storage_grid
	var storage_slot := storage_grid.get_child(0) as Button
	var storage_drag_data: Variant = {
		"drag_type": &"van_storage_item",
		"source_kind": &"storage",
		"item_instance_id": str(storage_slot.get_meta(
			&"item_instance_id",
			""
		)),
	}

	if (
		not storage_drag_data is Dictionary
		or not storage_interface._can_drop_slot_data(
			Vector2.ZERO,
			storage_drag_data,
			&"inventory"
		)
	):
		return _fail("A stored item cannot be dragged back to the inventory.")

	storage_interface._drop_slot_data(
		Vector2.ZERO,
		storage_drag_data,
		&"inventory"
	)
	await get_tree().process_frame

	if (
		not cabinet.get("stored_item_paths").is_empty()
		or player.inventory_instance_ids != ["cabinet_pistol"]
	):
		return _fail("Dragging storage to inventory did not transfer the item.")

	var inventory_slot := inventory_grid.get_child(0) as Button
	var inventory_drag_data: Variant = {
		"drag_type": &"van_storage_item",
		"source_kind": &"inventory",
		"item_instance_id": str(inventory_slot.get_meta(
			&"item_instance_id",
			""
		)),
	}

	if (
		not inventory_drag_data is Dictionary
		or not storage_interface._can_drop_slot_data(
			Vector2.ZERO,
			inventory_drag_data,
			&"storage"
		)
	):
		return _fail("An inventory item cannot be dragged into storage.")

	storage_interface._drop_slot_data(
		Vector2.ZERO,
		inventory_drag_data,
		&"storage"
	)
	await get_tree().process_frame

	if (
		cabinet.get("stored_item_instance_ids") != ["cabinet_pistol"]
		or not player.inventory.is_empty()
	):
		return _fail("Dragging inventory to storage did not transfer the item.")

	var double_click_event := InputEventMouseButton.new()
	double_click_event.button_index = MOUSE_BUTTON_LEFT
	double_click_event.pressed = true
	double_click_event.double_click = true
	storage_interface._on_slot_gui_input(
		double_click_event,
		storage_grid.get_child(0) as Button,
		&"storage",
		0
	)
	await get_tree().process_frame

	if (
		not cabinet.get("stored_item_paths").is_empty()
		or player.inventory_instance_ids != ["cabinet_pistol"]
	):
		return _fail("Double-clicking storage did not retrieve the item.")

	storage_interface._on_slot_gui_input(
		double_click_event,
		inventory_grid.get_child(0) as Button,
		&"inventory",
		0
	)
	await get_tree().process_frame

	if (
		cabinet.get("stored_item_instance_ids") != ["cabinet_pistol"]
		or not player.inventory.is_empty()
	):
		return _fail("Double-clicking inventory did not store the item.")

	var escape_event := InputEventAction.new()
	escape_event.action = &"ui_cancel"
	escape_event.pressed = true
	storage_interface._input(escape_event)
	await get_tree().process_frame

	if (
		storage_interface.visible
		or player.is_using_cabinet_storage()
		or not player.player_hud.visible
		or get_tree().paused
	):
		return _fail("ESC did not close only the cabinet and restore gameplay.")

	cabinet.call("request_take_item", player, "cabinet_pistol")
	await get_tree().process_frame

	if (
		cabinet.get("stored_item_paths").is_empty() == false
		or player.inventory_instance_ids != ["cabinet_pistol"]
		or not player.server_has_inventory_item(
			"cabinet_pistol",
			pistol.resource_path
		)
	):
		return _fail("Taking an item did not preserve its exact instance ID.")

	for item_index in range(15):
		var instance_id := "cabinet_fill_%02d" % item_index

		if not player.server_receive_item(weed, instance_id):
			return _fail("Player could not receive storage fill item %d." % item_index)

		cabinet.call(
			"request_store_item",
			player,
			instance_id,
			weed.resource_path
		)

	if cabinet.get("stored_item_paths").size() != 15:
		return _fail("Cabinet did not accept exactly 15 items.")

	if not player.server_receive_item(weed, "cabinet_overflow"):
		return _fail("Player could not receive the overflow test item.")

	cabinet.call(
		"request_store_item",
		player,
		"cabinet_overflow",
		weed.resource_path
	)

	if (
		cabinet.get("stored_item_paths").size() != 15
		or not player.server_has_inventory_item(
			"cabinet_overflow",
			weed.resource_path
		)
	):
		return _fail("The cabinet capacity guard lost or accepted an overflow item.")

	cabinet.call("request_take_item", player, "cabinet_fill_00")

	if (
		cabinet.get("stored_item_paths").size() != 14
		or not player.server_has_inventory_item(
			"cabinet_fill_00",
			weed.resource_path
		)
	):
		return _fail("A stored item could not be retrieved after a full-capacity test.")

	print("CABINET_STORAGE_SMOKE_TEST_OK")
	return 0


func _fail(message: String) -> int:
	push_error(message)
	return 1
