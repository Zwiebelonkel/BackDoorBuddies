extends "res://scripts/lobby.gd"


func _ready() -> void:
	super._ready()
	var exit_code := await _run_test()
	get_tree().quit(exit_code)


func _run_test() -> int:
	await get_tree().process_frame
	await get_tree().process_frame
	_spawn_lobby_weapons()
	await get_tree().process_frame

	var dummy := $Players.get_node_or_null("0") as FPSController
	var pistol := $WeaponPickups/PistolPickup as PickupItem
	var knife := $WeaponPickups/KnifePickup as PickupItem
	var machine_pistol := $WeaponPickups/MachinePistolPickup as PickupItem
	var flashlight := $WeaponPickups/FlashlightPickup as PickupItem
	var note := $WeaponPickups/TargetClueNotePickup as PickupItem
	var drive := $WeaponPickups/TargetClueDrivePickup as PickupItem
	var start_button := $StartButton
	var multiplayer_button := $MultiplayerButton

	if dummy == null or dummy.get_multiplayer_authority() != 0:
		return _fail("Lobby training dummy is not a non-player FPSController.")

	if (
		pistol == null
		or pistol.item_data == null
		or pistol.item_data.item_id != &"1911"
		or knife == null
		or knife.item_data == null
		or knife.item_data.item_id != &"knife"
		or machine_pistol == null
		or machine_pistol.item_data == null
		or flashlight == null
		or flashlight.item_data == null
		or flashlight.item_data.item_id != &"flashlight"
		or note == null
		or note.item_data == null
		or note.item_data.item_id != &"target_clue_age"
		or not note.item_data.is_mission_clue
		or drive == null
		or drive.item_data == null
		or drive.item_data.item_id != &"target_clue_hair_drive"
		or not drive.item_data.is_mission_clue
	):
		return _fail("A permanent lobby weapon, flashlight or clue pickup is missing.")

	var flashlight_is_spawnable := false
	var note_is_spawnable := false
	var drive_is_spawnable := false

	for scene_index in range($WeaponSpawner.get_spawnable_scene_count()):
		var scene_path: String = $WeaponSpawner.get_spawnable_scene(scene_index)

		match scene_path:
			"res://procedural/items/flashlight_pickup.tscn":
				flashlight_is_spawnable = true
			"res://procedural/items/lobby_target_clue_note_pickup.tscn":
				note_is_spawnable = true
			"res://procedural/items/lobby_target_clue_drive_pickup.tscn":
				drive_is_spawnable = true

	if not flashlight_is_spawnable or not note_is_spawnable or not drive_is_spawnable:
		return _fail("A lobby item is not registered for multiplayer spawning.")

	if (
		start_button == null
		or not start_button.has_method("request_interaction")
		or not start_button.has_method("get_interaction_text")
	):
		return _fail("Lobby 3D host start button is incomplete.")

	if (
		multiplayer_button == null
		or not multiplayer_button.has_method("request_interaction")
		or not multiplayer_button.has_method("get_interaction_text")
		or not Networking.has_method("open_lobby_invite_overlay")
		or not Steam.has_method("activateGameOverlayInviteDialog")
	):
		return _fail("Lobby 3D multiplayer invite button is incomplete.")

	if (
		$PlayerSpawner.spawn_path != NodePath("../Players")
		or $WeaponSpawner.spawn_path != NodePath("../WeaponPickups")
		or $ItemSpawner.spawn_path != NodePath("../DroppedItems")
	):
		return _fail("Lobby multiplayer spawners are configured incorrectly.")

	spawn_player(1)
	var player := $Players.get_node_or_null("1") as FPSController

	if player == null:
		return _fail("Lobby could not spawn a connected player.")

	var standing_shape := player.standing_collision.shape as CapsuleShape3D

	if (
		player.is_crouching()
		or player.standing_collision.disabled
		or not player.crouch_collision.disabled
		or not is_equal_approx(player.head.position.y, player.stand_head_y)
		or standing_shape == null
		or not is_equal_approx(standing_shape.height, player.stand_height)
	):
		_cleanup_player(player)
		return _fail("A lobby player does not spawn in the standing stance.")

	var local_name_label := player.get_node_or_null(
		"PlayerNameLabel"
	) as Label3D

	if local_name_label == null or local_name_label.visible:
		_cleanup_player(player)
		return _fail("The local player name label is missing or visible.")

	Networking._sync_player_display_names({2: "Steam\nTester"})
	spawn_player(2)
	await get_tree().process_frame
	var remote_player := $Players.get_node_or_null("2") as FPSController
	var remote_name_label := (
		remote_player.get_node_or_null("PlayerNameLabel") as Label3D
		if remote_player != null
		else null
	)

	if (
		remote_name_label == null
		or not remote_name_label.visible
		or remote_name_label.text != "Steam Tester"
	):
		if remote_player != null:
			_cleanup_player(remote_player)
		_cleanup_player(player)
		return _fail("Remote player name label is not configured correctly.")

	_cleanup_player(remote_player)
	Networking._sync_player_display_names({})

	player.set_physics_process(false)
	player.global_position = dummy.global_position + Vector3(0.0, 0.0, 1.2)

	for _frame in range(3):
		await get_tree().process_frame
	await get_tree().physics_frame

	var dummy_hit_position := dummy.global_position + Vector3.UP * 1.65
	var health_before_attacks := dummy.current_health
	player.equipped_item_resource_path = "res://resources/items/1911.tres"
	player.request_player_attack(
		dummy,
		&"pistol",
		dummy_hit_position,
		Vector3.FORWARD
	)
	await get_tree().process_frame

	if dummy.current_health >= health_before_attacks:
		_cleanup_player(player)
		return _fail("Lobby pistol could not damage the training dummy.")

	var health_after_pistol := dummy.current_health
	player.equipped_item_resource_path = "res://resources/items/knife.tres"
	player.request_player_attack(
		dummy,
		&"knife",
		dummy_hit_position,
		Vector3.FORWARD
	)
	await get_tree().process_frame

	if dummy.current_health >= health_after_pistol:
		_cleanup_player(player)
		return _fail("Lobby knife could not damage the training dummy.")

	dummy.server_receive_damage(
		dummy.maximum_health,
		1,
		dummy.global_position + Vector3.UP,
		Vector3.FORWARD,
		Vector3(0.0, 0.0, -2.0)
	)
	await get_tree().process_frame
	await get_tree().physics_frame

	if not dummy.is_dead:
		_cleanup_player(player)
		return _fail("Lobby training dummy did not enter its dead state.")

	if not dummy.ragdoll_controller.is_ragdoll_active():
		_cleanup_player(player)
		return _fail("Lobby training dummy did not ragdoll after lethal damage.")

	var ragdoll_start_position: Vector3 = (
		dummy.ragdoll_controller.get_ragdoll_center_position()
	)

	for _frame in range(90):
		await get_tree().physics_frame

	var ragdoll_end_position: Vector3 = (
		dummy.ragdoll_controller.get_ragdoll_center_position()
	)

	if (
		not ragdoll_end_position.is_finite()
		or ragdoll_start_position.distance_to(ragdoll_end_position) > 6.0
	):
		_cleanup_player(player)
		return _fail("Lobby training dummy ragdoll became unstable.")

	player.global_position = (
		dummy.ragdoll_controller.get_ragdoll_center_position()
		+ Vector3.RIGHT
	)
	dummy.request_interaction(player)
	await get_tree().process_frame

	if dummy.is_dead or dummy.current_health <= 0.0:
		_cleanup_player(player)
		return _fail("Lobby training dummy could not be revived with interaction.")

	if dummy.ragdoll_controller.is_ragdoll_active():
		_cleanup_player(player)
		return _fail("Revived lobby training dummy remained in ragdoll mode.")

	_cleanup_player(player)
	print("LOBBY_SMOKE_TEST_OK")
	return 0


func _cleanup_player(player: FPSController) -> void:
	var hud := player.player_hud
	players.erase(player)
	$Players.remove_child(player)
	player.free()

	if is_instance_valid(hud):
		hud.queue_free()


func _fail(message: String) -> int:
	push_error("LOBBY_SMOKE_TEST_FAILED: " + message)
	return 1
