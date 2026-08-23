extends Node3D


func _ready() -> void:
	var player := preload(
		"res://scenes/PlayerController.tscn"
	).instantiate() as FPSController
	player.name = "1"
	var authored_head_z := (
		player.get_node("Head") as Node3D
	).position.z
	add_child(player)
	await get_tree().create_timer(0.15).timeout

	var skeleton := player.player_skeleton
	var animation_player := player.get_node(
		"playerModell/AnimationPlayer"
	) as AnimationPlayer
	var head_bone := skeleton.find_bone(&"Head")
	assert(head_bone >= 0)
	player.player_animation.set_process(false)
	animation_player.play(&"ual/Sprint")
	animation_player.advance(0.25)
	skeleton.force_update_all_bone_transforms()

	var animated_head := (
		skeleton.global_transform
		* skeleton.get_bone_global_pose(head_bone)
	).origin
	var resting_head := (
		skeleton.global_transform
		* skeleton.get_bone_global_rest(head_bone)
	).origin
	var animated_offset := (
		player.to_local(animated_head).z
		- player.to_local(resting_head).z
	)
	assert(absf(animated_offset) > 0.2)

	player._sprint_active = true
	player.velocity = Vector3(0.0, 0.0, -player.sprint_speed)
	player._update_camera_shoulder_follow(1.0)
	var expected_offset := clampf(
		animated_offset,
		-player.camera_shoulder_max_offset,
		player.camera_shoulder_max_offset
	)
	assert(is_equal_approx(
		player.head.position.z,
		authored_head_z + expected_offset
	), "Schulterkamera %.5f, erwartet %.5f" % [
		player.head.position.z,
		authored_head_z + expected_offset,
	])
	assert(is_zero_approx(player.head.position.x))
	assert(is_zero_approx(player.head.rotation.x))

	player._sprint_active = false
	player.velocity = Vector3.ZERO
	player._update_camera_shoulder_follow(1.0)
	assert(not is_equal_approx(player.head.position.z, authored_head_z))

	animation_player.play(&"Idle", 0.0)
	animation_player.advance(0.25)
	skeleton.force_update_all_bone_transforms()
	player._update_camera_shoulder_follow(1.0)
	var idle_head := (
		skeleton.global_transform
		* skeleton.get_bone_global_pose(head_bone)
	).origin
	var idle_offset := (
		player.to_local(idle_head).z
		- player.to_local(resting_head).z
	)
	var expected_idle_offset := 0.0

	if absf(idle_offset) >= player.camera_shoulder_activation_offset:
		expected_idle_offset = clampf(
			idle_offset,
			-player.camera_shoulder_max_offset,
			player.camera_shoulder_max_offset
		)

	assert(is_equal_approx(
		player.head.position.z,
		authored_head_z + expected_idle_offset
	))

	print("PLAYER_CAMERA_SHOULDER_SMOKE_TEST_OK")
	get_tree().quit(0)
