extends Node3D

const FLASHLIGHT_PATH := "res://resources/items/flashlight.tres"


func _ready() -> void:
	var flashlight := load(FLASHLIGHT_PATH) as ItemData
	assert(flashlight != null)
	assert(flashlight.item_id == &"flashlight")
	assert(flashlight.world_model != null)
	assert(flashlight.held_model != null)
	assert(flashlight.icon != null)

	var held := flashlight.held_model.instantiate() as FlashlightHeld
	assert(held != null)
	add_child(held)
	await get_tree().process_frame
	var model_bounds := _get_visual_bounds(held)
	assert(model_bounds.size.z > 0.35)
	assert(model_bounds.size.x < 0.15)
	assert(held.beam.position.z < -0.25)
	assert(absf(held.beam.position.z - model_bounds.position.z) < 0.08)
	assert(not held.is_light_enabled())
	assert(not held.beam.visible)
	held.use_primary()
	assert(held.is_light_enabled())
	assert(held.beam.visible)
	held.use_primary()
	assert(not held.is_light_enabled())
	assert(not held.beam.visible)

	var player := preload(
		"res://scenes/PlayerController.tscn"
	).instantiate() as FPSController
	player.name = str(multiplayer.get_unique_id())
	add_child(player)
	await get_tree().process_frame
	player._equip_item(flashlight)
	var equipped_flashlight := (
		player.held_item_instance as FlashlightHeld
	)
	assert(equipped_flashlight != null)
	assert(not equipped_flashlight.is_light_enabled())
	player._use_held_item()
	assert(equipped_flashlight.is_light_enabled())
	player._use_held_item()
	assert(not equipped_flashlight.is_light_enabled())

	var pickup := preload(
		"res://procedural/items/flashlight_pickup.tscn"
	).instantiate() as PickupItem
	assert(pickup != null)
	assert(pickup.item_data == flashlight)
	add_child(pickup)
	await get_tree().process_frame
	assert(pickup.get_node("ModelContainer").get_child_count() == 1)

	var common_table := load(
		"res://procedural/item_tables/common_floor_items.tres"
	) as ItemSpawnTable
	var flashlight_is_spawnable := false

	for entry in common_table.entries:
		if entry != null and entry.item_id == &"flashlight":
			flashlight_is_spawnable = true
			break

	assert(flashlight_is_spawnable)
	print("FLASHLIGHT_ITEM_SMOKE_TEST_OK")
	get_tree().quit(0)


func _get_visual_bounds(root: Node3D) -> AABB:
	var bounds := AABB()
	var has_bounds := false

	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D

		if mesh_instance == null or mesh_instance.mesh == null:
			continue

		var world_bounds := (
			mesh_instance.global_transform
			* mesh_instance.get_aabb()
		)

		if has_bounds:
			bounds = bounds.merge(world_bounds)
		else:
			bounds = world_bounds
			has_bounds = true

	return bounds
