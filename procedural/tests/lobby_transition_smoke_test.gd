extends Node


func _ready() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var tree := get_tree()

	# Keep this probe alive while Networking replaces the current lobby scene.
	tree.current_scene = null
	reparent(tree.root)
	Networking.start_game_from_lobby()

	for _frame in range(240):
		await tree.process_frame

		var current_scene := tree.current_scene

		if (
			current_scene == null
			or current_scene.scene_file_path != "res://scenes/main.tscn"
		):
			continue

		var player := current_scene.get_node_or_null("Players/1") as FPSController
		var generator := current_scene.get_node_or_null(
			"ProceduralLevelGenerator"
		) as ProceduralLevelGenerator

		if (
			player != null
			and generator != null
			and not generator.generated_rooms.is_empty()
			and not bool(generator.get("_generation_running"))
		):
			var fog_error := _validate_fog_environments(
				current_scene,
				player,
				generator
			)

			if not fog_error.is_empty():
				push_error(
					"LOBBY_TRANSITION_SMOKE_TEST_FAILED: " + fog_error
				)
				tree.quit(1)
				return

			print("LOBBY_TRANSITION_SMOKE_TEST_OK")
			await tree.process_frame
			await tree.process_frame
			tree.quit(0)
			return

	push_error(
		"LOBBY_TRANSITION_SMOKE_TEST_FAILED: synchronized game startup timed out."
	)
	tree.quit(1)


func _validate_fog_environments(
	main_scene: Node,
	player: FPSController,
	generator: ProceduralLevelGenerator
) -> String:
	var outside_world := main_scene.get_node_or_null(
		"Environment/Outside"
	) as WorldEnvironment

	if outside_world == null or outside_world.environment == null:
		return "The outside fog environment is missing."

	if not bool(
		outside_world.environment.get_meta(
			&"options_default_fog",
			outside_world.environment.fog_enabled
		)
	):
		return "The outside environment no longer defines fog."

	if (
		not main_scene.has_method("get_indoor_environment")
		or not main_scene.has_method("update_local_camera_environment")
	):
		return "The indoor camera environment controller is missing."

	var indoor_environment := main_scene.call(
		"get_indoor_environment"
	) as Environment

	if (
		indoor_environment == null
		or indoor_environment.fog_enabled
		or indoor_environment.volumetric_fog_enabled
	):
		return "The indoor camera environment still contains fog."

	var original_transform := player.global_transform
	var room_center := generator.generated_bounds[0].get_center()
	player.global_position = Vector3(
		room_center.x,
		player.global_position.y,
		room_center.z
	)
	main_scene.call("update_local_camera_environment")

	if player.camera.environment != indoor_environment:
		player.global_transform = original_transform
		main_scene.call("update_local_camera_environment")
		return "The player camera did not switch to the indoor environment."

	player.global_transform = original_transform
	main_scene.call("update_local_camera_environment")

	if player.camera.environment != null:
		return "The player camera did not restore outside fog."

	var feed_camera := main_scene.get_node_or_null(
		"Hall/Van/CameraMonitor/SubViewport/FeedCamera"
	) as Camera3D

	if (
		feed_camera == null
		or feed_camera.environment == null
		or feed_camera.environment.fog_enabled
		or feed_camera.environment.volumetric_fog_enabled
	):
		return "The van camera feed still contains fog."

	return ""
