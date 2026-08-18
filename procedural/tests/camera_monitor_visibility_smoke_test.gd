extends Node3D


func _ready() -> void:
	var players := Node3D.new()
	players.name = "Players"
	add_child(players)

	var player_scene := load(
		"res://scenes/PlayerController.tscn"
	) as PackedScene
	var viewer := player_scene.instantiate()
	viewer.name = "1"
	players.add_child(viewer)
	viewer.set_physics_process(false)

	var observed_player := player_scene.instantiate()
	observed_player.name = "2"
	players.add_child(observed_player)

	var monitor_scene := load(
		"res://scenes/props/van/CameraMonitor.tscn"
	) as PackedScene
	var monitor := monitor_scene.instantiate()
	add_child(monitor)

	await get_tree().process_frame
	await get_tree().process_frame

	viewer.apply_hide_own_body(false)
	monitor.refresh_cameras()
	assert(monitor.get_camera_count() == 2)
	assert(monitor.get_current_camera_id() == -1)
	assert(monitor.begin_view(viewer))
	assert(viewer.is_model_hidden_for_camera_monitor())
	assert(not _mesh(viewer, "Body").visible)
	assert(not _mesh(viewer, "Arm_R").visible)
	assert(_mesh(observed_player, "Body").visible)

	monitor.next_camera()
	assert(monitor.get_current_camera_id() == -2)
	assert(viewer.is_model_hidden_for_camera_monitor())
	assert(observed_player.is_model_hidden_for_camera_monitor())
	assert(not _mesh(viewer, "Body").visible)
	assert(not _mesh(viewer, "Arm_R").visible)
	assert(not _mesh(observed_player, "Body").visible)
	assert(not _mesh(observed_player, "Arm_R").visible)

	monitor.previous_camera()
	assert(monitor.get_current_camera_id() == -1)
	assert(not observed_player.is_model_hidden_for_camera_monitor())
	assert(_mesh(observed_player, "Body").visible)
	assert(_mesh(observed_player, "Arm_R").visible)
	assert(not _mesh(viewer, "Body").visible)

	viewer.exit_camera_monitor()
	assert(not viewer.is_model_hidden_for_camera_monitor())
	assert(_mesh(viewer, "Body").visible)
	assert(_mesh(viewer, "Arm_R").visible)

	viewer.apply_hide_own_body(true)
	assert(monitor.begin_view(viewer))
	assert(not _mesh(viewer, "Body").visible)
	assert(not _mesh(viewer, "Arm_R").visible)
	viewer.exit_camera_monitor()
	assert(not _mesh(viewer, "Body").visible)
	assert(_mesh(viewer, "Arm_R").visible)

	print("CAMERA_MONITOR_VISIBILITY_SMOKE_TEST_OK")
	get_tree().quit()


func _mesh(player: FPSController, mesh_name: String) -> VisualInstance3D:
	return player.get_node(
		"playerModell/Armature/Skeleton3D/%s" % mesh_name
	) as VisualInstance3D
