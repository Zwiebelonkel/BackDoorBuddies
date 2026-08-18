extends Node


func _ready() -> void:
	var player_scene := load(
		"res://scenes/PlayerController.tscn"
	) as PackedScene
	var local_player := player_scene.instantiate()
	local_player.name = "1"
	add_child(local_player)
	local_player.set_physics_process(false)

	var remote_player := player_scene.instantiate()
	remote_player.name = "2"
	add_child(remote_player)

	await get_tree().process_frame
	await get_tree().process_frame

	var local_skeleton := local_player.get_node(
		"playerModell/Armature/Skeleton3D"
	)
	var remote_skeleton := remote_player.get_node(
		"playerModell/Armature/Skeleton3D"
	)

	local_player.apply_hide_own_body(false)
	assert(local_skeleton.get_node("Body").visible)
	assert(local_skeleton.get_node("Foot_L").visible)
	assert(local_skeleton.get_node("Waist").visible)
	assert(local_skeleton.get_node("Arm_L").visible)
	assert(local_skeleton.get_node("Arm_R").visible)
	assert(not local_player.is_own_body_hidden())

	local_player.apply_hide_own_body(true)
	assert(not local_skeleton.get_node("Body").visible)
	assert(not local_skeleton.get_node("Foot_L").visible)
	assert(not local_skeleton.get_node("Foot_R").visible)
	assert(not local_skeleton.get_node("UpperLeg_L").visible)
	assert(not local_skeleton.get_node("UpperLeg_R").visible)
	assert(not local_skeleton.get_node("Waist").visible)
	assert(local_skeleton.get_node("Arm_L").visible)
	assert(local_skeleton.get_node("Arm_R").visible)
	assert(local_skeleton.get_node("UpperArm_L").visible)
	assert(local_skeleton.get_node("UpperArm_R").visible)
	assert(local_player.is_own_body_hidden())

	remote_player.apply_hide_own_body(true)
	assert(remote_skeleton.get_node("Body").visible)
	assert(remote_skeleton.get_node("Foot_L").visible)
	assert(remote_skeleton.get_node("Arm_L").visible)

	var options_scene := load(
		"res://scenes/options_menu.tscn"
	) as PackedScene
	var options_menu := options_scene.instantiate()
	assert(
		options_menu.has_node(
			"PanelContainer/MarginContainer/VBoxContainer/Tabs/General/"
			+ "GeneralMargin/GeneralOptions/HideOwnBodyRow/"
			+ "HideOwnBodyCheckBox"
		)
	)
	options_menu.free()

	print("LOCAL_MODEL_VISIBILITY_SMOKE_TEST_OK")
	get_tree().quit()
