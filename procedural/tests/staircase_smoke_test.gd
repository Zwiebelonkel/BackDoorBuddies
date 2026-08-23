extends "res://scripts/lobby.gd"


func _ready() -> void:
	super._ready()
	var exit_code := await _run_test()
	get_tree().quit(exit_code)


func _run_test() -> int:
	await get_tree().process_frame
	await get_tree().physics_frame

	var floor_mesh := ($Room/Floor as MeshInstance3D).mesh as BoxMesh
	var floor_shape := ($Collision/Floor as CollisionShape3D).shape as BoxShape3D
	var north_wall_shape := (
		$Collision/NorthWall as CollisionShape3D
	).shape as BoxShape3D
	var staircase := $TestStaircase as StaticBody3D
	var ramp_collision := (
		staircase.get_node_or_null("RampCollision") as CollisionShape3D
		if staircase != null
		else null
	)
	var left_rail_collision := (
		staircase.get_node_or_null(
			"LeftLowerRailCollision"
		) as CollisionShape3D
		if staircase != null
		else null
	)
	var platform_shape := (
		$Mezzanine/Collision/Platform as CollisionShape3D
	).shape as BoxShape3D

	if (
		floor_mesh == null
		or floor_mesh.size.z < 17.9
		or floor_shape == null
		or floor_shape.size.z < 17.9
		or north_wall_shape == null
		or north_wall_shape.size.y < 5.9
		or $Collision/SouthWall.position.z < 12.9
		or staircase == null
		or int(staircase.get_meta("step_count", 0)) != 12
		or ramp_collision == null
		or not ramp_collision.shape is ConvexPolygonShape3D
		or left_rail_collision == null
		or left_rail_collision.basis.z.y < 0.4
		or not staircase.has_node("RightLowerRailCollision")
		or platform_shape == null
		or platform_shape.size.x < 4.0
		or not $Mezzanine/Collision.has_node("NorthGuard")
	):
		return _fail("Expanded lobby stair geometry is incomplete.")

	spawn_player(1)
	var player := $Players.get_node_or_null("1") as FPSController

	if player == null:
		return _fail("Stair test player could not be spawned.")

	if (
		player.floor_snap_length < 0.3
		or not player.floor_constant_speed
		or not player.floor_stop_on_slope
		or player.floor_max_angle < deg_to_rad(44.0)
	):
		_cleanup_player(player)
		return _fail("Player stair and slope movement is not configured.")

	var movement_error := await _test_stair_movement(player)
	_cleanup_player(player)

	if not movement_error.is_empty():
		return _fail(movement_error)

	print("STAIRCASE_SMOKE_TEST_OK")
	return 0


func _test_stair_movement(player: FPSController) -> String:
	var bottom := $TestStaircase/Bottom as Marker3D
	var top := $TestStaircase/Top as Marker3D

	player.velocity = Vector3.ZERO
	player.global_position = bottom.global_position
	player.global_rotation = Vector3(0.0, PI, 0.0)

	for _frame in range(4):
		await get_tree().physics_frame

	Input.action_press("move_forward")
	var reached_top := false

	for _frame in range(180):
		await get_tree().physics_frame

		if (
			player.global_position.y >= top.global_position.y - 0.25
			and player.global_position.z >= top.global_position.z - 0.2
		):
			reached_top = true
			break

	Input.action_release("move_forward")

	for _frame in range(6):
		await get_tree().physics_frame

	if (
		not reached_top
		or not player.global_position.is_finite()
		or not player.is_on_floor()
	):
		return "Player could not walk up the lobby staircase without jumping."

	player.velocity = Vector3.ZERO
	player.global_position = top.global_position
	player.global_rotation = Vector3.ZERO

	for _frame in range(4):
		await get_tree().physics_frame

	Input.action_press("move_forward")
	var reached_bottom := false

	for _frame in range(180):
		await get_tree().physics_frame

		if (
			player.global_position.y <= bottom.global_position.y + 0.15
			and player.global_position.z <= bottom.global_position.z + 0.25
		):
			reached_bottom = true
			break

	Input.action_release("move_forward")

	for _frame in range(6):
		await get_tree().physics_frame

	if (
		not reached_bottom
		or not player.global_position.is_finite()
		or not player.is_on_floor()
	):
		return "Player could not walk down the lobby staircase continuously."

	return ""


func _cleanup_player(player: FPSController) -> void:
	var hud := player.player_hud
	players.erase(player)
	$Players.remove_child(player)
	player.free()

	if is_instance_valid(hud):
		hud.queue_free()


func _fail(message: String) -> int:
	Input.action_release("move_forward")
	push_error("STAIRCASE_SMOKE_TEST_FAILED: " + message)
	return 1
