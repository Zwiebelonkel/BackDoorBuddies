extends Node3D

var spawned_item_paths: Array[String] = []
var spawned_item_positions: Array[Vector3] = []
var spawned_item_instance_ids: Array[String] = []


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
	player.inventory_instance_ids.append("death_test_pistol")
	player.inventory_instance_ids.append("death_test_sniper")
	player.server_inventory_paths.append(pistol.resource_path)
	player.server_inventory_paths.append(sniper.resource_path)
	player.server_inventory_instance_ids.append("death_test_pistol")
	player.server_inventory_instance_ids.append("death_test_sniper")
	player.selected_inventory_index = -1
	player.equipped_item_resource_path = ""
	var unscoped_camera_fov := player.camera.fov
	player.select_inventory_item(1)
	var sniper_held := player.held_item_instance as SniperHeld
	assert(sniper_held != null)
	sniper_held.use_secondary(true)
	await get_tree().create_timer(0.2).timeout
	var scope_fov_before_wheel := sniper_held.get_current_scope_fov()
	var wheel_up := InputEventMouseButton.new()
	wheel_up.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel_up.pressed = true
	player._unhandled_input(wheel_up)
	await get_tree().create_timer(0.1).timeout
	assert(sniper_held.get_current_scope_fov() < scope_fov_before_wheel)
	assert(player.camera.fov < unscoped_camera_fov)
	player.select_inventory_item(0)
	assert(is_equal_approx(player.camera.fov, unscoped_camera_fov))
	assert(is_equal_approx(player._weapon_aim_sensitivity_multiplier, 1.0))
	player.select_inventory_item(1)
	sniper_held = player.held_item_instance as SniperHeld
	assert(sniper_held != null)
	sniper_held.use_secondary(true)
	await get_tree().create_timer(0.2).timeout
	assert(sniper_held.adjust_scope_zoom(1.0))
	await get_tree().create_timer(0.1).timeout
	assert(player.camera.fov < unscoped_camera_fov)

	var hit_position := player.global_position + Vector3(0.0, 1.35, -0.2)
	var camera_height_before_death := player.camera.global_position.y
	player.server_receive_damage(
		player.maximum_health,
		1,
		hit_position,
		Vector3.BACK,
		Vector3.FORWARD * 5.5,
		&"sniper"
	)
	var damage_flash := player.player_hud.get_node(
		"DamageFlash/Flash"
	) as ColorRect
	assert(damage_flash.visible)
	assert(damage_flash.color.a >= 0.4)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame

	assert(player.is_dead)
	assert(player.ragdoll_controller.is_ragdoll_active())
	var ragdoll_head: PhysicalBone3D = (
		player.ragdoll_controller.get_ragdoll_head_bone()
	)
	assert(ragdoll_head != null)
	assert(player.camera.get_parent() == ragdoll_head)
	assert(player.camera.global_transform.is_equal_approx(
		ragdoll_head.global_transform * player.camera.transform
	))
	assert(
		not player.ragdoll_controller.get_last_impact_bone_name().is_empty()
	)
	var applied_impulse: Vector3 = (
		player.ragdoll_controller.get_last_applied_impulse()
	)
	assert(applied_impulse.dot(Vector3.FORWARD) > 0.0)
	assert(
		applied_impulse.length()
		<= player.ragdoll_controller.maximum_death_impulse + 0.001
	)
	assert(spawned_item_paths.size() == 2)
	assert(pistol.resource_path in spawned_item_paths)
	assert(sniper.resource_path in spawned_item_paths)
	assert("death_test_pistol" in spawned_item_instance_ids)
	assert("death_test_sniper" in spawned_item_instance_ids)
	assert(player.inventory.is_empty())
	assert(player.inventory_instance_ids.is_empty())
	assert(player.server_inventory_paths.is_empty())
	assert(player.server_inventory_instance_ids.is_empty())
	assert(player.selected_inventory_index == -1)
	assert(player.equipped_item_resource_path.is_empty())
	assert(is_equal_approx(player.camera.fov, unscoped_camera_fov))
	assert(is_equal_approx(player._weapon_aim_sensitivity_multiplier, 1.0))

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

	var final_hit_particles := get_tree().get_nodes_in_group(
		"final_hit_blood_particles"
	)
	assert(final_hit_particles.size() == 1)
	var final_particles := final_hit_particles[0] as GPUParticles3D
	assert(final_particles != null)
	assert(
		final_particles.scene_file_path
		== "res://scenes/particles/bloodsplatter.tscn"
	)
	assert(final_particles.one_shot)
	assert(
		(final_particles.global_position - hit_position).dot(Vector3.FORWARD)
		> player.blood_effects.final_hit_exit_padding
	)
	var final_process_material := (
		final_particles.process_material as ParticleProcessMaterial
	)
	assert(final_process_material != null)
	assert(
		final_process_material.direction.is_equal_approx(Vector3.FORWARD)
	)
	var minimum_death_camera_height := player.camera.global_position.y

	for _frame_index in range(30):
		await get_tree().physics_frame
		minimum_death_camera_height = minf(
			minimum_death_camera_height,
			player.camera.global_position.y
		)

	assert(
		minimum_death_camera_height
		< camera_height_before_death - 0.2,
		"Todeskamera-Minimum %.3f, Start %.3f" % [
			minimum_death_camera_height,
			camera_height_before_death,
		]
	)

	player._sync_revive_result(
		player.revive_health,
		player.global_position
	)
	assert(not player.is_dead)
	assert(not player.ragdoll_controller.is_ragdoll_active())
	assert(player.camera.get_parent() == player.head)

	print("PLAYER_DEATH_DROP_BLOOD_TEST_PASS")
	get_tree().quit()


func server_spawn_dropped_item(
	item_path: String,
	spawn_position: Vector3,
	_spawn_rotation: Vector3,
	item_instance_id: String = ""
) -> void:
	spawned_item_paths.append(item_path)
	spawned_item_positions.append(spawn_position)
	spawned_item_instance_ids.append(item_instance_id)
