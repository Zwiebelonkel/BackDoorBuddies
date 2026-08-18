extends Node3D

var spawned_item_paths: Array[String] = []
var spawned_item_positions: Array[Vector3] = []


func _ready() -> void:
	var player_scene := load(
		"res://scenes/PlayerController.tscn"
	) as PackedScene
	var player := player_scene.instantiate() as FPSController
	player.name = "1"
	add_child(player)
	await get_tree().process_frame
	await get_tree().physics_frame

	var pistol := load("res://resources/items/1911.tres") as ItemData
	var sniper := load("res://resources/items/sniper.tres") as ItemData
	assert(pistol != null)
	assert(sniper != null)
	player.inventory.append(pistol)
	player.inventory.append(sniper)
	player.server_inventory_paths.append(pistol.resource_path)
	player.server_inventory_paths.append(sniper.resource_path)
	player.selected_inventory_index = 0
	player.equipped_item_resource_path = pistol.resource_path
	var sniper_held := sniper.held_model.instantiate() as SniperHeld
	assert(sniper_held != null)
	player.item_holder.add_child(sniper_held)
	player.held_item_instance = sniper_held
	sniper_held.use_secondary(true)
	await get_tree().create_timer(0.2).timeout
	var scope_fov_before_wheel := sniper_held.get_current_scope_fov()
	var wheel_up := InputEventMouseButton.new()
	wheel_up.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel_up.pressed = true
	player._unhandled_input(wheel_up)
	await get_tree().create_timer(0.1).timeout
	assert(sniper_held.get_current_scope_fov() < scope_fov_before_wheel)
	sniper_held.use_secondary(false)

	var hit_position := player.global_position + Vector3(0.0, 1.35, -0.2)
	player.server_receive_damage(
		player.maximum_health,
		1,
		hit_position,
		Vector3.BACK,
		Vector3.FORWARD * 5.5,
		&"sniper"
	)
	await get_tree().process_frame
	await get_tree().physics_frame

	assert(player.is_dead)
	assert(spawned_item_paths.size() == 2)
	assert(pistol.resource_path in spawned_item_paths)
	assert(sniper.resource_path in spawned_item_paths)
	assert(player.inventory.is_empty())
	assert(player.server_inventory_paths.is_empty())
	assert(player.selected_inventory_index == -1)
	assert(player.equipped_item_resource_path.is_empty())

	var player_decals := get_tree().get_nodes_in_group(
		"player_blood_decals"
	)
	assert(player_decals.size() == 1)
	var player_decal := player_decals[0] as Decal
	assert(player_decal != null)
	assert(player_decal.get_parent() is BoneAttachment3D)
	assert(player.is_ancestor_of(player_decal))

	var wall_decals := get_tree().get_nodes_in_group("wall_blood_decals")
	assert(wall_decals.size() == 1)
	var wall_decal := wall_decals[0] as Decal
	assert(wall_decal != null)
	assert(wall_decal.get_parent() == self)
	assert(wall_decal.global_position.z < -2.0)
	assert(is_equal_approx(
		wall_decal.size.x,
		player.blood_effects.sniper_hit_splatter_size
	))
	assert(
		player.blood_effects.sniper_hit_splatter_size
		> player.blood_effects.gun_hit_splatter_size
	)

	print("PLAYER_DEATH_DROP_BLOOD_TEST_PASS")
	get_tree().quit()


func server_spawn_dropped_item(
	item_path: String,
	spawn_position: Vector3,
	_spawn_rotation: Vector3
) -> void:
	spawned_item_paths.append(item_path)
	spawned_item_positions.append(spawn_position)
