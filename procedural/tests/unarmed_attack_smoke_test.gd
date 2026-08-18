extends Node3D


func _ready() -> void:
	var players := Node3D.new()
	players.name = "Players"
	add_child(players)

	var player_scene := load(
		"res://scenes/PlayerController.tscn"
	) as PackedScene
	var attacker := player_scene.instantiate()
	attacker.name = "1"
	players.add_child(attacker)
	attacker.set_physics_process(false)

	var target := player_scene.instantiate()
	target.name = "2"
	target.position = Vector3(0.0, 0.0, -1.25)
	players.add_child(target)

	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame

	assert(attacker.equipped_item_resource_path.is_empty())
	assert(attacker.held_item_instance == null)
	assert(attacker.player_animation.has_animation(&"ual/Punch_Jab"))
	assert(attacker.player_animation.has_animation(&"ual/Punch_Cross"))

	var starting_health: float = target.current_health
	attacker._use_held_item()
	await get_tree().physics_frame
	assert(
		is_equal_approx(
			target.current_health,
			starting_health - attacker.unarmed_damage
		)
	)

	var health_after_first_punch: float = target.current_health
	attacker._use_held_item()
	await get_tree().physics_frame
	assert(is_equal_approx(target.current_health, health_after_first_punch))

	await get_tree().create_timer(0.52).timeout
	attacker._use_held_item()
	await get_tree().physics_frame
	assert(
		is_equal_approx(
			target.current_health,
			health_after_first_punch - attacker.unarmed_damage
		)
	)

	var health_after_second_punch: float = target.current_health
	attacker.equipped_item_resource_path = (
		"res://resources/items/1911.tres"
	)
	attacker._last_attack_time_by_type.clear()
	attacker._server_process_player_attack(
		2,
		&"unarmed",
		target.global_position + Vector3.UP,
		Vector3.BACK
	)
	assert(is_equal_approx(target.current_health, health_after_second_punch))

	print("UNARMED_ATTACK_SMOKE_TEST_OK")
	get_tree().quit()
